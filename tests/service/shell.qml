import QtQuick
import Quickshell
import "plugin"
import "plugin/Model.js" as Model

// Service integration test. scripts/service-test.sh starts mock-kimai.js,
// puts the fake secret-tool first on PATH, points XDG_CONFIG_HOME at a temp
// dir and runs this headless. Each check prints "SVC PASS name" or
// "SVC FAIL name: detail"; the last line is "SVC DONE <failures>".
ShellRoot {
  id: h

  property int failures: 0
  property int changed: 0
  property var steps: []
  property int stepIndex: -1
  property var waitPredicate: null
  property var waitThen: null
  property double waitDeadline: 0
  property string waitName: ""
  readonly property string base: Quickshell.env("KIMAI_TEST_URL")
  readonly property string keyringDir: Quickshell.env("FAKE_KEYRING")
  readonly property string configPath: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy-kimai/config.json"
  readonly property string today: Model.localDateString(Date.now())

  Service {
    id: svc
    onTimesheetsChanged: h.changed++
  }

  // A fresh instance, to exercise startup with the config already in place.
  property var second: null
  property var third: null
  property bool tokenAtUrlChange: true

  // Records whether the old token was still loaded at the moment the URL changed.
  Connections {
    target: h.second
    function onConfigChanged() { if (h.second.config.url !== h.base) h.tokenAtUrlChange = h.second.hasToken }
  }

  function after(ms, fn) {
    var t = Qt.createQmlObject("import QtQuick; Timer {}", h)
    t.interval = ms
    t.triggered.connect(function() { t.destroy(); fn() })
    t.start()
  }
  Component { id: serviceComponent; Service {} }

  function check(name, ok, detail) {
    if (ok) {
      console.log("SVC PASS " + name)
    } else {
      h.failures++
      console.log("SVC FAIL " + name + (detail !== undefined ? ": " + detail : ""))
    }
  }

  function next() {
    h.stepIndex++
    if (h.stepIndex >= h.steps.length) {
      console.log("SVC DONE " + h.failures)
      Qt.quit()
      return
    }
    try {
      h.steps[h.stepIndex]()
    } catch (e) {
      h.check("step " + h.stepIndex + " ran without exceptions", false, e + "")
      h.next()
    }
  }

  // Poll `predicate` every 50 ms; check it and continue with `then`.
  function waitFor(name, predicate, timeoutMs, then) {
    h.waitName = name
    h.waitPredicate = predicate
    h.waitThen = then || h.next
    h.waitDeadline = Date.now() + (timeoutMs || 5000)
    waiter.start()
  }

  Timer {
    id: waiter
    interval: 50
    repeat: true
    onTriggered: {
      var ok = false
      try { ok = h.waitPredicate() } catch (e) { ok = false }
      if (!ok && Date.now() < h.waitDeadline) return
      stop()
      h.check(h.waitName, ok, ok ? undefined : "status=" + svc.status + " error=" + svc.errorText + " active=" + svc.active.length)
      var then = h.waitThen
      Qt.callLater(then)
    }
  }

  function control(path, body, cb) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (cb) cb(xhr.status === 200 && xhr.responseText ? JSON.parse(xhr.responseText) : null)
    }
    xhr.open(body === null ? "GET" : "POST", h.base + path)
    xhr.send(body === null ? null : JSON.stringify(body))
  }

  function shell(argv, cb) {
    svc.runCommand(argv, null, function(code, out, err) { cb(code, out, err) })
  }

  Component.onCompleted: {
    h.steps = [
      function() { h.waitFor("starts unconfigured without a config file", function() { return svc.status === "unconfigured" }, 3000) },

      function() {
        svc.connect(h.base, "wrong-token", function(r) {
          h.check("connect with a wrong token is rejected", r.kind === "unauthorized" && r.message === "Kimai rejected this token", JSON.stringify(r))
          h.check("a failed connect leaves the plugin unconfigured", svc.status === "unconfigured" && !svc.hasToken, svc.status)
          h.next()
        })
      },

      function() {
        svc.connect("http://example.com", "test-token", function(r) {
          h.check("plain http to a remote host is refused", r.kind === "invalid" && r.message.indexOf("https://") !== -1, JSON.stringify(r))
          h.next()
        })
      },

      function() {
        svc.connect(h.base + "/nothing-here", "test-token", function(r) {
          h.check("a URL with no Kimai API explains what to enter", r.kind === "notfound" && r.message.indexOf("No Kimai API at " + h.base + "/nothing-here/api") === 0, JSON.stringify(r))
          h.next()
        })
      },

      function() {
        svc.connect(h.base + "/api/", "test-token", function(r) {
          h.check("connect succeeds and reports user and version", r.kind === "ok" && r.message === "Connected as admin · Kimai 2.67.0", JSON.stringify(r))
          h.check("pasted /api suffix is normalised away", svc.url === h.base, svc.url)
          h.waitFor("status becomes ok after connecting", function() { return svc.status === "ok" && svc.recent.length > 0 })
        })
      },

      function() {
        h.shell(["cat", h.configPath], function(code, out) {
          var cfg = Model.parseConfig(out)
          h.check("config file holds the URL", cfg.url === h.base, out)
          h.check("config file does not hold the token", out.indexOf("test-token") === -1, out)
          h.shell(["sh", "-c", "cat \"$FAKE_KEYRING\"/*"], function(code2, out2) {
            h.check("token went to the keyring", out2 === "test-token", JSON.stringify(out2))
            h.next()
          })
        })
      },

      function() {
        svc.start({ projectId: "2", activityId: "3", description: "Write tests", tags: ["alpha", "new"] }, function(r) {
          h.check("start succeeds", r.kind === "ok", JSON.stringify(r))
          h.waitFor("started timer shows up as active", function() { return svc.active.length === 1 && svc.active[0].description === "Write tests" })
        })
      },

      function() {
        h.check("a new tag typed at start is kept", svc.active.length === 1 && svc.active[0].tags.join(",") === "alpha,new",
                svc.active.length ? JSON.stringify(svc.active[0].tags) : "no active")
        h.control("/__log", null, function(log) {
          var tagPost = log.findIndex(function(r) { return r.method === "POST" && r.path === "/api/tags" })
          var sheetPost = log.findIndex(function(r) { return r.method === "POST" && r.path === "/api/timesheets" })
          h.check("missing tags are created before the timesheet", tagPost !== -1 && tagPost < sheetPost
                  && JSON.parse(log[tagPost].body).name === "new", JSON.stringify([tagPost, sheetPost]))
          h.next()
        })
      },

      function() {
        h.check("timesheetsChanged fired after start", h.changed >= 1, h.changed)
        h.check("bar label names the activity", Model.barParts(svc.active, Date.now()).name === "Code review")
        h.control("/__log", null, function(log) {
          var post = log.filter(function(r) { return r.method === "POST" && r.path === "/api/timesheets" })[0]
          var body = post ? JSON.parse(post.body) : {}
          h.check("start posts project, activity, description and tags", body.project === 2 && body.activity === 3
                  && body.description === "Write tests" && body.tags === "alpha,new", post ? post.body : "no POST")
          h.next()
        })
      },

      function() {
        var r = svc.toggle()
        h.check("toggle while running stops", r === "stopping", r)
        h.waitFor("toggle stopped the timer", function() { return svc.active.length === 0 })
      },

      function() {
        h.waitFor("recent list has the stopped entry first", function() { return svc.recent.length > 0 && svc.recent[0].description === "Write tests" })
      },

      function() {
        var r = svc.toggle()
        h.check("toggle while idle restarts the last entry", r === "restarting", r)
        h.waitFor("restart copies description and tags", function() {
          return svc.active.length === 1 && svc.active[0].description === "Write tests" && svc.active[0].tags.join(",") === "alpha,new"
        })
      },

      function() {
        svc.update(svc.active[0].id, { project: 2, activity: 3, description: "Edited", tags: "alpha" }, function(r) {
          h.check("update succeeds", r.kind === "ok", JSON.stringify(r))
          h.waitFor("update is visible in active", function() { return svc.active.length === 1 && svc.active[0].description === "Edited" })
        })
      },

      function() {
        h.control("/__tagsLocked", { locked: true }, function() {
          var before = svc.active[0].description
          svc.update(svc.active[0].id, { project: 2, activity: 3, description: "Not saved", tags: "alpha,forbidden" }, function(r) {
            h.check("a tag Kimai refuses to create stops the save with a message", r.kind === "invalid"
                    && r.message.indexOf('Kimai did not create the tag "forbidden"') === 0, JSON.stringify(r))
            h.check("nothing is saved when a tag can't be created", svc.active[0].description === before, svc.active[0].description)
            h.control("/__tagsLocked", { locked: false }, function() { h.next() })
          })
        })
      },

      function() {
        h.control("/__patchLocked", { locked: true }, function() {
          svc.update(svc.active[0].id, { project: 2, activity: 3, description: "Locked", tags: "" }, function(r) {
            h.check("a 403 on an edit shows Kimai's reason, not a token problem", r.kind === "forbidden" && r.message === "This timesheet is locked.", JSON.stringify(r))
            h.check("a 403 on an edit does not log the user out", svc.status === "ok", svc.status)
            h.control("/__patchLocked", { locked: false }, function() { h.next() })
          })
        })
      },

      function() {
        svc.update(5, { end: h.today + "T00:00:00", begin: h.today + "T01:00:00" }, function(r) {
          h.check("invalid edit returns Kimai's message", r.kind === "invalid" && r.message === "End date must not be earlier then start date.", JSON.stringify(r))
          h.next()
        })
      },

      function() {
        svc.loadDay(h.today, function(r) {
          h.check("loadDay returns the day's entries", r.kind === "ok" && r.data.length >= 3, JSON.stringify(r).slice(0, 200))
          h.control("/__log", null, function(log) {
            var day = log.filter(function(x) { return x.path === "/api/timesheets" && x.method === "GET" }).pop()
            h.check("loadDay asks for the whole local day", day && day.query.indexOf("begin=" + h.today + "T00%3A00%3A00") !== -1
                    && day.query.indexOf("end=" + h.today + "T23%3A59%3A59") !== -1, day ? day.query : "none")
            h.next()
          })
        })
      },

      function() {
        svc.activities("2", function(r) {
          var ids = r.data ? r.data.map(function(a) { return a.id }).join(",") : ""
          h.check("activities merges project and global activities", r.kind === "ok" && ids === "3,9", ids)
          svc.tags(function(t) {
            h.check("tags returns names, including ones the plugin created", t.kind === "ok" && t.data.join(",") === "alpha,review,new", JSON.stringify(t))
            h.next()
          })
        })
      },

      function() {
        var synced = svc.lastSync
        svc.api("GET", "/version", null, null, function() { throw new Error("view went away") })
        svc.refresh()
        h.waitFor("a callback that throws does not stall the request queue", function() { return svc.lastSync > synced })
      },

      function() {
        svc.stopAll(function() {
          h.waitFor("idle before the external-timer check", function() { return svc.active.length === 0 })
        })
      },

      function() {
        h.control("/__external", { description: "From web" }, function() {
          var r = svc.toggle()
          h.check("toggle while idle restarts", r === "restarting", r)
          h.waitFor("toggle restarts what was tracked last elsewhere, not a stale recent entry", function() {
            return svc.active.length === 1 && svc.active[0].description === "From web"
          })
        })
      },

      function() {
        var stopsBefore = 0
        h.control("/__log", null, function(log) {
          stopsBefore = log.filter(function(r) { return /\/stop$/.test(r.path) }).length
          var first = svc.toggle()
          var second = svc.toggle() // a double middle-click
          h.check("a second toggle while the first runs is refused", first === "stopping" && second === "busy", first + " / " + second)
          h.waitFor("the first toggle stops the timer", function() { return svc.active.length === 0 && !svc.busy }, 10000, function() {
            h.control("/__log", null, function(log2) {
              var stops = log2.filter(function(r) { return /\/stop$/.test(r.path) }).length - stopsBefore
              h.check("a double toggle sends one stop", stops === 1, stops)
              svc.toggle()
              h.waitFor("timer running again for the next checks", function() { return svc.active.length === 1 && !svc.busy })
            })
          })
        })
      },

      function() { h.control("/__mode", { mode: "html" }, function() { svc.refresh(); h.waitFor("proxy error page makes the state stale", function() { return svc.status === "stale" }) }) },
      function() {
        h.check("stale keeps the last known timer", svc.active.length === 1)
        h.check("stale explains the HTTP error", svc.errorText === "Kimai answered HTTP 502", svc.errorText)
        h.control("/__mode", { mode: "ok" }, function() { svc.refresh(); h.waitFor("recovers when the server is back", function() { return svc.status === "ok" && svc.errorText === "" }) })
      },
      function() { h.control("/__mode", { mode: "down" }, function() { svc.refresh(); h.waitFor("dropped connection makes the state stale", function() { return svc.status === "stale" && svc.errorText !== "" }) }) },
      function() { h.control("/__mode", { mode: "ok" }, function() { svc.refresh(); h.waitFor("recovers after a dropped connection", function() { return svc.status === "ok" }) }) },

      function() { h.control("/__token", { token: "rotated" }, function() { svc.refresh(); h.waitFor("revoked token makes the state unauthorized", function() { return svc.status === "unauthorized" }) }) },
      function() {
        h.check("unauthorized explains itself", svc.errorText === "Kimai rejected the API token", svc.errorText)
        h.control("/__log", null, function(log) {
          var api = log.filter(function(r) { return r.path.indexOf("/api/") === 0 })
          h.check("every API call sent a Bearer header", api.every(function(r) { return r.auth.indexOf("Bearer ") === 0 }), api.length)
          h.check("no API call carried the token in the URL", api.every(function(r) { return r.query.indexOf("token") === -1 }))
          var polls = api.filter(function(r) { return r.path === "/api/timesheets/active" }).length
          h.check("active timers are fetched through one queue (no duplicates per refresh)", polls < 20, polls)
          h.next()
        })
      },

      function() {
        h.control("/__token", { token: "test-token" }, function() {
          svc.refreshAll() // requests in flight while the user disconnects
          svc.disconnect(function() {
            h.after(1500, function() {
              h.check("requests from before a disconnect don't revive the session",
                      svc.status === "unconfigured" && !svc.hasToken && svc.active.length === 0,
                      "status=" + svc.status + " active=" + svc.active.length)
              h.shell(["sh", "-c", "ls \"$FAKE_KEYRING\" | wc -l"], function(code, out) {
                h.check("disconnect removes the keyring entry", out.trim() === "0", out)
                h.next()
              })
            })
          })
        })
      },

      function() {
        svc.savePreferences({ pollSeconds: 20 })
        h.waitFor("preferences are saved", function() { return svc.config.pollSeconds === 20 })
      },

      function() {
        var text = JSON.stringify({ url: h.base, pollSeconds: 45 })
        h.shell(["sh", "-c", "sleep 0.3; printf '%s' '" + text + "' > \"$1\"", "sh", h.configPath], function() {
          h.waitFor("external edits to config.json are picked up", function() { return svc.config.pollSeconds === 45 }, 3000)
        })
      },

      function() {
        h.shell(["touch", h.keyringDir + "/FAIL"], function() {
          h.second = serviceComponent.createObject(h)
          h.waitFor("a locked keyring at startup shows an error", function() {
            return h.second.status === "error" && h.second.errorText.indexOf("Keyring unavailable: ") === 0
          })
        })
      },

      function() {
        h.shell(["rm", h.keyringDir + "/FAIL"], function() {
          svc.runCommand(Model.secretToolArgs("store", h.base), "test-token", function() {
            h.second.refreshAll() // what opening the popup or `omarchy-shell kimai refresh` does
            h.waitFor("refresh retries the keyring once it is unlocked", function() { return h.second.status === "ok" && h.second.hasToken })
          })
        })
      },

      function() {
        h.control("/__mode", { mode: "down" }, function() {
          h.third = serviceComponent.createObject(h)
          h.waitFor("starting while the server is unreachable shows Offline, not an error", function() {
            return h.third.status === "stale" && Model.statusLabel(h.third.status, null) === "Offline"
          }, 8000, function() {
            h.third.destroy()
            h.control("/__mode", { mode: "ok" }, function() { h.next() })
          })
        })
      },

      function() {
        var text = JSON.stringify({ url: "http://127.0.0.1:9" })
        h.shell(["sh", "-c", "printf '%s' '" + text + "' > \"$1\"", "sh", h.configPath], function() {
          h.waitFor("a URL changed in config.json is picked up", function() { return h.second.config.url === "http://127.0.0.1:9" }, 3000, function() {
            h.check("the old server's token is dropped before the new URL is used", h.tokenAtUrlChange === false)
            h.next()
          })
        })
      }
    ]
    Qt.callLater(h.next)
  }

  Timer {
    interval: 60000
    running: true
    onTriggered: { console.log("SVC FAIL harness timed out at step " + h.stepIndex); console.log("SVC DONE 1"); Qt.quit() }
  }
}
