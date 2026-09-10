import QtQuick
import Quickshell
import Quickshell.Io

// Compact bar control for Vinyl Player.
// A small record icon. Left-click toggles the desktop vinyl; right-click
// plays and pauses. The disc spins (and the accent lights) while a track
// is playing.
Item {
  id: root

  property var bar: null
  property var shell: null
  property var manifest: null
  property var settings: null
  property string moduleName: "vinyl.player"

  property bool playerOn: true
  property bool playing: false

  implicitWidth: 28
  implicitHeight: bar ? (bar.barSize || 26) : 26

  readonly property color accent: bar && bar.accent ? bar.accent : "#1DB954"
  readonly property color fg: bar && bar.foreground ? bar.foreground : "#e8e8e8"

  Process {
    id: query
    command: ["omarchy-shell", "-q", "vinyl.player", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text.trim())
          if (typeof data.visible === "boolean") root.playerOn = data.visible
          if (typeof data.playing === "boolean") root.playing = data.playing
        } catch (e) {
          const t = text.trim().toLowerCase()
          if (t === "true" || t === "1") root.playerOn = true
          else if (t === "false" || t === "0") root.playerOn = false
        }
      }
    }
  }

  Process {
    id: toggler
    command: ["omarchy-shell", "-q", "vinyl.player", "toggle"]
    onExited: Qt.callLater(() => { query.running = true })
  }

  Process {
    id: playPause
    command: ["omarchy-shell", "-q", "vinyl.player", "playPause"]
    onExited: Qt.callLater(() => { query.running = true })
  }

  Timer {
    interval: 1200
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: query.running = true
  }

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: root.playerOn ? root.accent : "transparent"
    opacity: root.playerOn ? 0.22 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  Item {
    id: glyph
    width: 16
    height: 16
    anchors.centerIn: parent
    opacity: root.playerOn ? 1 : 0.45
    rotation: 0

    Timer {
      interval: 32
      running: root.playing && root.playerOn
      repeat: true
      onTriggered: glyph.rotation = (glyph.rotation + 6) % 360
    }

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "#14110f"
      border.width: 1.5
      border.color: root.playing ? root.accent : root.fg
    }
    Rectangle {
      width: 5
      height: 5
      radius: 2.5
      anchors.centerIn: parent
      color: root.playing ? root.accent : root.fg
    }

    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) playPause.running = true
      else toggler.running = true
    }
  }
}
