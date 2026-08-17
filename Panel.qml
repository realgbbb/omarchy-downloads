import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Downloads — recent files from the download folder, in the bar.
//
// The panel is built for the two-second interaction: a file lands, the bar
// icon drops its arrow, you hit the keybind and Enter, and the file is open.
// That is why the newest row is already selected when the panel appears rather
// than waiting for a first arrow press.
//
// The id is deliberately `downloadsPanel` and not the usual `root`: several
// qs.Ui components declare their own `id: root`, and every inline Component
// below (bar icon, hero icon, hero trailing button) is instantiated inside one
// of them. A unique id keeps those references unambiguous.
Panel {
  id: downloadsPanel

  moduleName: "realgbb.downloads"
  ipcTarget: "realgbb.downloads"
  manageIpc: false

  property string focusSection: "files"
  property int fileIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: downloads.partials > 0 ? barForeground : Qt.darker(barForeground, 1.25)

  // "header" is only a cursor stop once there is a folder to open.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  function ensureCursor() {
    if (downloads.files.length === 0) {
      focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header") focusSection = "files"
    if (fileIndex >= downloads.files.length) fileIndex = Math.max(0, downloads.files.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && downloads.files.length > 0) {
        focusSection = "files"
        fileIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        setHeaderCursor()
        return
      }
      fileIndex = Math.max(0, Math.min(downloads.files.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
    scrollCursorIntoView()
  }

  function selectedFile() {
    if (downloads.files.length === 0) return null
    return downloads.files[Math.max(0, Math.min(fileIndex, downloads.files.length - 1))]
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") openFolder()
    else openSelected()
  }

  // Opening a file is the end of the errand — get out of the way afterwards,
  // the same way the menu closes on a chosen command.
  function openSelected() {
    var file = selectedFile()
    if (!file) return
    downloads.openFile(file)
    close()
  }

  // Handing the folder to the file manager ends the errand just as much as
  // opening a file does, so it exits the same way — from Space, `o`, Enter on
  // the header, or the hero button. One action, one behaviour.
  function openFolder() {
    downloads.openFolder()
    close()
  }

  // The numbered rows. No cursor move first: the number *is* the selection,
  // and the panel is gone before a highlight could be read anyway.
  function openFileAt(index) {
    if (index < 0 || index >= downloads.files.length) return
    var file = downloads.files[index]
    if (!file) return
    downloads.openFile(file)
    close()
  }

  function trashSelected() {
    if (focusSection !== "files") return
    var file = selectedFile()
    if (!file) return
    downloads.trashFile(file)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length) {
      scrollItemIntoView(fileColumn.children[fileIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The newest file is preselected on open, so the whole interaction can be
  // "keybind, Enter". Every other panel starts with a dormant cursor; this one
  // does not, because there is exactly one obvious thing you came here to do.
  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    cursorActive = true
    fileIndex = 0
    focusSection = downloads.files.length > 0 ? "files" : "header"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFileIndexChanged: scrollCursorIntoView()

  Service {
    id: downloads
    settings: downloadsPanel.settings
  }

  Connections {
    target: downloads
    function onFilesChanged() { downloadsPanel.ensureCursor() }
  }

  IpcHandler {
    target: downloadsPanel.ipcTarget
    function open(): void { downloadsPanel.open() }
    function close(): void { downloadsPanel.close() }
    function show(): void { downloadsPanel.open() }
    function hide(): void { downloadsPanel.close() }
    function toggle(): void { downloadsPanel.toggle() }
    function folder(): string { return downloads.folder }
    function count(): string { return String(downloads.total) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: downloadsPanel.bar
    iconComponent: Component {
      Item {
        DownloadsIcon {
          id: barGlyph
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: downloadsPanel.barIconColor
          pulseColor: downloadsPanel.accent

          // The arrival animation, on the bar itself — the panel does not have
          // to be open (or ever opened) for a finished download to register.
          Connections {
            target: downloads
            function onArrived(path) { barGlyph.pulse() }
          }
        }

        // Quiet in-flight marker. Distinct from the arrival animation: this one
        // simply persists for as long as something is still being written.
        Rectangle {
          visible: downloads.partials > 0
          width: Style.space(4)
          height: width
          radius: width / 2
          color: downloadsPanel.accent
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(1)
          anchors.topMargin: Style.space(1)
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) downloads.openFolder()
      else downloadsPanel.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: downloadsPanel
    bar: downloadsPanel.bar
    open: downloadsPanel.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + footerInset, Style.space(560))

    readonly property real footerInset: footer.visible ? footer.implicitHeight + Style.space(10) : 0

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // The shared catcher folds Enter and Space into one `activateRequested`,
      // and only Enter is preceded by `returnRequested`. That pair is what
      // tells them apart here, without forking the catcher: Enter opens the row
      // under the cursor, Space is this panel's key for the folder itself.
      property bool activateFromReturn: false

      onMoveRequested: function(dx, dy) { downloadsPanel.moveCursor(dx, dy) }
      onReturnRequested: activateFromReturn = true
      onActivateRequested: {
        var fromReturn = activateFromReturn
        activateFromReturn = false
        if (!fromReturn) { downloadsPanel.openFolder(); return }
        if (downloadsPanel.focusSection === "header") downloadsPanel.openFolder()
        else downloadsPanel.openSelected()
      }
      onCloseRequested: downloadsPanel.close()
      onTabRequested: function(direction) { downloadsPanel.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "t" || text === "T") { downloadsPanel.trashSelected(); return }
        if (text === "o" || text === "O") { downloadsPanel.openFolder(); return }
        var row = Model.shortcutIndex(text)
        if (row >= 0) downloadsPanel.openFileAt(row)
      }
      // `t` above is the documented trash key. The shared catcher also maps `x`
      // to delete for every panel, and that stays wired; Delete itself falls
      // through to here unhandled, and people reach for it first with a file
      // list in front of them.
      onDeleteRequested: downloadsPanel.trashSelected()
      Keys.onDeletePressed: downloadsPanel.trashSelected()

      Flickable {
        id: panelFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.visible ? footer.top : parent.bottom
        anchors.bottomMargin: footer.visible ? Style.space(10) : 0
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Read by the hero's trailingControl, which resolves ids through
            // the hero rather than this panel.
            readonly property bool ringVisible: downloadsPanel.headerHasCursor
            readonly property string folderTip: "Open " + Model.displayPath(downloads.folder, downloads.home)
            function focusHero() { downloadsPanel.setHeaderCursor() }
            function openFolder() { downloadsPanel.openFolder() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Downloads"
              meta: downloads.ready ? Model.summaryText(downloads.total, downloads.partials) : "Reading folder"
              foreground: downloadsPanel.foreground
              fontFamily: downloadsPanel.fontFamily

              iconComponent: Component {
                DownloadsIcon {
                  iconSize: Style.font.display
                  color: hero.foreground
                }
              }

              // Opening the folder in the file manager: the hero's trailing
              // edge, matching where the other panels put their one global
              // action. Also reachable with `o`, or Enter from the header.
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰝰"
                  tooltipText: header.folderTip
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  hasCursor: header.ringVisible
                  onHovered: function(on) { if (on) header.focusHero() }
                  onClicked: header.openFolder()
                }
              }
            }
          }

          Text {
            visible: downloads.lastError !== ""
            width: parent.width
            text: downloads.lastError
            color: downloadsPanel.urgent
            font.family: downloadsPanel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: downloadsPanel.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RECENT"
              foreground: downloadsPanel.foreground
              fontFamily: downloadsPanel.fontFamily
            }

            Text {
              visible: downloads.ready && downloads.files.length === 0 && downloads.lastError === ""
              width: parent.width
              text: "Nothing downloaded yet."
              color: downloadsPanel.dim
              font.family: downloadsPanel.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: fileColumn
              visible: downloads.files.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: downloads.files
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }

      // Pinned below the list rather than trailing it, so the shortcuts stay
      // on screen once the list is long enough to scroll.
      Text {
        id: footer
        visible: downloads.files.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "↵ open · 1–9 open file · t trash · space folder"
        color: Qt.darker(downloadsPanel.foreground, 2.0)
        font.family: downloadsPanel.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow

    property var file: null
    property int rowIndex: 0

    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"
    readonly property string shortcutKey: Model.shortcutKey(rowIndex)
    // Fresh arrivals glow for a few seconds, whether or not the panel was open
    // when they landed — so opening the panel after the fact still shows you
    // which row is the new one.
    readonly property bool isNew: !!file && downloads.arrivalActive && downloads.arrivalPath === file.path

    hasCursor: downloadsPanel.cursorActive && downloadsPanel.focusSection === "files" && downloadsPanel.fileIndex === rowIndex
    foreground: downloadsPanel.foreground

    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    Rectangle {
      id: arrivalFlash
      anchors.fill: parent
      radius: Style.cornerRadius
      color: downloadsPanel.accent
      opacity: 0

      SequentialAnimation on opacity {
        running: fileRow.isNew
        loops: 3
        NumberAnimation { to: 0.22; duration: 240; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.0; duration: 420; easing.type: Easing.InQuad }
      }
    }

    // The trash button is a mouse affordance only, so it tracks the pointer
    // rather than the panel cursor. `trashHovered` is what keeps it from
    // blinking out from under the pointer: once the button's own MouseArea
    // takes the hover, the row's no longer has it.
    property bool trashHovered: false
    readonly property bool mouseOver: rowMouse.containsMouse || trashHovered

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: downloadsPanel.setFileCursor(fileRow.rowIndex)
      onClicked: downloadsPanel.openSelected()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: Model.fileGlyph(fileRow.file)
        color: fileRow.file && fileRow.file.partial ? downloadsPanel.accent : downloadsPanel.foreground
        font.family: downloadsPanel.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: fileRow.fileName
          color: downloadsPanel.foreground
          font.family: downloadsPanel.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.file, clock.nowMs)
          color: downloadsPanel.dim
          font.family: downloadsPanel.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Always in the layout so the row never reflows. Revealed by the pointer
      // alone, not by the keyboard cursor: on the keyboard the trash is `t`,
      // and a delete button that lights up as you arrow past a row is an
      // invitation nobody asked for.
      PanelActionButton {
        iconText: "󰩹"
        tooltipText: "Move to trash"
        foreground: downloadsPanel.foreground
        hoverColor: downloadsPanel.urgent
        fontFamily: downloadsPanel.fontFamily
        opacity: fileRow.mouseOver ? 1.0 : 0.0
        Layout.alignment: Qt.AlignVCenter
        onClicked: downloads.trashFile(fileRow.file)
        onHovered: function(on) { fileRow.trashHovered = on }

        Behavior on opacity {
          NumberAnimation { duration: 90 }
        }
      }

      // Row number, on the trailing edge, in a ring that fills solid when the
      // cursor lands on the row — so the key you would press and the row Enter
      // would open read as the same thing. The slot keeps its width past row 9
      // so the filenames all stop at the same place, badge or no badge.
      Item {
        implicitWidth: Style.space(20)
        implicitHeight: Style.space(20)
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
          anchors.centerIn: parent
          visible: fileRow.shortcutKey !== ""
          width: Style.space(20)
          height: width
          radius: width / 2
          antialiasing: true
          color: fileRow.hasCursor ? downloadsPanel.accent : "transparent"
          border.width: Style.spacing.hairline
          border.color: fileRow.hasCursor
            ? downloadsPanel.accent
            : Util.alpha(downloadsPanel.foreground, 0.3)

          Behavior on color {
            ColorAnimation { duration: 90 }
          }
          Behavior on border.color {
            ColorAnimation { duration: 90 }
          }

          Text {
            anchors.centerIn: parent
            text: fileRow.shortcutKey
            color: fileRow.hasCursor ? Color.background : downloadsPanel.dim
            font.family: downloadsPanel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

    }
  }

  // One shared clock for every row's "3m ago", ticking only while the panel is
  // actually on screen.
  QtObject {
    id: clock
    property double nowMs: Date.now()
  }

  Timer {
    interval: 30000
    repeat: true
    running: downloadsPanel.opened
    triggeredOnStart: true
    onTriggered: clock.nowMs = Date.now()
  }
}
