import QtQuick
import Quickshell
import qs.Commons
import "plugin"
import "plugin/views"
import "plugin/tests/ui"
import "plugin/Model.js" as Model

// Renders preview.png for the README and the plugin marketplace with demo
// data: scripts/preview.sh. Needs Quickshell and Omarchy's shell sources.
ShellRoot {
  id: h
  readonly property double now: Date.now()
  function stamp(minutesAgo) {
    var ms = h.now - minutesAgo * 60000
    var d = new Date(ms)
    var off = -d.getTimezoneOffset(), sign = off >= 0 ? "+" : "-"
    off = Math.abs(off)
    return Model.localDateString(ms) + "T" + Model.pad2(d.getHours()) + ":" + Model.pad2(d.getMinutes()) + ":00" + sign + Model.pad2(Math.floor(off / 60)) + Model.pad2(off % 60)
  }
  function e(id, act, proj, cust, beginAgo, endAgo, desc, tags) {
    return { id: id, begin: stamp(beginAgo), end: endAgo === null ? null : stamp(endAgo), duration: endAgo === null ? 0 : (beginAgo - endAgo) * 60,
             description: desc, tags: tags, activity: { id: id + 100, name: act }, project: { id: id + 200, name: proj, customer: { id: 1, name: cust } } }
  }
  readonly property var running: e(1, "Code review", "Website", "Acme", 83, null, "Release 2.1 checklist", ["billable"])
  readonly property var day: [running, e(2, "Design", "Mobile app", "Acme", 250, 160, "Onboarding screens", []), e(3, "Meetings", "Internal", "Acme", 300, 270, "Standup", []),
                              e(4, "Development", "Website", "Acme", 420, 315, "Search filters", ["billable"])]

  MockService { id: svc; active: [h.running]; recent: h.day.slice(1); day: h.day; user: ({ username: "anna", alias: "Anna" }) }

  component FakeBar: QtObject {
    property string fontFamily: Style.font.family
    property color barForeground: Color.foreground
    property color urgent: Color.urgent
    property bool vertical: false
    property int barSize: Style.bar.sizeHorizontal
    property bool foregroundAnimationEnabled: false
    property string position: "top"
    property QtObject shell: QtObject { function serviceFor(id) { return svc } }
    function showTooltip(t, x) {}
    function hideTooltip(t) {}
    function registerClickTarget(t) {}
    function unregisterClickTarget(t) {}
  }
  FakeBar { id: fakeBar }

  component Card: Rectangle {
    property string title: ""
    default property alias content: inner.data
    width: 420
    height: inner.implicitHeight + head.implicitHeight + 52
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 2
    Text { id: head; x: 20; y: 16; text: Model.ICON + "  Kimai  ·  " + parent.title; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
    Column { id: inner; x: 20; y: head.y + head.implicitHeight + 14; width: parent.width - 40 }
  }

  FloatingWindow {
    implicitWidth: scene.width
    implicitHeight: scene.height
    color: "transparent"
    Rectangle {
      id: scene
      width: content.width + 48; height: content.y + content.height + 32
      color: Qt.darker(Color.popups.background, 1.35)
      Rectangle {
        id: barStrip
        width: parent.width; height: 44
        color: Color.popups.background
        Row {
          anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
          spacing: 18
          Text { text: "‹"; color: Qt.darker(Color.foreground, 1.3); font.family: Style.font.family; font.pixelSize: Style.font.body + 2; anchors.verticalCenter: parent.verticalCenter }
          BarWidget { bar: fakeBar; anchors.verticalCenter: parent.verticalCenter }
          Text { text: "      " + Qt.formatTime(new Date(), "HH:mm"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      Row {
        id: content
        x: 24; y: 76; spacing: 24
        Column {
          spacing: 24
          Card { title: "Timer"; TimerView { width: parent.width; svc: svc } }
          Card { title: "Entries"; EntriesView { width: parent.width; svc: svc } }
        }
        Card { title: "Edit"; EditForm { id: ef; width: parent.width; svc: svc } }
      }
    }
    Timer {
      interval: 900; running: true
      onTriggered: {
        ef.entry = h.day[1]
        Qt.callLater(function() {
          scene.grabToImage(function(r) { console.log("PREVIEW saved=" + r.saveToFile(Quickshell.env("PREVIEW_OUT"))); Qt.quit() })
        })
      }
    }
  }
}
