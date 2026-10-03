import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One instance per monitor. Renders the service's state and owns the popup;
// all data and API calls live in Service.qml.
BarWidget {
  id: root
  moduleName: Model.ID

  property var svc: null

  // The service can be created after this widget on startup and is recreated
  // on plugin reload, so keep resolving until it is there.
  function resolveService() {
    var shell = root.bar ? root.bar.shell : null
    root.svc = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(Model.ID) : null
  }

  Timer {
    interval: 500
    repeat: true
    running: root.bar !== null && root.svc === null
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  readonly property string status: svc ? svc.status : "unconfigured"
  readonly property var parts: svc ? Model.barParts(svc.active, svc.now) : Model.barParts([], 0)
  readonly property bool running: parts.elapsed !== ""
  readonly property bool problem: status === "unauthorized" || status === "error"

  // ---- popup plumbing (same contract as the built-in weather widget)
  function injectPanel() {
    var p = panelLoader.item
    if (!p) return
    p.bar = root.bar
    p.anchorItem = button
    p.hostWidget = root
    p.svc = Qt.binding(function() { return root.svc })
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: { injectPanel(); resolveService() }

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: root.injectPanel()
  }

  TextMetrics {
    id: nameMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    text: root.parts.name
    elide: Text.ElideRight
    elideWidth: root.svc ? root.svc.config.labelMaxWidth : 180
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.running && !root.vertical
      ? Model.ICON + "  " + root.parts.elapsed + " · " + nameMetrics.elidedText + root.parts.extra
      : Model.ICON
    dimmed: !root.running && !root.problem || root.status === "stale"
    active: root.problem
    tooltipText: root.svc ? Model.tooltip(root.status, root.svc.active, root.svc.now, root.svc.lastSync, root.svc.errorText)
                          : "Kimai · Starting…"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        if (root.svc) root.svc.toggle()
      } else if (mouseButton === Qt.RightButton) {
        if (root.svc && root.svc.url) Quickshell.execDetached(["xdg-open", root.svc.url])
      } else if (panelLoader.item) {
        panelLoader.item.toggle()
      }
    }
  }
}
