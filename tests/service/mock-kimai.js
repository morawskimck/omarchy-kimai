// Minimal Kimai API double for tests/service. Listens on a random localhost
// port and prints "PORT <n>" once ready. Control endpoints (no auth):
//   POST /__mode  {"mode": "ok" | "html" | "down"}  html = 502 page, down = drop connection
//   POST /__token {"token": "..."}                   rotate the accepted token
//   GET  /__log                                      every API request seen so far
const http = require("node:http")

let token = "test-token"
let mode = "ok"
let nextId = 100
const log = []

const project = { id: 2, name: "Website", customer: { id: 1, name: "Acme" } }
const activities = { 3: { id: 3, name: "Code review" }, 9: { id: 9, name: "Meetings" } }

function pad2(n) { return (n < 10 ? "0" : "") + n }
function stamp(ms) {
  const d = new Date(ms)
  let off = -d.getTimezoneOffset()
  const sign = off >= 0 ? "+" : "-"
  off = Math.abs(off)
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}${sign}${pad2(Math.floor(off / 60))}${pad2(off % 60)}`
}
const wall = s => String(s).slice(0, 19)

const now = Date.now()
const sheets = [{ id: 5, begin: stamp(now - 3 * 3600e3), end: stamp(now - 2 * 3600e3), duration: 3600,
                  description: "PR review", tags: ["review"], activity: 3, project: 2 }]

function expand(t) {
  return Object.assign({}, t, { activity: activities[t.activity], project })
}

function json(res, status, data) {
  res.writeHead(status, { "content-type": "application/json" })
  res.end(data === undefined ? "" : JSON.stringify(data))
}

function stop(t) {
  t.end = stamp(Date.now())
  t.duration = 60
}

function create(fields) {
  sheets.filter(t => !t.end).forEach(stop) // activeEntriesHardLimit = 1
  const t = { id: nextId++, begin: stamp(Date.now()), end: null, duration: 0,
              description: fields.description || "", tags: fields.tags ? String(fields.tags).split(",").filter(Boolean) : [],
              activity: Number(fields.activity), project: Number(fields.project) }
  sheets.push(t)
  return t
}

function route(req, res, url, body) {
  const m = req.method
  const p = url.pathname
  let match
  if (m === "GET" && p === "/api/users/me") return json(res, 200, { id: 1, username: "admin", alias: null, timezone: "Europe/Warsaw" })
  if (m === "GET" && p === "/api/version") return json(res, 200, { version: "2.67.0", versionId: 26700 })
  if (m === "GET" && p === "/api/config/timesheet") return json(res, 200, { trackingMode: "default", activeEntriesHardLimit: 1 })
  if (m === "GET" && p === "/api/timesheets/active") return json(res, 200, sheets.filter(t => !t.end).map(expand))
  if (m === "GET" && p === "/api/timesheets/recent") return json(res, 200, sheets.filter(t => t.end).slice().reverse().map(expand))
  if (m === "GET" && p === "/api/timesheets") return json(res, 200, sheets.slice().reverse().map(expand))
  if (m === "POST" && p === "/api/timesheets") {
    const f = JSON.parse(body || "{}")
    if (!activities[f.activity] || Number(f.project) !== 2)
      return json(res, 400, { code: 400, message: "Validation Failed", errors: { children: { activity: { errors: ["This value is not valid."] } } } })
    return json(res, 200, create(f))
  }
  if ((match = /^\/api\/timesheets\/(\d+)\/stop$/.exec(p)) && m === "PATCH") {
    const t = sheets.find(s => s.id === Number(match[1]))
    if (!t) return json(res, 404, { message: "Not found" })
    stop(t)
    return json(res, 200, t)
  }
  if ((match = /^\/api\/timesheets\/(\d+)\/restart$/.exec(p)) && m === "PATCH") {
    const t = sheets.find(s => s.id === Number(match[1]))
    if (!t) return json(res, 404, { message: "Not found" })
    const copy = JSON.parse(body || "{}").copy === "all"
    return json(res, 200, create({ project: t.project, activity: t.activity,
                                   description: copy ? t.description : "", tags: copy ? t.tags.join(",") : "" }))
  }
  if ((match = /^\/api\/timesheets\/(\d+)$/.exec(p)) && m === "PATCH") {
    const t = sheets.find(s => s.id === Number(match[1]))
    if (!t) return json(res, 404, { message: "Not found" })
    const f = JSON.parse(body || "{}")
    const begin = f.begin ? f.begin : wall(t.begin)
    const end = f.end ? f.end : (t.end ? wall(t.end) : null)
    if (end && end <= begin)
      return json(res, 400, { code: 400, message: "Validation Failed", errors: { children: { end: { errors: ["End date must not be earlier then start date."] } } } })
    if (f.description !== undefined) t.description = f.description
    if (f.tags !== undefined) t.tags = String(f.tags).split(",").filter(Boolean)
    if (f.begin) t.begin = f.begin + stamp(Date.now()).slice(19)
    if (f.end) t.end = f.end + stamp(Date.now()).slice(19)
    return json(res, 200, t)
  }
  if (m === "GET" && p === "/api/projects") return json(res, 200, [{ id: 2, name: "Website", parentTitle: "Acme", customer: 1 }])
  if (m === "GET" && p === "/api/activities") {
    if (url.searchParams.get("globals") === "true") return json(res, 200, [{ id: 9, name: "Meetings", parentTitle: null, project: null }])
    return json(res, 200, [{ id: 3, name: "Code review", parentTitle: "Website", project: 2 }])
  }
  if (m === "GET" && p === "/api/tags") return json(res, 200, ["alpha", "review"])
  return json(res, 404, { message: "Not found" })
}

function control(req, res, url, body) {
  if (url.pathname === "/__mode") { mode = JSON.parse(body).mode; return json(res, 200, { mode }) }
  if (url.pathname === "/__token") { token = JSON.parse(body).token; return json(res, 200, {}) }
  if (url.pathname === "/__log") return json(res, 200, log)
  return json(res, 404, {})
}

const server = http.createServer((req, res) => {
  let body = ""
  req.on("data", chunk => { body += chunk })
  req.on("end", () => {
    const url = new URL(req.url, "http://localhost")
    if (url.pathname.startsWith("/__")) return control(req, res, url, body)
    log.push({ method: req.method, path: url.pathname, query: url.search, auth: req.headers.authorization || "", body })
    if (mode === "down") return req.socket.destroy()
    if (mode === "html") {
      res.writeHead(502, { "content-type": "text/html" })
      return res.end("<html><body>502 Bad Gateway</body></html>")
    }
    if (req.headers.authorization !== "Bearer " + token) return json(res, 401, { code: 401, message: "Invalid credentials" })
    route(req, res, url, body)
  })
})

server.listen(0, "127.0.0.1", () => console.log("PORT " + server.address().port))
