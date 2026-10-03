import QtQuick
import Quickshell
import qs.Commons
import "plugin/views"
import "plugin"
import "plugin/tests/ui"
import "plugin/Model.js" as Model

// UI test harness. scripts/ui-test.sh copies this file into a throwaway
// Quickshell config dir next to symlinks for Omarchy's Commons/Ui and this
// repo (as plugin/), then runs it offscreen. The real views talk to a
// MockService; each check prints "UI PASS name" or "UI FAIL name: detail",
// screenshots land in $KIMAI_UI_OUT, and the last line is "UI DONE <failures>".
ShellRoot {
  id: harness

  property int failures: 0
  property var edited: []
  property bool editClosed: false
  readonly property string outDir: Quickshell.env("KIMAI_UI_OUT")
  readonly property double now: Date.now()

  function check(name, ok, detail) {
    if (ok) {
      console.log("UI PASS " + name)
    } else {
      harness.failures++
      console.log("UI FAIL " + name + (detail !== undefined ? ": " + detail : ""))
    }
  }

  // Kimai-style timestamp in the local timezone, `minutesAgo` before now.
  function stamp(minutesAgo) {
    var ms = harness.now - minutesAgo * 60000
    var d = new Date(ms)
    var off = -d.getTimezoneOffset()
    var sign = off >= 0 ? "+" : "-"
    off = Math.abs(off)
    return Model.localDateString(ms) + "T" + Model.pad2(d.getHours()) + ":" + Model.pad2(d.getMinutes()) + ":00"
      + sign + Model.pad2(Math.floor(off / 60)) + Model.pad2(off % 60)
  }

  function entry(id, beginAgo, endAgo, description, tags) {
    return {
      id: id, begin: stamp(beginAgo), end: endAgo === null ? null : stamp(endAgo),
      duration: endAgo === null ? 0 : (beginAgo - endAgo) * 60, description: description, tags: tags,
      activity: { id: 3, name: "Code review" },
      project: { id: 2, name: "Website", customer: { id: 1, name: "Acme" } }
    }
  }

  function walk(item, out) {
    if (!item) return out
    out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) walk(kids[i], out)
    return out
  }

  function find(item, predicate) {
    var all = walk(item, [])
    for (var i = 0; i < all.length; i++) if (predicate(all[i])) return all[i]
    return null
  }

  function button(item, text) {
    return find(item, function(o) {
      return o.iconText !== undefined && o.clicked !== undefined && typeof o.text === "string"
        && o.text.indexOf(text) === 0 && o.visible
    })
  }

  function field(item, placeholder) {
    return find(item, function(o) { return o.placeholderText === placeholder && o.echoMode !== undefined })
  }

  function textShown(item, text) {
    return find(item, function(o) { return o.text === text && o.font !== undefined && o.visible }) !== null
  }

  function lastCall(svc, key) {
    for (var i = svc.calls.length - 1; i >= 0; i--)
      if (typeof svc.calls[i] === "object" && svc.calls[i][key] !== undefined) return svc.calls[i]
    return null
  }

  function grab(item, name, then) {
    item.grabToImage(function(result) {
      if (harness.outDir) result.saveToFile(harness.outDir + "/" + name + ".png")
      then()
    })
  }

  MockService { id: runningSvc; active: [harness.entry(7, 83, null, "Fix login bug", ["billable"])]; recent: [harness.entry(5, 300, 240, "PR review", ["review"])] }
  MockService { id: idleSvc; recent: [harness.entry(5, 300, 240, "PR review", ["review"])] }
  MockService { id: daySvc; day: [harness.entry(11, 300, 210, "Planning", []), harness.entry(7, 83, null, "Fix login bug", [])] }
  MockService { id: editSvc }
  MockService { id: punchSvc; trackingMode: "punch" }
  MockService { id: slowSvc; slowLookups: true }
  MockService { id: settingsSvc; hasToken: false; status: "unconfigured"; user: null }
  MockService {
    id: barSvc
    active: [harness.entry(7, 83, null, "", []), harness.entry(8, 200, null, "", []), harness.entry(9, 300, null, "", [])]
    Component.onCompleted: {
      var list = barSvc.active
      list[0].activity = { id: 3, name: "Reviewing the extremely long pull request about timezone handling in reports" }
      barSvc.active = Model.sortActive(list)
    }
  }
  MockService { id: idleBarSvc }
  MockService { id: connectedSvc; config: ({ url: "https://kimai.mine.example", pollSeconds: 30, labelMaxWidth: 180 }) }
  property bool connectedSignalled: false
  MockService { id: staleBarSvc; status: "stale"; active: [harness.entry(7, 83, null, "", [])] }
  MockService { id: brokenBarSvc; status: "unauthorized"; errorText: "Kimai rejected the API token" }

  // Just enough of Omarchy's PluginBarApi for BarWidget.qml and WidgetButton.
  component FakeBar: QtObject {
    property var svc: null
    property string fontFamily: Style.font.family
    property color barForeground: Color.foreground
    property color urgent: Color.urgent
    property bool vertical: false
    property int barSize: Style.bar.sizeHorizontal
    property bool foregroundAnimationEnabled: false
    property string position: "top"
    property QtObject shell: QtObject { function serviceFor(id) { return id === Model.ID ? fakeBarShell.svc : null } }
    readonly property var fakeBarShell: this
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function requestPopout(owner) {}
    function releasePopout(owner) {}
  }
  FakeBar { id: barRunning; svc: barSvc }
  FakeBar { id: barIdle; svc: idleBarSvc }
  FakeBar { id: barStale; svc: staleBarSvc }
  FakeBar { id: barBroken; svc: brokenBarSvc }

  FloatingWindow {
    implicitWidth: 2200
    implicitHeight: 1200
    color: Color.popups.background

    Row {
      x: 16
      y: 16
      spacing: 24

      Rectangle {
        id: runningBox
        width: 400; height: runningView.implicitHeight + 24; color: Color.popups.background
        TimerView {
          id: runningView
          x: 12; y: 12; width: 376; svc: runningSvc
          onEditRequested: function(e) { harness.edited = harness.edited.concat([e.id]) }
        }
      }

      Rectangle {
        id: idleBox
        width: 400; height: idleView.implicitHeight + 24; color: Color.popups.background
        TimerView { id: idleView; x: 12; y: 12; width: 376; svc: idleSvc }
      }

      Rectangle {
        id: entriesBox
        width: 400; height: entriesView.implicitHeight + 24; color: Color.popups.background
        EntriesView {
          id: entriesView
          x: 12; y: 12; width: 376; svc: daySvc
          onEditRequested: function(e) { harness.edited = harness.edited.concat([e.id]) }
        }
      }

      Column {
        spacing: 24
        Rectangle {
          id: editBox
          width: 400; height: editForm.implicitHeight + 24; color: Color.popups.background
          EditForm {
            id: editForm
            x: 12; y: 12; width: 376; svc: editSvc
            onClosed: harness.editClosed = true
          }
        }
        Rectangle {
          id: punchBox
          width: 400; height: punchForm.implicitHeight + 24; color: Color.popups.background
          EditForm { id: punchForm; x: 12; y: 12; width: 376; svc: punchSvc }
        }
        EditForm { id: slowForm; width: 376; svc: slowSvc }
        EditForm { id: archivedForm; width: 376; svc: editSvc }
      }

      Column {
        id: barsBox
        spacing: 8
        BarWidget { id: barWidgetRunning; bar: barRunning }
        BarWidget { id: barWidgetIdle; bar: barIdle }
        BarWidget { id: barWidgetStale; bar: barStale }
        BarWidget { id: barWidgetBroken; bar: barBroken }
      }

      SettingsView {
        id: connectedSettings
        width: 376
        svc: connectedSvc
        onConnectSucceeded: harness.connectedSignalled = true
      }

      Rectangle {
        id: settingsBox
        width: 400; height: settingsView.implicitHeight + 24; color: Color.popups.background
        SettingsView { id: settingsView; x: 12; y: 12; width: 376; svc: settingsSvc }
      }
    }
  }

  function barButton(widget) {
    return harness.find(widget, function(o) { return o.pressed !== undefined && o.dimmed !== undefined && o.labelVisible !== undefined })
  }

  function runChecks() {
    // Bar widget
    var running = harness.barButton(barWidgetRunning)
    check("bar shows elapsed time of the newest timer", running && running.text.indexOf(Model.ICON + "  1:23 · ") === 0, running ? running.text : "no button")
    check("a long activity name is elided", running && running.text.indexOf("…") !== -1 && running.text.indexOf("reports") === -1, running ? running.text : "")
    check("extra running timers stay visible after elision", running && /…\s?\+2$/.test(running.text), running ? running.text : "")
    check("bar label width is bounded", barWidgetRunning.implicitWidth < 330, barWidgetRunning.implicitWidth)
    check("running timer is shown at full strength", running && !running.dimmed && !running.active)
    var idle = harness.barButton(barWidgetIdle)
    check("idle bar shows just the icon, dimmed", idle && idle.text === Model.ICON && idle.dimmed, idle ? idle.text + " dimmed=" + idle.dimmed : "")
    var stale = harness.barButton(barWidgetStale)
    check("stale bar keeps the label but dims it", stale && stale.text.indexOf("1:23") !== -1 && stale.dimmed, stale ? stale.text : "")
    var broken = harness.barButton(barWidgetBroken)
    check("a rejected token turns the icon to the urgent colour", broken && broken.active && !broken.dimmed, broken ? "active=" + broken.active : "")
    check("tooltip explains a rejected token", broken && broken.tooltipText === "Kimai · Kimai rejected the API token", broken ? broken.tooltipText : "")
    check("bar widget exposes the host's popup contract", typeof barWidgetIdle.open === "function" && typeof barWidgetIdle.close === "function"
          && typeof barWidgetIdle.toggle === "function" && typeof barWidgetIdle.closeForPopoutSwitch === "function"
          && barWidgetIdle.opened === false && barWidgetIdle.popoutSwitchClosing === false)
    // Opening itself can't be checked here: KeyboardPanel needs a real
    // Wayland layer-shell backend, which the offscreen platform lacks.

    // Timer tab, running
    check("running timer shows elapsed time", harness.textShown(runningView, "1:23"))
    var stop = harness.button(runningView, "Stop")
    check("Stop button exists", stop !== null)
    if (stop) stop.clicked()
    check("Stop stops the running entry", runningSvc.calls.indexOf("stop:7") !== -1, JSON.stringify(runningSvc.calls))
    var edit = harness.button(runningView, "Edit")
    if (edit) edit.clicked()
    check("Edit asks to edit the running entry", harness.edited.indexOf(7) !== -1, JSON.stringify(harness.edited))
    check("start form hidden while a timer runs", harness.button(runningView, "Start") === null)
    runningSvc.busy = true
    check("Stop and Edit are disabled while a change is in flight", stop !== null && !stop.enabled && edit !== null && !edit.enabled)
    runningSvc.busy = false
    check("and enabled again afterwards", stop !== null && stop.enabled)

    // Timer tab, idle
    var picker = harness.find(idleView, function(o) { return o.reset !== undefined && o.projectId !== undefined })
    check("start form pre-fills project from recent", picker && picker.projectId === "2", picker ? picker.projectId : "no picker")
    check("start form pre-fills activity from recent", picker && picker.activityId === "3", picker ? picker.activityId : "no picker")
    check("start form pre-fills description from recent", picker && picker.description === "PR review", picker ? picker.description : "no picker")
    var start = harness.button(idleView, "Start")
    check("Start enabled once project and activity are set", start !== null && start.enabled)
    if (start) start.clicked()
    var started = harness.lastCall(idleSvc, "start")
    check("Start sends the picked fields", started !== null && started.start.projectId === "2" && started.start.activityId === "3"
          && started.start.description === "PR review" && JSON.stringify(started.start.tags) === '["review"]', JSON.stringify(started))
    idleSvc.busy = true
    var recentWhileBusy = harness.button(idleView, "Code review · Website")
    check("Start and Recent rows are disabled while a change is in flight", start !== null && !start.enabled && recentWhileBusy !== null && !recentWhileBusy.enabled)
    idleSvc.busy = false
    var recentRow = harness.button(idleView, "Code review · Website")
    if (recentRow) recentRow.clicked()
    check("clicking a recent entry restarts it", idleSvc.calls.indexOf("restart:5") !== -1, JSON.stringify(idleSvc.calls))

    // Entries tab
    var today = Model.localDateString(Date.now())
    check("Entries loads today on creation", daySvc.calls.indexOf("loadDay:" + today) !== -1, JSON.stringify(daySvc.calls))
    var row = harness.find(entriesView, function(o) { return o.row !== undefined && o.clicked !== undefined && o.row.id === 11 })
    if (row) row.clicked()
    check("clicking an entry asks to edit it", harness.edited.indexOf(11) !== -1, JSON.stringify(harness.edited))
    check("running entry is listed as …–now", harness.find(entriesView, function(o) { return o.row !== undefined && o.row.range.indexOf("–now") !== -1 }) !== null)
    var loadsBefore = daySvc.count("loadDay:")
    daySvc.refreshAll()
    check("Entries reloads when the service refreshes", daySvc.count("loadDay:") > loadsBefore, JSON.stringify(daySvc.calls))
    var next = harness.button(entriesView, "›")
    check("› is disabled on today", next !== null && !next.enabled)
    var prev = harness.button(entriesView, "‹")
    if (prev) prev.clicked()
    check("‹ loads yesterday", daySvc.calls.indexOf("loadDay:" + Model.addDays(today, -1)) !== -1, JSON.stringify(daySvc.calls))
    check("› is enabled on earlier days", next !== null && next.enabled)

    // Edit form
    var finished = {
      id: 11, begin: "2026-01-15T09:00:37+0100", end: "2026-01-15T10:30:00+0100", duration: 5363,
      description: "Planning", tags: ["billable"], activity: { id: 3, name: "Code review" },
      project: { id: 2, name: "Website", customer: { id: 1, name: "Acme" } }
    }
    editForm.entry = finished
    var begin = harness.field(editForm, "09:00")
    check("edit form shows the entry's start time", begin !== null && begin.text === Model.wallTime(finished.begin), begin ? begin.text : "no field")
    begin.text = "25:00"
    editForm.save()
    check("bad start time is rejected before any request", harness.lastCall(editSvc, "update") === null)
    check("bad start time shows a message", harness.textShown(editForm, "Start time must look like 09:30"))
    begin.text = "08:15"
    editSvc.busy = true
    var save = harness.button(editForm, "Save")
    check("Save is disabled while a change is in flight", save !== null && !save.enabled)
    editSvc.busy = false
    editForm.save()
    var updated = harness.lastCall(editSvc, "update")
    check("save sends only the changed start time", updated !== null && updated.update === 11
          && updated.payload.begin === "2026-01-15T08:15:00" && updated.payload.end === undefined,
          JSON.stringify(updated))
    check("save keeps the entry's tags", updated !== null && updated.payload.tags === "billable", JSON.stringify(updated))
    check("successful save closes the form", harness.editClosed)

    slowForm.entry = finished
    var dropdowns = harness.walk(slowForm, []).filter(function(o) { return typeof o.currentLabel === "function" && o.options !== undefined })
    check("edit form shows project and activity names before the lists load",
          dropdowns.length >= 2 && dropdowns[0].currentLabel() === "Website" && dropdowns[1].currentLabel() === "Code review",
          dropdowns.map(function(d) { return d.currentLabel() }).join(" / "))

    var archived = JSON.parse(JSON.stringify(finished))
    archived.project = { id: 77, name: "Old website", customer: { id: 1, name: "Acme" } }
    archived.activity = { id: 78, name: "Legacy support" }
    archivedForm.entry = archived
    var archivedDropdowns = harness.walk(archivedForm, []).filter(function(o) { return typeof o.currentLabel === "function" && o.options !== undefined })
    check("an entry of a hidden or archived project keeps its names after the lists load",
          archivedDropdowns.length >= 2 && archivedDropdowns[0].currentLabel() === "Old website" && archivedDropdowns[1].currentLabel() === "Legacy support",
          archivedDropdowns.map(function(d) { return d.currentLabel() }).join(" / "))

    punchForm.entry = finished
    var punchBegin = harness.field(punchForm, "09:00")
    check("punch mode hides the time fields", punchBegin !== null && !punchBegin.visible)

    // Settings
    var savedUrl = harness.field(connectedSettings, "https://kimai.example.com")
    check("settings shows the saved server URL", savedUrl !== null && savedUrl.text === "https://kimai.mine.example", savedUrl ? savedUrl.text : "no field")
    connectedSvc.config = { url: "https://kimai.other.example", pollSeconds: 30, labelMaxWidth: 180 }
    check("settings follows a changed server URL", savedUrl !== null && savedUrl.text === "https://kimai.other.example", savedUrl ? savedUrl.text : "no field")
    harness.field(connectedSettings, "Paste a new token to replace the saved one").text = "tok"
    var reconnect = harness.button(connectedSettings, "Connect")
    if (reconnect) reconnect.clicked()
    check("a successful connect signals the panel", harness.connectedSignalled)
    harness.field(settingsView, "https://kimai.example.com").text = "kimai.example.com"
    harness.field(settingsView, "Paste your API token").text = "secret-token"
    var connect = harness.button(settingsView, "Connect")
    if (connect) connect.clicked()
    var connected = harness.lastCall(settingsSvc, "connect")
    check("Connect passes URL and token to the service", connected !== null && connected.connect === "kimai.example.com"
          && connected.token === "secret-token", JSON.stringify(connected))
    check("Connect shows the service's message", harness.textShown(settingsView, "Connected as admin · Kimai 2.67.0"))
    var poll = harness.find(settingsView, function(o) { return o.label === "Refresh every (seconds)" && o.modified !== undefined })
    if (poll) poll.modified(60)
    var prefs = harness.lastCall(settingsSvc, "prefs")
    check("changing the refresh interval saves it", prefs !== null && prefs.prefs.pollSeconds === 60, JSON.stringify(prefs))
  }

  Timer {
    interval: 700
    running: true
    onTriggered: {
      try {
        harness.runChecks()
      } catch (e) {
        harness.check("checks ran without exceptions", false, e + "")
      }
      harness.grab(runningBox, "timer-running", function() {
        harness.grab(idleBox, "timer-idle", function() {
          harness.grab(entriesBox, "entries", function() {
            harness.grab(editBox, "edit", function() {
              harness.grab(punchBox, "edit-punch", function() {
                harness.grab(settingsBox, "settings", function() {
                  harness.grab(barsBox, "bar", function() {
                    console.log("UI DONE " + harness.failures)
                    Qt.quit()
                  })
                })
              })
            })
          })
        })
      })
    }
  }

  Timer {
    interval: 20000
    running: true
    onTriggered: { console.log("UI FAIL harness timed out"); console.log("UI DONE 1"); Qt.quit() }
  }
}
