import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "views"

// Everything inside the popup: header, tabs, views and Escape handling.
// Panel.qml hosts it in the KeyboardPanel; tests/ui hosts it directly.
// Tabs: Timer · Entries · Settings; EditForm replaces the tab content while
// an entry is being edited.
Column {
  id: root

  property var svc: null
  property bool opened: false
  property string tab: "timer"
  property var editing: null
  readonly property bool configured: svc !== null && svc.status !== "unconfigured"
  readonly property bool textEditing: (timerView.visible && timerView.textEditing)
    || (entriesView.visible && entriesView.textEditing)
    || (settingsView.visible && settingsView.textEditing)
    || (editForm.visible && editForm.textEditing)

  signal closeRequested()

  spacing: Style.space(10)

  // Escape leaves the edit form first, then closes the popup.
  function handleEscape() {
    if (root.editing) root.editing = null
    else root.closeRequested()
  }

  function edit(entry) { root.editing = entry }

  onOpenedChanged: {
    if (!opened) { editing = null; return }
    var needsSetup = !configured || svc.status === "unauthorized" || svc.status === "error"
    if (needsSetup) tab = "settings"
    if (configured) svc.refreshAll()
  }

  // While a text field has focus, PanelKeyCatcher passes keys through and the
  // field ignores Escape, so it bubbles up to here.
  Keys.onEscapePressed: function(event) {
    root.handleEscape()
    event.accepted = true
  }

  Item {
    width: parent.width
    height: title.implicitHeight
    Text {
      id: title
      text: Model.ICON + "  Kimai"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: title.verticalCenter
      text: root.svc ? Model.statusLabel(root.svc.status, root.svc.user) : ""
      color: root.svc && (root.svc.status === "unauthorized" || root.svc.status === "error") ? Color.urgent : Qt.darker(Color.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  ButtonGroup {
    visible: root.editing === null
    options: [
      { value: "timer", label: "Timer" },
      { value: "entries", label: "Entries" },
      { value: "settings", label: "Settings" }
    ]
    value: root.tab
    onChanged: function(value) { root.tab = value }
  }

  PanelSeparator { width: parent.width }

  TimerView {
    id: timerView
    width: parent.width
    svc: root.svc
    visible: root.editing === null && root.tab === "timer" && root.configured
    onEditRequested: function(entry) { root.edit(entry) }
  }

  EntriesView {
    id: entriesView
    width: parent.width
    svc: root.svc
    visible: root.editing === null && root.tab === "entries" && root.configured
    onEditRequested: function(entry) { root.edit(entry) }
  }

  SettingsView {
    id: settingsView
    width: parent.width
    svc: root.svc
    visible: root.editing === null && (root.tab === "settings" || !root.configured)
    onConnectSucceeded: root.tab = "timer"
  }

  EditForm {
    id: editForm
    width: parent.width
    svc: root.svc
    entry: root.editing
    visible: root.editing !== null
    onClosed: root.editing = null
  }
}
