import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "views"

// The popup. BarWidget.qml loads one per monitor and injects bar, anchorItem,
// hostWidget and svc. Tabs: Timer · Entries · Settings; EditForm replaces the
// tab content while an entry is being edited.
Panel {
  id: root
  moduleName: Model.ID
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root

  property string tab: "timer"
  property var editing: null
  readonly property bool configured: svc !== null && svc.status !== "unconfigured"
  readonly property bool textEditing: (timerView.visible && timerView.textEditing)
    || (entriesView.visible && entriesView.textEditing)
    || (settingsView.visible && settingsView.textEditing)
    || (editForm.visible && editForm.textEditing)

  onOpenedChanged: {
    if (!opened) { editing = null; return }
    var needsSetup = !configured || svc.status === "unauthorized" || svc.status === "error"
    if (needsSetup) tab = "settings"
    if (configured) svc.refreshAll()
  }

  function edit(entry) { root.editing = entry }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.textEditing
      onCloseRequested: root.editing ? root.editing = null : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

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
    }
  }
}
