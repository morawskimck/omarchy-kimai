const { test } = require("node:test")
const { loadModel, same, assert } = require("./helpers")
const M = loadModel()

test("curlConfig escapes quotes and backslashes and drops newlines", () => {
  assert.equal(M.curlConfig("abc123"), 'header = "Authorization: Bearer abc123"\n')
  assert.equal(M.curlConfig('a"b\\c'), 'header = "Authorization: Bearer a\\"b\\\\c"\n')
  assert.equal(M.curlConfig("tok\nen\r"), 'header = "Authorization: Bearer token"\n')
})

test("buildCurlArgs never carries the token and only adds a body when given", () => {
  const get = M.buildCurlArgs("GET", "https://k.example/api/timesheets/active", null)
  same(get, ["curl", "-q", "-sS", "--connect-timeout", "5", "--max-time", "15", "--config", "-", "-X", "GET",
             "-H", "Accept: application/json", "-w", "\n%{http_code}", "https://k.example/api/timesheets/active"])
  const post = M.buildCurlArgs("POST", "https://k.example/api/timesheets", { project: 1, description: 'say "hi"' })
  same(post.slice(-4), ["Content-Type: application/json", "--data-binary", '{"project":1,"description":"say \\"hi\\""}', "https://k.example/api/timesheets"])
  assert.ok(!post.join(" ").includes("Bearer"))
})

test("queryString skips empty values and encodes the rest", () => {
  assert.equal(M.queryString({}), "")
  assert.equal(M.queryString({ a: 1, b: null, c: "", d: undefined, e: "x y&z" }), "?a=1&e=x%20y%26z")
  assert.equal(M.apiUrl("https://k.example", "/timesheets", { size: 10 }), "https://k.example/api/timesheets?size=10")
})

test("parseCurlOutput splits the status line written by -w", () => {
  same(M.parseCurlOutput('[{"id":1}]\n200'), { status: 200, body: '[{"id":1}]' })
  same(M.parseCurlOutput("\n204"), { status: 204, body: "" })
  same(M.parseCurlOutput("line1\nline2\n404"), { status: 404, body: "line1\nline2" })
  same(M.parseCurlOutput(""), { status: 0, body: "" })
})

test("classifyResponse maps HTTP results to the kinds the service reacts to", () => {
  same(M.classifyResponse(0, '[{"id":1}]\n200', ""), { kind: "ok", status: 200, data: [{ id: 1 }], message: "" })
  same(M.classifyResponse(0, "\n204", ""), { kind: "ok", status: 204, data: null, message: "" })
  assert.equal(M.classifyResponse(0, '{"code":401,"message":"Invalid credentials"}\n401', "").kind, "unauthorized")
  assert.equal(M.classifyResponse(0, '{"message":"Not Found"}\n404', "").kind, "notfound")
})

test("a proxy error page or a 200 with HTML never throws and is treated as a server problem", () => {
  const bad = M.classifyResponse(0, "<html><body>502 Bad Gateway</body></html>\n502", "")
  assert.equal(bad.kind, "server")
  assert.equal(bad.message, "Kimai answered HTTP 502")
  const portal = M.classifyResponse(0, "<html>Login to Wi-Fi</html>\n200", "")
  same(portal, { kind: "server", status: 200, data: null, message: "Unexpected response from the server" })
})

test("curl failures become network results with curl's own message", () => {
  same(M.classifyResponse(6, "", "curl: (6) Could not resolve host: k.example\n"),
       { kind: "network", status: 0, data: null, message: "Could not resolve host: k.example" })
  assert.equal(M.classifyResponse(28, "", "").message, "Network error (curl exit 28)")
})

test("extractError collects nested form errors, else falls back to message", () => {
  const nested = { code: 400, message: "Validation Failed", errors: { children: {
    begin: { errors: ["The begin date cannot be in the future."] },
    project: {}, activity: { errors: ["This value is not valid."] } } } }
  assert.equal(M.extractError(nested), "The begin date cannot be in the future. This value is not valid.")
  const flat = { code: 400, message: "Validation Failed", errors: { errors: ["Maximum 1 active records allowed."], children: {} } }
  assert.equal(M.extractError(flat), "Maximum 1 active records allowed.")
  assert.equal(M.extractError({ message: "Bad things" }), "Bad things")
  assert.equal(M.extractError(null), "Kimai rejected the request")
  assert.equal(M.classifyResponse(0, JSON.stringify(nested) + "\n400", "").message,
    "The begin date cannot be in the future. This value is not valid.")
})

test("nextPollSeconds backs off from 30 s, doubling up to 300 s", () => {
  assert.equal(M.nextPollSeconds(0, 30), 30)
  assert.equal(M.nextPollSeconds(0, 120), 120)
  assert.deepEqual([1, 2, 3, 4, 5, 9].map(f => M.nextPollSeconds(f, 10)), [30, 60, 120, 240, 300, 300])
  assert.equal(M.nextPollSeconds(1, 120), 120)
})

test("secretToolArgs addresses one entry per server URL", () => {
  same(M.secretToolArgs("lookup", "https://k.example"), ["secret-tool", "lookup", "application", "omarchy-kimai", "url", "https://k.example"])
  same(M.secretToolArgs("clear", "https://k.example"), ["secret-tool", "clear", "application", "omarchy-kimai", "url", "https://k.example"])
  same(M.secretToolArgs("store", "https://k.example"),
       ["secret-tool", "store", "--label=Omarchy Kimai (https://k.example)", "application", "omarchy-kimai", "url", "https://k.example"])
})

test("extractError understands the 400 body captured from Kimai in Task 1", () => {
  const body = require("./fixtures/error-400.json")
  const message = M.extractError(body)
  assert.notEqual(message, "Kimai rejected the request")
  assert.notEqual(message, "Validation Failed")
  assert.ok(message.length > 0)
})

test("403 is a permission problem with Kimai's own message, not a bad token", () => {
  same(M.classifyResponse(0, '{"code":403,"message":"Access denied."}\n403', ""),
       { kind: "forbidden", status: 403, data: { code: 403, message: "Access denied." }, message: "Access denied." })
  assert.equal(M.classifyResponse(0, "\n403", "").message, "Kimai refused this action")
})

test("curl ignores the user's ~/.curlrc (-q must come first) and gives up connecting after 5 s", () => {
  const args = M.buildCurlArgs("GET", "https://k.example/api/version", null)
  assert.equal(args[1], "-q")
  assert.equal(args[args.indexOf("--connect-timeout") + 1], "5")
})
