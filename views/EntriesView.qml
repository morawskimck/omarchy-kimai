import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Entries tab: one day of timesheets with ‹ › navigation and a day total.
Column {
  id: root

  property var svc: null
  property string date: Model.localDateString(Date.now())
  property var entries: []
  property string message: ""
  property bool loading: false
  readonly property double now: svc ? svc.now : Date.now()
  readonly property string today: Model.localDateString(now)
  readonly property bool textEditing: false

  signal editRequested(var entry)

  spacing: Style.space(8)

  function load() {
    if (!root.svc || !root.visible) return
    root.loading = true
    var forDate = root.date
    root.svc.loadDay(forDate, function(r) {
      if (forDate !== root.date) return
      root.loading = false
      if (r.kind === "ok") {
        root.entries = Array.isArray(r.data) ? r.data : []
        root.message = ""
      } else {
        root.message = r.message
      }
    })
  }

  onVisibleChanged: {
    if (!visible) return
    if (root.date === Model.localDateString(Date.now())) load()
    else root.date = Model.localDateString(Date.now())
  }
  onDateChanged: load()
  onSvcChanged: load()
  Component.onCompleted: load()

  // The popup keeps this view alive while closed, so visibility alone does
  // not tell us it was reopened; the service's refresh does.
  Connections {
    target: root.svc
    function onTimesheetsChanged() { root.load() }
    function onRefreshing() { root.load() }
  }

  Item {
    width: parent.width
    height: Math.max(prevButton.implicitHeight, dayLabel.implicitHeight)

    Button { id: prevButton; text: "‹"; onClicked: root.date = Model.addDays(root.date, -1) }
    PlainText {
      id: dayLabel
      anchors.centerIn: parent
      wrapMode: Text.NoWrap
      font.bold: true
      text: Model.formatDayHeader(root.date) + "  ·  " + Model.formatElapsed(Model.dayTotalSeconds(root.entries, root.now))
    }
    Button {
      anchors.right: parent.right
      text: "›"
      enabled: root.date < root.today
      onClicked: root.date = Model.addDays(root.date, 1)
    }
  }

  PlainText {
    text: root.loading ? "Loading…" : "No entries"
    muted: true
    visible: root.loading || root.entries.length === 0
  }

  Flickable {
    width: parent.width
    height: Math.min(list.implicitHeight, Style.space(320))
    contentHeight: list.implicitHeight
    clip: true
    visible: root.entries.length > 0

    Column {
      id: list
      width: parent.width

      Repeater {
        model: root.entries
        delegate: Button {
          required property var modelData
          readonly property var row: Model.entryRow(modelData, root.now)
          width: list.width
          leftAlign: true
          text: Model.entryLabel(modelData, root.now)
          tooltipText: row.description
          onClicked: root.editRequested(modelData)
        }
      }
    }
  }

  PlainText { width: parent.width; text: root.message; danger: true; visible: text !== "" }
}
