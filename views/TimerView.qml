import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Timer tab: running timers with Stop/Edit; when idle, the start form and
// recent entries (one click restarts with the same description and tags).
Column {
  id: root

  property var svc: null
  property string message: ""
  readonly property var active: svc ? svc.active : []
  readonly property bool busy: svc !== null && svc.busy === true
  readonly property bool textEditing: startForm.visible && startForm.textEditing

  signal editRequested(var entry)

  spacing: Style.space(10)

  function report(r) { root.message = r.kind === "ok" ? "" : r.message }

  Repeater {
    model: root.active
    delegate: Column {
      required property var modelData
      width: root.width
      spacing: Style.space(4)

      PlainText { width: parent.width; text: Model.activityName(modelData); font.pixelSize: Style.font.subtitle; font.bold: true }
      PlainText { width: parent.width; text: Model.projectLine(modelData); muted: true; visible: text !== "" }
      PlainText { width: parent.width; text: String(modelData.description || ""); visible: text !== "" }
      Row {
        spacing: Style.space(10)
        PlainText {
          id: elapsedText
          text: Model.formatElapsed(Model.elapsedSeconds(modelData.begin, root.svc ? root.svc.now : Date.now()))
          font.pixelSize: Style.font.title
          font.bold: true
        }
        PlainText {
          anchors.baseline: elapsedText.baseline
          text: "since " + Model.wallTime(modelData.begin)
          muted: true
        }
      }
      Row {
        spacing: Style.space(8)
        Button { text: "Stop"; iconText: ""; bordered: true; enabled: !root.busy; onClicked: root.svc.stop(modelData.id, root.report) }
        Button { text: "Edit"; iconText: ""; bordered: true; enabled: !root.busy; onClicked: root.editRequested(modelData) }
      }
    }
  }

  StartForm {
    id: startForm
    width: parent.width
    svc: root.svc
    visible: root.active.length === 0
  }

  PanelSectionHeader {
    text: "Recent"
    visible: root.active.length === 0 && recentRepeater.count > 0
  }

  Repeater {
    id: recentRepeater
    model: root.active.length === 0 && root.svc ? root.svc.recent : []
    delegate: Button {
      required property var modelData
      width: root.width
      leftAlign: true
      enabled: !root.busy
      iconText: ""
      text: Model.activityName(modelData) + (modelData.project && modelData.project.name ? " · " + modelData.project.name : "")
      tooltipText: String(modelData.description || "")
      onClicked: root.svc.restart(modelData.id, root.report)
    }
  }

  PlainText { width: parent.width; text: root.message; danger: true; visible: text !== "" }
}
