import QtQuick
import "../../Model.js" as Model

// Stand-in for Service.qml in the UI tests: the same properties, signals and
// functions the views use, canned data, synchronous callbacks, and a log of
// every call in `calls`.
Item {
  id: root

  property string status: "ok"
  property string errorText: ""
  property double lastSync: Date.now()
  property var config: ({ url: "https://kimai.example.com", pollSeconds: 30, labelMaxWidth: 180 })
  readonly property string url: config.url
  property var user: ({ username: "admin", alias: null })
  property string serverVersion: "2.67.0"
  property string trackingMode: "default"
  readonly property bool allowTimeEdits: !Model.isPunchMode(trackingMode)
  property bool hasToken: true
  property bool busy: false
  property var active: []
  property var recent: []
  property double now: Date.now()
  property bool timezoneMismatch: false
  property var day: []
  property var calls: []
  // When true, picker lookups answer after 300 ms, like a busy request queue.
  property bool slowLookups: false

  signal timesheetsChanged()
  signal refreshing()

  function log(entry) { root.calls = root.calls.concat([entry]) }
  function count(prefix) {
    return root.calls.filter(function(c) { return typeof c === "string" && c.indexOf(prefix) === 0 }).length
  }
  function ok(data) { return { kind: "ok", status: 200, data: data, message: "" } }

  function refreshAll() { log("refreshAll"); root.refreshing() }
  function later(fn) {
    if (!root.slowLookups) { fn(); return }
    var t = Qt.createQmlObject("import QtQuick; Timer { interval: 300 }", root)
    t.triggered.connect(function() { t.destroy(); fn() })
    t.start()
  }
  function projects(cb) { later(function() { cb(ok([{ id: 2, name: "Website", parentTitle: "Acme" }, { id: 4, name: "App", parentTitle: "ACME" }])) }) }
  function activities(projectId, cb) { log("activities:" + projectId); later(function() { cb(ok([{ id: 3, name: "Code review", parentTitle: "Website" }, { id: 9, name: "Meetings", parentTitle: "" }])) }) }
  function tags(cb) { cb(ok(["billable", "review"])) }
  function loadDay(date, cb) { log("loadDay:" + date); cb(ok(root.day)) }
  function start(fields, cb) { log({ start: fields }); cb(ok({})) }
  function stop(id, cb) { log("stop:" + id); cb(ok({})) }
  function restart(id, cb) { log("restart:" + id); cb(ok({})) }
  function update(id, payload, cb) { log({ update: id, payload: payload }); cb(ok({})) }
  function connect(url, token, cb) { log({ connect: url, token: token }); cb({ kind: "ok", message: "Connected as admin · Kimai 2.67.0" }) }
  function disconnect(cb) { log("disconnect"); if (cb) cb() }
  function savePreferences(values) { log({ prefs: values }) }
}
