import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Start a new timer. Pre-filled from the most recent entry.
Column {
  id: root

  property var svc: null
  property string message: ""
  property bool busy: false
  readonly property bool textEditing: fields.textEditing

  spacing: Style.space(8)

  function load() {
    root.message = ""
    fields.reset(Model.prefillFromRecent(root.svc ? root.svc.recent : []))
  }

  function submit() {
    if (root.busy || !root.svc) return
    root.busy = true
    root.svc.start({ projectId: fields.projectId, activityId: fields.activityId, description: fields.description, tags: fields.tags }, function(r) {
      root.busy = false
      root.message = r.kind === "ok" ? "" : r.message
    })
  }

  onVisibleChanged: if (visible) load()
  onSvcChanged: if (visible) load()
  Component.onCompleted: if (visible) load()

  // Recent entries usually arrive after the form is first shown.
  Connections {
    target: root.svc
    function onRecentChanged() { if (root.visible && fields.projectId === "") root.load() }
  }

  PickerFields {
    id: fields
    width: parent.width
    svc: root.svc
    onSubmitted: root.submit()
  }

  Button {
    text: root.busy ? "Starting…" : "Start"
    iconText: ""
    bordered: true
    enabled: !root.busy && !(root.svc && root.svc.busy) && fields.projectId !== "" && fields.activityId !== ""
    onClicked: root.submit()
  }

  PlainText { width: parent.width; text: root.message; danger: true; visible: text !== "" }
}
