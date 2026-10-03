import QtQuick
import Quickshell.Io

// Runs one argv command, optionally feeding `input` on stdin, and emits done()
// once the process has exited and both output streams are drained. Service.qml
// creates one per call and destroys it afterwards.
Item {
  id: root

  property var command: []
  property string input: ""
  property bool hasInput: false
  property int timeoutMs: 30000

  signal done(int exitCode, string stdout, string stderr)

  property var _exitCode: null
  property bool _outDone: false
  property bool _errDone: false
  property bool _emitted: false

  function start() {
    proc.command = root.command
    proc.running = true
    watchdog.start()
  }

  function _finish(code, out, err) {
    if (_emitted) return
    _emitted = true
    watchdog.stop()
    done(code, out, err)
  }

  function _maybeFinish() {
    if (_exitCode === null || !_outDone || !_errDone) return
    _finish(_exitCode, stdoutCollector.text, stderrCollector.text)
  }

  Process {
    id: proc
    stdinEnabled: root.hasInput
    stdout: StdioCollector {
      id: stdoutCollector
      waitForEnd: true
      onStreamFinished: { root._outDone = true; root._maybeFinish() }
    }
    stderr: StdioCollector {
      id: stderrCollector
      waitForEnd: true
      onStreamFinished: { root._errDone = true; root._maybeFinish() }
    }
    onStarted: {
      if (!root.hasInput) return
      write(root.input)
      stdinEnabled = false // closes stdin so the child sees EOF
    }
    onExited: function(exitCode) {
      root._exitCode = exitCode
      root._maybeFinish()
    }
  }

  // A command that never starts (missing binary) or hangs still reports back.
  Timer {
    id: watchdog
    interval: root.timeoutMs
    onTriggered: {
      proc.running = false
      root._finish(-1, "", root.command[0] + " did not finish")
    }
  }
}
