// Run with TZ=Europe/Warsaw (scripts/check.sh and CI set it).
const { test } = require("node:test")
const { loadModel, same, assert } = require("./helpers")
const M = loadModel()

test("normalizeUrl adds https, strips slashes and a pasted /api suffix", () => {
  same(M.normalizeUrl("kimai.example.com"), { ok: true, url: "https://kimai.example.com", error: "" })
  same(M.normalizeUrl("  https://Kimai.Example.com/api/  "), { ok: true, url: "https://kimai.example.com", error: "" })
  same(M.normalizeUrl("https://example.com/kimai/"), { ok: true, url: "https://example.com/kimai", error: "" })
  same(M.normalizeUrl("http://localhost:8001"), { ok: true, url: "http://localhost:8001", error: "" })
})

test("normalizeUrl rejects empty, plain-http remote hosts and junk", () => {
  assert.equal(M.normalizeUrl("").ok, false)
  assert.equal(M.normalizeUrl(null).ok, false)
  assert.equal(M.normalizeUrl("http://kimai.example.com").ok, false)
  assert.equal(M.normalizeUrl("https://exa mple.com").ok, false)
  assert.equal(M.normalizeUrl("ftp://kimai.example.com").ok, false)
})

test("parseConfig applies defaults, clamps numbers and survives bad JSON", () => {
  same(M.parseConfig(""), { url: "", pollSeconds: 30, labelMaxWidth: 180 })
  same(M.parseConfig("{not json"), { url: "", pollSeconds: 30, labelMaxWidth: 180 })
  same(M.parseConfig("[1,2]"), { url: "", pollSeconds: 30, labelMaxWidth: 180 })
  same(M.parseConfig('{"url":"kimai.example.com/","pollSeconds":2,"labelMaxWidth":9999}'),
       { url: "https://kimai.example.com", pollSeconds: 10, labelMaxWidth: 400 })
  same(M.parseConfig('{"pollSeconds":"abc","labelMaxWidth":null}'), { url: "", pollSeconds: 30, labelMaxWidth: 180 })
})

test("serializeConfig writes normalised, pretty JSON with a trailing newline", () => {
  assert.equal(M.serializeConfig({ url: "kimai.example.com", pollSeconds: 45 }),
    '{\n  "url": "https://kimai.example.com",\n  "pollSeconds": 45,\n  "labelMaxWidth": 180\n}\n')
})

test("parseKimaiDate honours the offset Kimai sends", () => {
  assert.equal(M.parseKimaiDate("2026-10-03T09:15:00+0200"), Date.UTC(2026, 9, 3, 7, 15, 0))
  assert.equal(M.parseKimaiDate("2026-10-03T09:15:00+02:00"), Date.UTC(2026, 9, 3, 7, 15, 0))
  assert.equal(M.parseKimaiDate("2026-10-03T09:15:00-0430"), Date.UTC(2026, 9, 3, 13, 45, 0))
  assert.equal(M.parseKimaiDate("2026-10-03T09:15:00Z"), Date.UTC(2026, 9, 3, 9, 15, 0))
  assert.ok(Number.isNaN(M.parseKimaiDate("yesterday")))
  assert.ok(Number.isNaN(M.parseKimaiDate(null)))
})

test("a Kimai profile timezone different from the machine's still yields correct elapsed time", () => {
  const begin = "2026-10-03T07:00:00+0000" // 09:00 in Warsaw
  const now = Date.UTC(2026, 9, 3, 8, 30, 0)
  assert.equal(M.elapsedSeconds(begin, now), 5400)
  assert.equal(M.timezoneMismatch(begin, M.localOffsetAt(now)), true)
  assert.equal(M.timezoneMismatch("2026-10-03T09:00:00+0200", M.localOffsetAt(now)), false)
})

test("wall-clock helpers keep Kimai's own date and time", () => {
  assert.equal(M.wallDate("2026-10-03T23:45:10+0200"), "2026-10-03")
  assert.equal(M.wallTime("2026-10-03T23:45:10+0200"), "23:45")
  assert.equal(M.wallStamp("2026-10-03T23:45:10+0200"), "2026-10-03T23:45:10")
  assert.equal(M.wallTime("garbage"), "")
})

test("formatElapsed renders H:MM, including past 24 hours", () => {
  assert.equal(M.formatElapsed(0), "0:00")
  assert.equal(M.formatElapsed(59), "0:00")
  assert.equal(M.formatElapsed(300), "0:05")
  assert.equal(M.formatElapsed(4980), "1:23")
  assert.equal(M.formatElapsed(90180), "25:03")
  assert.equal(M.formatElapsed(-20), "0:00")
  assert.equal(M.elapsedSeconds("2026-10-03T10:00:00+0200", Date.UTC(2026, 9, 3, 7, 0, 0)), 0)
})

test("day helpers walk calendar dates across month and DST boundaries", () => {
  assert.equal(M.addDays("2026-10-01", -1), "2026-09-30")
  assert.equal(M.addDays("2026-10-25", 1), "2026-10-26")
  assert.equal(M.addDays("2026-12-31", 1), "2027-01-01")
  assert.equal(M.formatDayHeader("2026-10-03"), "Sat 3 Oct")
  same(M.dayRange("2026-10-03"), { begin: "2026-10-03T00:00:00", end: "2026-10-03T23:59:59" })
  assert.equal(M.localDateString(Date.UTC(2026, 9, 2, 22, 30)), "2026-10-03") // 00:30 in Warsaw
})

test("normalizeUrl drops a web-UI path copied from the browser", () => {
  same(M.normalizeUrl("https://kimai.example.com/en/timesheet/"), { ok: true, url: "https://kimai.example.com", error: "" })
  same(M.normalizeUrl("https://example.com/kimai/de_AT/homepage"), { ok: true, url: "https://example.com/kimai", error: "" })
  same(M.normalizeUrl("kimai.example.com/pl"), { ok: true, url: "https://kimai.example.com", error: "" })
  same(M.normalizeUrl("https://example.com/kimai"), { ok: true, url: "https://example.com/kimai", error: "" })
})
