import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup. BarWidget.qml loads one per monitor and injects bar, anchorItem,
// hostWidget and svc. The content lives in PanelContent.qml.
Panel {
  id: root
  moduleName: Model.ID
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root

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
      blocked: content.textEditing
      onCloseRequested: content.handleEscape()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      PanelContent {
        id: content
        width: parent.width
        svc: root.svc
        opened: root.opened
        onCloseRequested: root.close()
      }
    }
  }
}
