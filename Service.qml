import QtQuick
import Quickshell
import Quickshell.Io

// Owns the long-lived watcher process and every side effect the panel can
// trigger (open, reveal, trash). The panel above stays presentational.
Item {
  id: root

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME")
  // Resolved from this file's own location so the plugin keeps working
  // wherever it is installed — cloned, symlinked, or dropped in by hand.
  readonly property string helperPath: {
    var url = String(Qt.resolvedUrl("watch.py"))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url)
  }

  readonly property string folderSetting: String(setting("folder", ""))
  readonly property int maxFiles: intSetting("maxFiles", 25, 3, 100)
  readonly property int highlightSeconds: intSetting("highlightSeconds", 6, 0, 60)

  // Populated from every watcher line.
  property string folder: ""
  property var files: []
  property int total: 0
  property int partials: 0
  property string lastError: ""
  property bool ready: false

  // The most recent completed arrival, and whether its highlight is still live.
  property string arrivalPath: ""
  property bool arrivalActive: false

  signal arrived(string path)

  // Paths seen in the previous snapshot. A path missing from here is new; on
  // the very first snapshot everything is "new", which is why `ready` gates
  // the arrival signal — opening a session should not fire 25 animations.
  property var _seen: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function applyLine(line) {
    var text = String(line || "").trim()
    if (text === "") return

    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      lastError = "Could not parse watcher output"
      return
    }
    if (!parsed || typeof parsed !== "object") return

    if (parsed.ok !== true) {
      lastError = String(parsed.error || "Could not read the downloads folder")
      files = []
      total = 0
      partials = 0
      folder = String(parsed.dir || folder)
      ready = true
      return
    }

    var incoming = Array.isArray(parsed.files) ? parsed.files : []
    folder = String(parsed.dir || "")
    total = Number(parsed.total || 0)
    partials = Number(parsed.partials || 0)
    lastError = ""

    // Newest-first, so the first unseen finished file is the arrival.
    var fresh = ""
    if (ready) {
      for (var i = 0; i < incoming.length; i++) {
        var file = incoming[i]
        if (!file || file.partial) continue
        if (!_seen[file.path]) { fresh = String(file.path); break }
      }
    }

    var next = ({})
    for (var j = 0; j < incoming.length; j++) {
      if (incoming[j] && incoming[j].path) next[incoming[j].path] = true
    }
    _seen = next
    files = incoming
    ready = true

    if (fresh !== "") {
      arrivalPath = fresh
      arrivalActive = highlightSeconds > 0
      if (arrivalActive) highlightTimer.restart()
      arrived(fresh)
    }
  }

  function clearArrival() {
    arrivalActive = false
    highlightTimer.stop()
  }

  function openFile(file) {
    if (!file || !file.path) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", String(file.path)])
  }

  function openFolder() {
    if (folder === "") return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", folder])
  }

  // gio trash, never rm: everything the panel deletes stays recoverable from
  // the desktop trash. Queued so rapid presses can't race the process.
  property var _trashQueue: []

  function trashFile(file) {
    if (!file || !file.path) return
    var queue = _trashQueue.slice()
    queue.push(String(file.path))
    _trashQueue = queue
    pumpTrash()
  }

  function pumpTrash() {
    if (trashProcess.running || _trashQueue.length === 0) return
    var queue = _trashQueue.slice()
    var next = queue.shift()
    _trashQueue = queue
    trashProcess.command = ["gio", "trash", "--", next]
    trashProcess.running = true
  }

  Timer {
    id: highlightTimer
    interval: Math.max(1, root.highlightSeconds) * 1000
    repeat: false
    onTriggered: root.arrivalActive = false
  }

  // Restart the watcher whenever the folder or the listing size changes;
  // both are baked into its argv.
  onFolderSettingChanged: restartWatcher()
  onMaxFilesChanged: restartWatcher()

  function restartWatcher() {
    ready = false
    _seen = ({})
    watcher.running = false
    watcher.command = ["python3", helperPath, folderSetting, String(maxFiles)]
    watcher.running = true
  }

  Process {
    id: watcher
    running: false
    command: []
    stdout: SplitParser { onRead: function(line) { root.applyLine(line) } }
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text !== "") root.lastError = text
      }
    }
    // A watcher that dies (folder unmounted, OOM) would silently freeze the
    // panel, so bring it back on a short backoff instead.
    onExited: respawnTimer.restart()
  }

  Timer {
    id: respawnTimer
    interval: 3000
    repeat: false
    onTriggered: if (!watcher.running) root.restartWatcher()
  }

  Process {
    id: trashProcess
    running: false
    command: []
    stderr: StdioCollector { id: trashError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var text = String(trashError.text || "").replace(/\s+/g, " ").trim()
        root.lastError = text !== "" ? text : "Could not move that file to the trash"
      }
      root.pumpTrash()
    }
  }

  Component.onCompleted: restartWatcher()
}
