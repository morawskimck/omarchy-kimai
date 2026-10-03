const { test } = require("node:test")
const { loadModel, same, assert } = require("./helpers")
const M = loadModel()

const NOW = Date.UTC(2026, 9, 3, 8, 23, 0) // 10:23 in Warsaw
function entry(over) {
  return Object.assign({
    id: 7, begin: "2026-10-03T09:00:00+0200", end: null, duration: 0, description: "",
    tags: [], activity: { id: 3, name: "Code review" },
    project: { id: 2, name: "Website", customer: { id: 1, name: "Acme" } }
  }, over)
}

test("sortActive puts the newest timer first", () => {
  const list = M.sortActive([entry({ id: 1, begin: "2026-10-03T08:00:00+0200" }), entry({ id: 2 })])
  same(list.map(e => e.id), [2, 1])
  same(M.sortActive(null), [])
})

test("barParts shows elapsed + activity, and +N for extra timers", () => {
  same(M.barParts([], NOW), { elapsed: "", name: "", extra: "" })
  same(M.barParts([entry()], NOW), { elapsed: "1:23", name: "Code review", extra: "" })
  same(M.barParts([entry(), entry({ id: 8 }), entry({ id: 9 })], NOW), { elapsed: "1:23", name: "Code review", extra: " +2" })
})

test("missing or empty activity names fall back to the project, then 'Timer'", () => {
  assert.equal(M.activityName(entry({ activity: { id: 3, name: "" } })), "Website")
  assert.equal(M.activityName(entry({ activity: null, project: null })), "Timer")
  assert.equal(M.projectLine(entry({ project: { id: 2, name: "Website", customer: null } })), "Website")
  assert.equal(M.projectLine(entry({ project: null })), "")
})

test("tooltip describes each state", () => {
  assert.equal(M.tooltip("unconfigured", [], NOW, 0, ""), "Kimai · Set up Kimai")
  assert.equal(M.tooltip("unauthorized", [], NOW, 0, "Kimai rejected the API token"), "Kimai · Kimai rejected the API token")
  assert.equal(M.tooltip("ok", [], NOW, NOW, ""), "Kimai · No timer running")
  assert.equal(M.tooltip("ok", [entry({ description: "PR #42" })], NOW, NOW, ""),
    "Code review — 1:23\nWebsite · Acme\nPR #42\nStarted 09:00")
  assert.match(M.tooltip("stale", [entry()], NOW, NOW, ""), /\nOffline · last sync 10:23$/)
})

test("entryRow formats running and finished entries, trusting Kimai's rounded duration", () => {
  same(M.entryRow(entry(), NOW), { id: 7, running: true, range: "09:00–now", duration: "1:23", title: "Code review · Website", description: "" })
  const done = entry({ end: "2026-10-03T10:30:00+0200", duration: 5400, description: "Fixes" })
  same(M.entryRow(done, NOW), { id: 7, running: false, range: "09:00–10:30", duration: "1:30", title: "Code review · Website", description: "Fixes" })
  const noDuration = entry({ end: "2026-10-03T09:45:00+0200", duration: null })
  assert.equal(M.entryRow(noDuration, NOW).duration, "0:45")
  assert.equal(M.dayTotalSeconds([entry(), done], NOW), 4980 + 5400)
})

test("toOptions builds sorted dropdown options with the parent as description", () => {
  same(M.toOptions([{ id: 5, name: "Website", parentTitle: "Acme" }, { id: 4, name: "App", parentTitle: "ACME" }, null, { name: "no id" }]),
       [{ value: "4", label: "App", description: "ACME" }, { value: "5", label: "Website", description: "Acme" }])
  same(M.mergeById([{ id: 1 }, { id: 2 }], [{ id: 2 }, { id: 3 }]).map(x => x.id), [1, 2, 3])
})

test("tags: options are unique and sorted; extra comma text is merged in", () => {
  same(M.tagOptions(["b", "a", "b", "", { name: "c" }]), ["a", "b", "c"])
  same(M.mergeTags(["b"], " a, ,c ,b"), ["a", "b", "c"])
  same(M.mergeTags([], ""), [])
})

test("prefillFromRecent copies the last working set", () => {
  same(M.prefillFromRecent([]), { projectId: "", activityId: "", description: "", tags: [] })
  same(M.prefillFromRecent([entry({ description: "PR", tags: ["review"] })]),
       { projectId: "2", activityId: "3", description: "PR", tags: ["review"] })
})

test("startPayload requires project and activity", () => {
  assert.equal(M.startPayload({ projectId: "2" }).ok, false)
  same(M.startPayload({ projectId: "2", activityId: "3", description: "  PR  ", tags: ["a", "b"] }),
       { ok: true, error: "", payload: { project: 2, activity: 3, description: "PR", tags: "a,b" } })
})

test("validateEdit sends only times that changed and keeps Kimai's dates", () => {
  const done = entry({ begin: "2026-10-03T09:00:37+0200", end: "2026-10-03T10:30:12+0200" })
  const base = { entry: done, projectId: "2", activityId: "3", description: "x", tags: [], allowTimes: true }
  same(M.validateEdit(Object.assign({ beginTime: "09:00", endTime: "10:30" }, base)).payload,
       { project: 2, activity: 3, description: "x", tags: "" })
  same(M.validateEdit(Object.assign({ beginTime: "8:15", endTime: "10:30" }, base)).payload,
       { project: 2, activity: 3, description: "x", tags: "", begin: "2026-10-03T08:15:00" })
})

test("validateEdit rejects bad times, end before start, and missing picks", () => {
  const done = entry({ end: "2026-10-03T10:30:00+0200" })
  const base = { entry: done, projectId: "2", activityId: "3", allowTimes: true }
  assert.equal(M.validateEdit(Object.assign({ beginTime: "25:00", endTime: "10:30" }, base)).error, "Start time must look like 09:30")
  assert.equal(M.validateEdit(Object.assign({ beginTime: "09:00", endTime: "nine" }, base)).error, "End time must look like 17:00")
  assert.equal(M.validateEdit(Object.assign({ beginTime: "11:00", endTime: "10:30" }, base)).error, "End must be after start")
  assert.equal(M.validateEdit(Object.assign({ beginTime: "09:00", endTime: "10:30" }, base, { activityId: "" })).ok, false)
})

test("validateEdit handles running entries, entries past midnight and punch mode", () => {
  const running = entry()
  same(M.validateEdit({ entry: running, projectId: "2", activityId: "3", beginTime: "08:30", allowTimes: true }).payload,
       { project: 2, activity: 3, description: "", tags: "", begin: "2026-10-03T08:30:00" })
  const overnight = entry({ begin: "2026-10-03T22:00:00+0200", end: "2026-10-04T01:00:00+0200" })
  assert.equal(M.validateEdit({ entry: overnight, projectId: "2", activityId: "3", beginTime: "22:00", endTime: "01:30", allowTimes: true }).payload.end,
    "2026-10-04T01:30:00")
  same(M.validateEdit({ entry: running, projectId: "2", activityId: "3", beginTime: "garbage", allowTimes: false }).payload,
       { project: 2, activity: 3, description: "", tags: "" })
})

test("small helpers", () => {
  assert.equal(M.isPunchMode("punch"), true)
  assert.equal(M.isPunchMode("default"), false)
  assert.equal(M.editUrl("https://k.example", 7), "https://k.example/en/timesheet/7/edit")
  assert.equal(M.userLabel({ alias: null, username: "admin" }), "admin")
  assert.equal(M.userLabel({ alias: "Maciek", username: "admin" }), "Maciek")
  assert.equal(M.parseHHMM("7:05"), "07:05")
})

test("statusSnapshot is what `omarchy-shell kimai status` prints", () => {
  same(M.statusSnapshot("ok", [entry()], NOW, ""), {
    status: "ok", running: true, label: "1:23 · Code review", error: "",
    timers: [{ id: 7, activity: "Code review", project: "Website · Acme", begin: "2026-10-03T09:00:00+0200", elapsed: "1:23" }]
  })
})
