import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Server URL + API token (stored in the keyring by the service), connection
// status and preferences.
Column {
  id: root

  property var svc: null
  property string message: ""
  property bool messageIsError: false
  property bool busy: false
  readonly property bool connected: svc !== null && svc.hasToken
  readonly property bool textEditing: urlField.activeFocus || tokenField.activeFocus
    || pollField.field.activeFocus || widthField.field.activeFocus

  spacing: Style.space(8)

  onVisibleChanged: {
    if (!visible) return
    urlField.text = root.svc ? root.svc.url : ""
    tokenField.text = ""
    root.message = ""
  }

  function connect() {
    if (root.busy || !root.svc) return
    root.busy = true
    root.message = ""
    root.svc.connect(urlField.text, tokenField.text, function(r) {
      root.busy = false
      root.messageIsError = r.kind !== "ok"
      root.message = r.message
      if (r.kind === "ok") tokenField.text = ""
    })
  }

  PlainText {
    width: parent.width
    text: !root.connected ? "Connect to your Kimai server."
      : "Connected as " + Model.userLabel(root.svc.user) + (root.svc.serverVersion ? " · Kimai " + root.svc.serverVersion : "")
  }

  PlainText {
    width: parent.width
    danger: true
    visible: root.svc !== null && (root.svc.status === "unauthorized" || root.svc.status === "error")
    text: root.svc ? root.svc.errorText : ""
  }

  PlainText { text: "Server URL"; muted: true }
  TextField { id: urlField; width: parent.width; placeholderText: "https://kimai.example.com" }

  PlainText { text: "API token"; muted: true }
  TextField {
    id: tokenField
    width: parent.width
    password: true
    placeholderText: root.connected ? "Paste a new token to replace the saved one" : "Paste your API token"
    onAccepted: root.connect()
  }

  PlainText {
    width: parent.width
    muted: true
    font.pixelSize: Style.font.caption
    text: "Create a token in Kimai: click your avatar, open API Access and create a token. It is stored in your keyring, never in a file."
  }

  Row {
    spacing: Style.space(8)
    Button { text: root.busy ? "Connecting…" : "Connect"; bordered: true; enabled: !root.busy; onClicked: root.connect() }
    Button {
      text: "Disconnect"
      visible: root.connected
      onClicked: root.svc.disconnect(function() { root.messageIsError = false; root.message = "Disconnected. The token was removed from your keyring." })
    }
  }

  PlainText { width: parent.width; text: root.message; danger: root.messageIsError; visible: text !== "" }

  PanelSeparator { width: parent.width }
  PanelSectionHeader { text: "Preferences" }

  NumberField {
    id: pollField
    label: "Refresh every (seconds)"
    from: 10
    to: 600
    stepSize: 5
    value: root.svc ? root.svc.config.pollSeconds : 30
    onModified: function(value) { if (root.svc) root.svc.savePreferences({ pollSeconds: value }) }
  }

  NumberField {
    id: widthField
    label: "Bar label width (px)"
    from: 60
    to: 400
    stepSize: 10
    value: root.svc ? root.svc.config.labelMaxWidth : 180
    onModified: function(value) { if (root.svc) root.svc.savePreferences({ labelMaxWidth: value }) }
  }

  PlainText {
    width: parent.width
    danger: true
    visible: root.svc !== null && root.svc.timezoneMismatch
    text: "Your Kimai profile timezone differs from this computer's. Times are shown as Kimai stores them; align the timezone in your Kimai profile to avoid confusion."
  }
}
