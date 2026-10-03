import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One instance per plugin (bar widgets exist once per monitor). Owns the
// config file, the API token, polling, the request queue and all Kimai state.
// Widgets and the panel bind to its properties and call its functions.
Item {
  id: root

  // Injected by the shell when declared.
  property string omarchyPath: ""

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy-kimai"
  readonly property string configPath: configDir + "/config.json"

  // ---- public state
  // unconfigured | connecting | ok | stale | unauthorized | error
  property string status: "unconfigured"
  property string errorText: ""
  property double lastSync: 0
  property var config: Model.parseConfig("")
  readonly property string url: config.url
  property var user: null
  property string serverVersion: ""
  property string trackingMode: "default"
  readonly property bool allowTimeEdits: !Model.isPunchMode(trackingMode)
  readonly property bool hasToken: _token !== ""
  // True while a start/stop/restart/update is in flight; views disable their
  // action buttons and toggle() refuses, so a double click can't send twice.
  readonly property bool busy: _inflight > 0
  property var active: []
  property var recent: []
  property double now: Date.now()
  property bool timezoneMismatch: false

  // Emitted after any successful start/stop/restart/update.
  signal timesheetsChanged()
  // Emitted when a full refresh starts (popup opened, reconnect), so views
  // with their own data (the Entries day list) reload too.
  signal refreshing()

  // ---- private
  property string _token: ""
  property int _failures: 0
  property var _queue: []
  property bool _busy: false
  // Bumped on every session reset; answers to older sessions are dropped.
  property int _session: 0
  property int _inflight: 0

  // ---------------------------------------------------------- processes

  Component { id: runComponent; Run {} }

  function runCommand(argv, input, cb) {
    var hasInput = input !== undefined && input !== null && input !== ""
    var r = runComponent.createObject(root, { command: argv, input: hasInput ? input : "", hasInput: hasInput })
    r.done.connect(function(code, out, err) {
      try {
        if (cb) cb(code, out, err)
      } finally {
        r.destroy()
      }
    })
    r.start()
  }

  function notify(message) {
    var bin = root.omarchyPath ? root.omarchyPath + "/bin/omarchy-notification-send" : "omarchy-notification-send"
    Quickshell.execDetached([bin, "-g", Model.ICON, "Kimai", message])
  }

  // ---------------------------------------------------------- config + token

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root._applyConfig(text())
    onLoadFailed: root._applyConfig("")
  }

  function _applyConfig(text) {
    var next = Model.parseConfig(text)
    // Never let the old server's token or queued requests meet a new URL.
    if (next.url !== root.config.url || !next.url) root._resetSession()
    root.config = next
    if (!next.url) {
      root.status = "unconfigured"
      return
    }
    if (!root._token) root._loadToken()
  }

  function _writeConfig(next) {
    root.config = Model.parseConfig(JSON.stringify(next))
    runCommand(["mkdir", "-p", root.configDir], null, function() {
      configFile.setText(Model.serializeConfig(root.config))
    })
  }

  function _resetSession() {
    root._session++
    root._queue = []
    root._inflight = 0 // callbacks of the old session are dropped
    pollTimer.stop()
    root._token = ""
    root.user = null
    root.serverVersion = ""
    root.active = []
    root.recent = []
    root._failures = 0
    root.errorText = ""
  }

  function _loadToken() {
    var forUrl = root.config.url
    runCommand(Model.secretToolArgs("lookup", forUrl), null, function(code, out, err) {
      if (forUrl !== root.config.url) return
      var token = String(out || "").trim()
      if (code === 0 && token) {
        root._token = token
        root.status = "connecting"
        root.refreshAll()
        return
      }
      root._resetSession()
      var problem = String(err || "").trim()
      if (problem) {
        root.status = "error"
        root.errorText = "Keyring unavailable: " + problem
      } else {
        root.status = "unconfigured"
      }
    })
  }

  // ---------------------------------------------------------- request queue

  // cb receives Model.classifyResponse(...) or { kind: "unconfigured", ... }.
  function api(method, path, params, body, cb, dedupeKey) {
    if (!root._token || !root.url) {
      if (cb) cb({ kind: "unconfigured", status: 0, data: null, message: "Kimai is not set up" })
      return
    }
    _enqueue(root.url, root._token, method, path, params, body, cb, dedupeKey)
  }

  function _enqueue(baseUrl, token, method, path, params, body, cb, dedupeKey) {
    if (dedupeKey) {
      for (var i = 0; i < root._queue.length; i++) {
        if (root._queue[i].key === dedupeKey) { _pump(); return }
      }
    }
    root._queue.push({ baseUrl: baseUrl, token: token, method: method, path: path, params: params, body: body, cb: cb,
                       key: dedupeKey || "", session: root._session })
    _pump()
  }

  function _pump() {
    if (root._busy || root._queue.length === 0) return
    var job = root._queue.shift()
    root._busy = true
    runCommand(Model.buildCurlArgs(job.method, Model.apiUrl(job.baseUrl, job.path, job.params), job.body),
               Model.curlConfig(job.token),
               function(code, out, err) {
      root._busy = false
      // Answers to a session that was disconnected or replaced are dropped, and
      // a failing callback (e.g. from a destroyed view) must not stall the queue.
      if (job.session === root._session && job.cb) {
        try {
          job.cb(Model.classifyResponse(code, out, err))
        } catch (e) {
          console.warn("kimai: request callback failed: " + e)
        }
      }
      root._pump()
    })
  }

  // ---------------------------------------------------------- polling

  Timer {
    id: pollTimer
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: root.active.length > 0
    onTriggered: root.now = Date.now()
  }

  function _schedulePoll() {
    if (!root._token || root.status === "unauthorized") return
    pollTimer.interval = Model.nextPollSeconds(root._failures, root.config.pollSeconds) * 1000
    pollTimer.restart()
  }

  function refresh() {
    api("GET", "/timesheets/active", null, null, function(r) {
      if (r.kind === "ok") {
        root.active = Model.sortActive(r.data)
        root.now = Date.now()
        root.lastSync = root.now
        root._failures = 0
        root.status = "ok"
        root.errorText = ""
        if (root.active.length)
          root.timezoneMismatch = Model.timezoneMismatch(root.active[0].begin, Model.localOffsetAt(root.now))
      } else if (r.kind === "unauthorized" || r.kind === "forbidden") {
        pollTimer.stop()
        root.status = "unauthorized"
        root.errorText = r.message
        return
      } else if (r.kind !== "unconfigured") {
        // Unreachable or failing server: Offline, also before the first sync.
        root._failures++
        root.status = "stale"
        root.errorText = r.message
      }
      root._schedulePoll()
    }, "active")
  }

  // cb (optional) runs once the list is updated; a request with a cb is never
  // merged into one that is already queued.
  function loadRecent(cb) {
    api("GET", "/timesheets/recent", { size: 10 }, null, function(r) {
      if (r.kind === "ok") {
        root.recent = Model.sortRecent(r.data)
        if (!root.active.length && root.recent.length)
          root.timezoneMismatch = Model.timezoneMismatch(root.recent[0].begin, Model.localOffsetAt(Date.now()))
      }
      if (cb) cb(r)
    }, cb ? "" : "recent")
  }

  function refreshAll() {
    // Without a token the keyring may have been locked earlier; try it again.
    if (!root._token) {
      if (root.config.url) root._loadToken()
      return
    }
    root.refreshing()
    refresh()
    loadRecent()
    api("GET", "/config/timesheet", null, null, function(r) {
      if (r.kind === "ok" && r.data) root.trackingMode = String(r.data.trackingMode || "default")
    }, "config")
    if (!root.user) {
      api("GET", "/users/me", null, null, function(r) { if (r.kind === "ok") root.user = r.data }, "me")
      api("GET", "/version", null, null, function(r) {
        if (r.kind === "ok" && r.data) root.serverVersion = String(r.data.version || "")
      }, "version")
    }
  }

  // ---------------------------------------------------------- mutations

  // Marks the service busy until the returned callback runs (once).
  function _begin(cb) {
    root._inflight++
    var session = root._session
    var done = false
    return function(r) {
      if (!done && session === root._session) root._inflight--
      done = true
      if (cb) cb(r)
    }
  }

  function _afterMutation(cb) {
    return function(r) {
      if (r.kind === "ok") {
        root.timesheetsChanged()
        root.refresh()
        root.loadRecent()
      }
      if (cb) cb(r)
    }
  }

  // Kimai's timesheet API silently drops tag names it doesn't know, so create
  // missing tags first, then check they all exist. cb(null) on success, else
  // an error result for the form.
  function ensureTags(names, cb) {
    if (!Model.tagOptions(names).length) { cb(null); return }
    api("GET", "/tags", null, null, function(r) {
      if (r.kind !== "ok") { cb(r); return }
      var missing = Model.missingTags(names, r.data)
      if (!missing.length) { cb(null); return }
      var createNext = function() {
        if (missing.length) {
          // A failure here (taken name, no permission) shows up in the re-check.
          api("POST", "/tags", null, { name: missing.shift(), visible: true }, createNext)
          return
        }
        api("GET", "/tags", null, null, function(again) {
          var still = again.kind === "ok" ? Model.missingTags(names, again.data) : Model.missingTags(names, [])
          if (!still.length) { cb(null); return }
          cb({ kind: "invalid", status: 0, data: null,
               message: "Kimai did not create the tag \"" + still.join("\", \"") + "\". Your account may not be allowed to create tags." })
        })
      }
      createNext()
    })
  }

  // fields: { projectId, activityId, description, tags }
  function start(fields, cb) {
    var p = Model.startPayload(fields)
    if (!p.ok) {
      if (cb) cb({ kind: "invalid", status: 0, data: null, message: p.error })
      return
    }
    var finish = _begin(cb)
    ensureTags(fields.tags, function(err) {
      if (err) { finish(err); return }
      api("POST", "/timesheets", null, p.payload, _afterMutation(finish))
    })
  }

  function stop(id, cb) {
    api("PATCH", "/timesheets/" + id + "/stop", null, null, _afterMutation(_begin(cb)))
  }

  function stopAll(cb) {
    var ids = root.active.map(function(e) { return e.id })
    if (!ids.length) {
      if (cb) cb({ kind: "ok", status: 200, data: null, message: "" })
      return
    }
    var remaining = ids.length
    var failed = null
    ids.forEach(function(id) {
      stop(id, function(r) {
        if (r.kind !== "ok" && !failed) failed = r
        remaining--
        if (remaining === 0 && cb) cb(failed || r)
      })
    })
  }

  function restart(id, cb) {
    api("PATCH", "/timesheets/" + id + "/restart", null, { copy: "all" }, _afterMutation(_begin(cb)))
  }

  // payload: the `payload` of a successful Model.validateEdit()
  function update(id, payload, cb) {
    var finish = _begin(cb)
    ensureTags(String(payload.tags || "").split(","), function(err) {
      if (err) { finish(err); return }
      api("PATCH", "/timesheets/" + id, null, payload, _afterMutation(finish))
    })
  }

  // Restart the most recent entry. Kimai is asked first, because timers
  // started and stopped elsewhere since the last refresh are not in `recent`.
  function restartLast(cb) {
    var finish = _begin(cb) // busy already while the recent list loads
    loadRecent(function() {
      if (root.recent.length) restart(root.recent[0].id, finish)
      else finish({ kind: "invalid", status: 0, data: null, message: "Nothing to restart yet" })
    })
  }

  // Stop everything that runs, or restart the most recent entry when idle.
  // Used by middle click and IPC, which have no UI, so failures notify.
  function toggle() {
    if (!root._token) return "unconfigured"
    if (root.busy) return "busy"
    var report = function(r) { if (r.kind !== "ok") root.notify(r.message) }
    if (root.active.length) {
      stopAll(report)
      return "stopping"
    }
    restartLast(report)
    return "restarting"
  }

  // ---------------------------------------------------------- lookups

  function loadDay(dateStr, cb) {
    var range = Model.dayRange(dateStr)
    api("GET", "/timesheets", { begin: range.begin, end: range.end, full: "true", size: 200, orderBy: "begin", order: "DESC" }, null, cb)
  }

  function projects(cb) {
    api("GET", "/projects", { visible: 1 }, null, cb)
  }

  // Project activities plus global ones, merged by id.
  function activities(projectId, cb) {
    api("GET", "/activities", { project: projectId, visible: 1 }, null, function(own) {
      if (own.kind !== "ok") { cb(own); return }
      api("GET", "/activities", { globals: "true", visible: 1 }, null, function(globals) {
        var merged = Model.mergeById(own.data, globals.kind === "ok" ? globals.data : [])
        cb({ kind: "ok", status: 200, data: merged, message: "" })
      })
    })
  }

  function tags(cb) {
    api("GET", "/tags", null, null, cb)
  }

  // ---------------------------------------------------------- connect

  function connect(urlInput, token, cb) {
    var n = Model.normalizeUrl(urlInput)
    if (!n.ok) { cb({ kind: "invalid", message: n.error }); return }
    var t = String(token || "").trim()
    if (!t) { cb({ kind: "invalid", message: "Paste an API token" }); return }
    var previousUrl = root.config.url
    var previousStatus = root.status
    root.status = "connecting"
    _enqueue(n.url, t, "GET", "/users/me", null, null, function(me) {
      if (me.kind !== "ok") {
        root.status = previousStatus
        if (me.kind === "unauthorized") cb({ kind: me.kind, message: "Kimai rejected this token" })
        else if (me.kind === "notfound")
          cb({ kind: me.kind, message: "No Kimai API at " + n.url + "/api. Enter the address of your Kimai start page, without /en/… or other paths." })
        else cb(me)
        return
      }
      _enqueue(n.url, t, "GET", "/version", null, null, function(ver) {
        runCommand(Model.secretToolArgs("store", n.url), t, function(code, out, err) {
          if (code !== 0) {
            root.status = previousStatus
            cb({ kind: "error", message: "Keyring unavailable: " + (String(err || "").trim() || ("secret-tool exit " + code)) })
            return
          }
          if (previousUrl && previousUrl !== n.url) runCommand(Model.secretToolArgs("clear", previousUrl), null, null)
          root._resetSession()
          root._token = t
          root.user = me.data
          root.serverVersion = ver.kind === "ok" && ver.data ? String(ver.data.version || "") : ""
          root._writeConfig({ url: n.url, pollSeconds: root.config.pollSeconds, labelMaxWidth: root.config.labelMaxWidth })
          root.refreshAll()
          cb({ kind: "ok", message: "Connected as " + Model.userLabel(me.data) + (root.serverVersion ? " · Kimai " + root.serverVersion : "") })
        })
      })
    })
  }

  function disconnect(cb) {
    var forUrl = root.config.url
    root._resetSession()
    root.status = "unconfigured"
    if (!forUrl) { if (cb) cb(); return }
    runCommand(Model.secretToolArgs("clear", forUrl), null, function() { if (cb) cb() })
  }

  // values: { pollSeconds?, labelMaxWidth? }
  function savePreferences(values) {
    var next = { url: root.config.url, pollSeconds: root.config.pollSeconds, labelMaxWidth: root.config.labelMaxWidth }
    for (var key in values) next[key] = values[key]
    _writeConfig(next)
    _schedulePoll()
  }

  // ---------------------------------------------------------- IPC

  IpcHandler {
    target: "kimai"

    function toggle(): string { return root.toggle() }
    function stop(): string {
      if (!root.hasToken) return "unconfigured"
      if (root.busy) return "busy"
      root.stopAll(function(r) { if (r.kind !== "ok") root.notify(r.message) })
      return "stopping"
    }
    function restartLast(): string {
      if (!root.hasToken) return "unconfigured"
      if (root.busy) return "busy"
      root.restartLast(function(r) { if (r.kind !== "ok") root.notify(r.message) })
      return "restarting"
    }
    function refresh(): string { root.refreshAll(); return "refreshing" }
    function status(): string { return JSON.stringify(Model.statusSnapshot(root.status, root.active, Date.now(), root.errorText)) }
  }

  Component.onCompleted: {
    runCommand(["mkdir", "-p", root.configDir], null, function() { configFile.reload() })
  }
}
