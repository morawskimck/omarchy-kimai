import QtQuick
import qs.Commons

// Body text in the popup's style. `muted` for secondary lines, `danger` for errors.
Text {
  property bool muted: false
  property bool danger: false

  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  color: danger ? Color.urgent : (muted ? Qt.darker(Color.foreground, 1.4) : Color.foreground)
  font.family: Style.font.family
  font.pixelSize: Style.font.body
}
