import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "views"

// The popup. BarWidget.qml loads one per monitor and injects bar, anchorItem,
// hostWidget and svc.
Panel {
  id: root
  moduleName: Model.ID
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool configured: svc !== null && svc.status !== "unconfigured"
  readonly property bool textEditing: settingsView.textEditing

  onOpenedChanged: if (opened && configured && svc) svc.refreshAll()

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
      onCloseRequested: root.close()
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

        PanelSeparator { width: parent.width }

        SettingsView {
          id: settingsView
          width: parent.width
          svc: root.svc
        }
      }
    }
  }
}
