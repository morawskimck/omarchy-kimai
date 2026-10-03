import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Edit a running or finished entry. Times are HH:MM on the entry's own date
// and are hidden when the server's tracking mode forbids API time edits.
Column {
  id: root

  property var svc: null
  property var entry: null
  property string message: ""
  property bool busy: false
  readonly property bool running: entry !== null && !entry.end
  readonly property bool allowTimes: svc ? svc.allowTimeEdits : true
  readonly property bool textEditing: fields.textEditing || beginField.activeFocus || endField.activeFocus

  signal closed()

  spacing: Style.space(8)

  onEntryChanged: {
    if (!root.entry) return
    root.message = ""
    beginField.text = Model.wallTime(root.entry.begin)
    endField.text = root.entry.end ? Model.wallTime(root.entry.end) : ""
    fields.reset({
      projectId: root.entry.project ? String(root.entry.project.id) : "",
      activityId: root.entry.activity ? String(root.entry.activity.id) : "",
      description: String(root.entry.description || ""),
      tags: Model.tagsOf(root.entry)
    })
  }

  function save() {
    if (root.busy || !root.svc || !root.entry) return
    var v = Model.validateEdit({
      entry: root.entry,
      projectId: fields.projectId,
      activityId: fields.activityId,
      description: fields.description,
      tags: fields.tags,
      beginTime: beginField.text,
      endTime: endField.text,
      allowTimes: root.allowTimes
    })
    if (!v.ok) { root.message = v.error; return }
    root.busy = true
    root.svc.update(root.entry.id, v.payload, function(r) {
      root.busy = false
      if (r.kind === "ok") root.closed()
      else root.message = r.message
    })
  }

  PanelSectionHeader {
    text: root.running ? "Edit running timer"
      : "Edit entry · " + Model.formatDayHeader(Model.wallDate(root.entry ? root.entry.begin : ""))
  }

  PickerFields {
    id: fields
    width: parent.width
    svc: root.svc
    onSubmitted: root.save()
  }

  Row {
    visible: root.allowTimes
    spacing: Style.space(10)

    Column {
      spacing: Style.space(4)
      PlainText { text: "Start"; muted: true }
      TextField { id: beginField; width: Style.space(90); placeholderText: "09:00"; onAccepted: root.save() }
    }
    Column {
      visible: !root.running
      spacing: Style.space(4)
      PlainText { text: "End"; muted: true }
      TextField { id: endField; width: Style.space(90); placeholderText: "17:00"; onAccepted: root.save() }
    }
  }

  Row {
    spacing: Style.space(8)
    Button { text: root.busy ? "Saving…" : "Save"; bordered: true; enabled: !root.busy; onClicked: root.save() }
    Button { text: "Cancel"; onClicked: root.closed() }
    Button {
      text: "Open in Kimai"
      iconText: ""
      onClicked: if (root.svc && root.entry) Quickshell.execDetached(["xdg-open", Model.editUrl(root.svc.url, root.entry.id)])
    }
  }

  PlainText { width: parent.width; text: root.message; danger: true; visible: text !== "" }
}
