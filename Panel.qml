import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omakeylight.keylight"
  ipcTarget: "omakeylight"
  manageIpc: false

  // Shipped alongside the QML so brightness works straight after
  // `omarchy plugin add`, before install.sh has run for the timeout.
  readonly property string ctl: String(Qt.resolvedUrl("bin/omakeylight-ctl")).replace("file://", "")

  property var statusInfo: ({})
  property bool loaded: false
  property real pendingLevel: -1
  property real wheelAccumulator: 0

  // Keyboard cursor: "brightness" row, or an index into the timeout grid.
  property bool cursorActive: false
  property string focusSection: "brightness"
  property int timeoutIndex: 0

  readonly property string device: String(statusInfo.device || "")
  readonly property int maxLevel: Number(statusInfo.max || 0)
  readonly property int level: Model.clampLevel(statusInfo.brightness, maxLevel)
  readonly property string timeoutValue: String(statusInfo.timeout || "")
  readonly property bool timeoutWritable: String(statusInfo.timeoutWritable || "0") === "1"
  readonly property var timeouts: Model.parseTimeouts(statusInfo.timeouts)

  // The widget hides itself entirely on machines with no keyboard backlight
  // rather than parking a dead icon in the bar.
  readonly property bool available: loaded && device !== "" && maxLevel > 0

  // While dragging, trust the slider over the last polled value so the
  // readout does not snap backwards between poll and driver update.
  readonly property int displayLevel: pendingLevel >= 0 ? Math.round(pendingLevel) : level

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(raw) {
    var next = Model.parseStatus(raw)
    loaded = true
    // Keep the last good reading if a poll comes back empty.
    if (!next.device) return
    statusInfo = next
    if (!cursorActive) {
      var idx = timeouts.indexOf(timeoutValue)
      if (idx >= 0) timeoutIndex = idx
    }
  }

  function setLevel(value) {
    var target = Model.clampLevel(value, maxLevel)
    if (target === level && pendingLevel < 0) return
    pendingLevel = target
    actionProc.command = [root.ctl, "brightness", String(target)]
    actionProc.running = true
  }

  function nudgeLevel(delta) {
    setLevel(displayLevel + delta)
  }

  function toggleLight() {
    actionProc.command = [root.ctl, "toggle"]
    actionProc.running = true
  }

  function setTimeout(value) {
    if (!value || !timeoutWritable) return
    actionProc.command = [root.ctl, "timeout", String(value)]
    actionProc.running = true
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }

    if (dy !== 0) {
      if (dy > 0 && focusSection === "brightness" && timeouts.length > 0 && timeoutWritable)
        focusSection = "timeout"
      else if (dy < 0 && focusSection === "timeout")
        focusSection = "brightness"
      return
    }

    if (focusSection === "brightness") nudgeLevel(dx)
    else if (timeouts.length > 0)
      timeoutIndex = Math.max(0, Math.min(timeouts.length - 1, timeoutIndex + dx))
  }

  function activateCursor() {
    if (focusSection === "timeout" && timeoutIndex >= 0 && timeoutIndex < timeouts.length)
      setTimeout(timeouts[timeoutIndex])
  }

  IpcHandler {
    target: "omakeylight"

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function up() { root.nudgeLevel(1) }
    function down() { root.nudgeLevel(-1) }
    function toggleLight() { root.toggleLight() }
  }

  Process {
    id: statusProc
    command: [root.ctl, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    onExited: function(code) { if (code !== 0) root.loaded = true }
  }

  Process {
    id: actionProc
    onExited: { root.pendingLevel = -1; root.refresh() }
  }

  // Poll briskly while the panel is open, lazily otherwise — the level also
  // changes behind our back via the keyboard's own backlight key.
  Timer {
    interval: root.opened ? 1000 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      focusSection = "brightness"
      var idx = timeouts.indexOf(timeoutValue)
      timeoutIndex = idx >= 0 ? idx : 0
    }
  }

  visible: available
  implicitWidth: available ? button.implicitWidth : 0
  implicitHeight: available ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.icon(root.displayLevel)
    opacity: root.displayLevel > 0 ? 1.0 : 0.55
    tooltipText: root.available
      ? "Keyboard light — " + Model.levelLabel(root.displayLevel, root.maxLevel)
        + (root.timeoutValue ? " · " + Model.timeoutLabel(root.timeoutValue) : "")
      : ""

    Behavior on opacity { NumberAnimation { duration: 180 } }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleLight()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.nudgeLevel(wheel.steps)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.icon(root.displayLevel)
            color: root.bar.foreground
            opacity: root.displayLevel > 0 ? 1.0 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on opacity { NumberAnimation { duration: 180 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Keyboard Light"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (Model.levelLabel(root.displayLevel, root.maxLevel)
                     + (root.timeoutValue && root.displayLevel > 0
                        ? " · " + Model.timeoutSentence(root.timeoutValue).toLowerCase()
                        : "")).toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- Brightness ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "BRIGHTNESS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          CursorSurface {
            id: brightnessRow
            width: parent.width
            height: brightnessSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "brightness"
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: brightnessSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: Math.max(1, root.maxLevel)
              step: 1
              integer: true
              tickCount: root.maxLevel + 1
              value: root.displayLevel

              onMoved: function(v) { root.setLevel(v) }
              onRightClicked: root.toggleLight()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "brightness"
              }
            }
          }
        }

        // ---------- Timeout ----------
        PanelSeparator {
          visible: root.timeouts.length > 0 || !root.timeoutWritable
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.timeouts.length > 0 && root.timeoutWritable

          PanelSectionHeader {
            text: "TURNS OFF AFTER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Grid {
            id: timeoutGrid
            width: parent.width
            columns: 4
            spacing: Style.space(6)

            readonly property real cellWidth:
              (width - spacing * (columns - 1)) / columns

            Repeater {
              model: root.timeouts

              Button {
                required property var modelData
                required property int index
                width: timeoutGrid.cellWidth
                text: Model.timeoutLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.timeoutValue === String(modelData)
                hasCursor: root.cursorActive && root.focusSection === "timeout" && root.timeoutIndex === index
                onClicked: root.setTimeout(String(modelData))
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "timeout"
                    root.timeoutIndex = index
                  }
                }
              }
            }
          }
        }

        // Shown when the driver exposes no timeout, or the udev rule is missing.
        Text {
          width: parent.width
          visible: !root.timeoutWritable
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.timeouts.length === 0 && String(root.statusInfo.timeouts || "") === ""
            ? "This keyboard backlight has no adjustable timeout."
            : "Timeout is read-only. Run install.sh from the omakeylight repo to add the udev rule."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
