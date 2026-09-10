import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import "Model.js" as Model

// Large spinning vinyl on the desktop. Lives on the Bottom layer, so it sits
// on top of wallpaper.blur (Background) and under ordinary windows.
//
// The surface itself is a full-screen click-through sheet; only the record
// and the Spotmarchy transport card take input. Spotify (and other MPRIS
// players) are driven through Quickshell's own service — no playerctl.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- tunables
  // Edit these, then `omarchy restart shell`. Sizes are in pixels.
  property int discSize: 560
  property bool showTonearm: true
  property bool hideWhenClosed: false
  property bool playerVisible: true
  property color accent: "#1DB954"
  property color foreground: "#f4f0ea"
  property color dim: "#b9b3aa"
  property color dimmer: "#8a8580"
  property color cardFill: "#cc14110f"

  // ------------------------------------------------------------------ player
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Model.findPlayer(players)
  readonly property bool live: player !== null && player !== undefined
  readonly property bool playing: live && player.isPlaying === true
  readonly property string trackTitle: live ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: live ? String(player.trackArtist || "") : ""
  readonly property string trackAlbum: live ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: live ? String(player.trackArtUrl || "") : ""
  readonly property real trackLength: live && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real trackPosition: {
    if (!live || !player.positionSupported) return 0
    var pos = Math.max(0, player.position)
    return trackLength > 0 ? Math.min(pos, trackLength) : pos
  }
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0
  readonly property bool canSeek: live && player.canSeek && trackLength > 0
  readonly property bool shuffleOn: live && player.shuffleSupported && player.shuffle === true
  readonly property int loopState: live && player.loopSupported ? player.loopState : MprisLoopState.None
  readonly property string loopIcon: loopState === MprisLoopState.Track ? "󰑘"
    : loopState === MprisLoopState.Playlist ? "󰑖"
    : "󰑗"
  readonly property string loopName: loopState === MprisLoopState.Track ? "track"
    : loopState === MprisLoopState.Playlist ? "playlist"
    : "off"
  readonly property bool shown: playerVisible && (live || !hideWhenClosed)

  // ------------------------------------------------------------ album colour
  property string artDominant: ""
  property string artMean: ""
  property real artLuma: 0
  property string artProbed: ""
  property string artProbeError: ""
  property string artFile: ""
  readonly property string artSourceUrl: Model.fileUrl(artFile)
  readonly property color artAccent: artDominant === "" ? accent : Model.ensureContrast(artDominant, 0.48)

  onArtUrlChanged: artProbeDelay.restart()
  Component.onCompleted: probeArt(false)

  function probeArt(force) {
    var target = Model.artProbeTarget(root.artUrl)
    if (!target) {
      root.forgetArt()
      return
    }
    if (!force && root.artProbed === root.artUrl) return
    if (artProbe.running) artProbe.running = false
    artProbe.pending = root.artUrl
    artProbe.command = ["/bin/sh", "-c", Model.artProbeScript(), "sh", target]
    artProbe.running = true
  }

  function forgetArt() {
    root.artFile = ""
    root.artDominant = ""
    root.artMean = ""
    root.artLuma = 0
    root.artProbed = ""
  }

  function applyArtProbe(url, text) {
    if (url !== root.artUrl) return
    var probe = Model.parseArtProbe(text)
    if (!probe) {
      root.artProbeError = "no colour in probe output"
      return
    }
    root.artProbeError = ""
    root.artFile = probe.file
    root.artDominant = probe.dominant
    root.artMean = probe.mean
    root.artLuma = probe.luma
    root.artProbed = url
  }

  Timer {
    id: artProbeDelay
    interval: 250
    onTriggered: root.probeArt(false)
  }

  Process {
    id: artProbe
    property string pending: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyArtProbe(artProbe.pending, text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.artProbeError = "probe exited " + exitCode
    }
  }

  // ----------------------------------------------------------------- actions
  function playPause() {
    if (!live) {
      launch()
      return false
    }
    if (player.canTogglePlaying) {
      player.togglePlaying()
      return true
    }
    if (playing && player.canPause) {
      player.pause()
      return true
    }
    if (!playing && player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function skipNext() {
    if (!live || !player.canGoNext) return false
    player.next()
    return true
  }

  function skipPrevious() {
    if (!live || !player.canGoPrevious) return false
    player.previous()
    return true
  }

  function seekTo(seconds) {
    if (!canSeek) return false
    player.position = Math.max(0, Math.min(trackLength, seconds))
    return true
  }

  function nudgeVolume(delta) {
    if (!live || !player.volumeSupported) return false
    player.volume = Math.max(0, Math.min(1, player.volume + delta))
    return true
  }

  function toggleShuffle() {
    if (!live || !player.shuffleSupported) return false
    player.shuffle = !player.shuffle
    return true
  }

  function cycleLoop() {
    if (!live || !player.loopSupported) return false
    player.loopState = loopState === MprisLoopState.None ? MprisLoopState.Playlist
      : loopState === MprisLoopState.Playlist ? MprisLoopState.Track
      : MprisLoopState.None
    return true
  }

  function launch() {
    Quickshell.execDetached(["omarchy", "launch", "spotify"])
  }

  function statusJson() {
    return JSON.stringify({
      running: root.live,
      playing: root.playing,
      visible: root.playerVisible,
      title: root.trackTitle,
      artist: root.trackArtist,
      album: root.trackAlbum,
      position: root.trackPosition,
      length: root.trackLength,
      shuffle: root.shuffleOn,
      loop: root.loopName,
      artFile: root.artFile
    })
  }

  Timer {
    running: root.playing && root.shown
    interval: 500
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  component TransportButton: Item {
    id: btn
    property string glyph: ""
    property bool active: false
    property bool accented: false
    property bool large: false
    signal clicked()

    width: large ? 42 : 32
    height: large ? 42 : 32
    opacity: enabled ? 1 : 0.35

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: btn.accented ? root.artAccent : (btn.active ? "#33ffffff" : "transparent")
      opacity: btn.accented ? 0.18 : 1
    }

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: btn.accented ? root.artAccent : root.foreground
      font.pixelSize: btn.large ? 22 : 16
      opacity: btn.active || btn.accented ? 1 : 0.7
    }

    MouseArea {
      anchors.fill: parent
      enabled: btn.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  IpcHandler {
    target: "vinyl.player"

    function toggle(): void { root.playerVisible = !root.playerVisible }
    function enable(): void { root.playerVisible = true }
    function disable(): void { root.playerVisible = false }
    function getEnabled(): bool { return root.playerVisible }
    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function next(): string { return root.skipNext() ? "ok" : "unhandled" }
    function previous(): string { return root.skipPrevious() ? "ok" : "unhandled" }
    function shuffle(): string { return root.toggleShuffle() ? "ok" : "unhandled" }
    function loop(): string { return root.cycleLoop() ? "ok" : "unhandled" }
    function launch(): void { root.launch() }
    function status(): string { return root.statusJson() }
    function reprobeArt(): void { root.probeArt(true) }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: surface
        required property var modelData

        screen: modelData
        visible: root.shown
        color: "transparent"

        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.namespace: "vinyl-player"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        // Only the record and the transport card take a click. Everything
        // else falls through to the wallpaper (and wallpaper.blur under it).
        mask: Region { item: player }

        Item {
          id: player
          width: root.discSize + 80
          height: root.discSize + 196
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Math.round(parent.height * 0.04)

          // Soft contact shadow so the record actually sits on the blur.
          Rectangle {
            id: contact
            width: disc.width * 0.86
            height: 36
            radius: 18
            color: "#66000000"
            anchors.horizontalCenter: disc.horizontalCenter
            anchors.top: disc.bottom
            anchors.topMargin: -18
            z: 0
          }

          Item {
            id: disc
            width: root.discSize
            height: root.discSize
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            z: 1

            property real spin: 0

            Timer {
              interval: 16
              running: root.playing && root.shown
              repeat: true
              onTriggered: disc.spin = (disc.spin + 3.33) % 360
            }

            // Platter / outer rim
            Rectangle {
              id: platter
              anchors.fill: parent
              radius: width / 2
              color: "#070707"
              border.width: Math.max(6, Math.round(width * 0.018))
              border.color: "#2a2420"
              rotation: disc.spin
              antialiasing: true

              // Grooves
              Canvas {
                id: grooves
                anchors.fill: parent
                anchors.margins: platter.border.width
                onPaint: {
                  var ctx = getContext("2d")
                  var w = width, h = height
                  var cx = w / 2, cy = h / 2
                  var rMax = Math.min(w, h) / 2 - 2
                  var rMin = Math.min(w, h) * 0.195
                  ctx.clearRect(0, 0, w, h)
                  for (var r = rMin; r < rMax; r += 2.4) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    var ring = Math.floor(r) % 7 === 0
                    ctx.strokeStyle = ring ? "rgba(255,255,255,0.055)" : "rgba(0,0,0,0.42)"
                    ctx.lineWidth = 1
                    ctx.stroke()
                  }
                }
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()
              }

              // Specular sheen
              Rectangle {
                anchors.fill: parent
                radius: width / 2
                rotation: -disc.spin
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.00; color: "#22ffffff" }
                  GradientStop { position: 0.28; color: "#00000000" }
                  GradientStop { position: 0.62; color: "#00000000" }
                  GradientStop { position: 1.00; color: "#18000000" }
                }
              }

              // Album label
              Item {
                id: label
                width: parent.width * 0.38
                height: width
                anchors.centerIn: parent

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: "#e8dcc8"
                  border.width: 2
                  border.color: "#1a120c"
                  clip: true

                  Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    source: root.artSourceUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: root.artSourceUrl === ""
                    text: "VINYL"
                    color: "#3a2a1c"
                    font.pixelSize: Math.round(label.width * 0.14)
                    font.letterSpacing: 2
                    font.bold: true
                  }
                }

                Rectangle {
                  width: Math.max(10, label.width * 0.09)
                  height: width
                  radius: width / 2
                  anchors.centerIn: parent
                  color: "#1a1512"
                  border.width: 2
                  border.color: "#cfc3b0"
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.playPause()
            }
          }

          // Tonearm
          Item {
            id: arm
            visible: root.showTonearm
            width: 18
            height: disc.height * 0.58
            z: 2
            anchors.left: disc.right
            anchors.leftMargin: -disc.width * 0.08
            anchors.top: disc.top
            anchors.topMargin: disc.height * 0.04
            transformOrigin: Item.Top
            rotation: root.playing ? 24 : -12
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

            Rectangle {
              width: 10
              height: 10
              radius: 5
              color: "#d9d0c4"
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
            }
            Rectangle {
              width: 4
              height: parent.height - 22
              radius: 2
              color: "#c8c0b4"
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 8
            }
            Rectangle {
              width: 12
              height: 18
              radius: 3
              color: "#2a2420"
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
            }
          }

          // Spotmarchy transport, docked under the record.
          Rectangle {
            id: card
            width: Math.min(parent.width, root.discSize * 0.92)
            height: 168
            radius: 18
            color: root.cardFill
            border.width: 1
            border.color: "#28ffffff"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: disc.bottom
            anchors.topMargin: 10
            z: 3

            Column {
              anchors.fill: parent
              anchors.margins: 14
              spacing: 8

              Row {
                width: parent.width
                spacing: 10
                height: 36

                Rectangle {
                  width: 36
                  height: 36
                  radius: 8
                  color: "#22ffffff"
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: root.artSourceUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: root.artSourceUrl === ""
                    text: ""
                    color: root.artAccent
                    font.pixelSize: 16
                  }
                }

                Column {
                  width: parent.width - 46
                  spacing: 2
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    width: parent.width
                    text: root.live ? (root.trackTitle || "Nothing playing") : "Spotify is not running"
                    color: root.foreground
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: root.trackArtist
                    color: root.dim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    visible: text !== ""
                  }
                }
              }

              Item {
                id: seek
                width: parent.width
                height: 28
                visible: root.live && root.trackLength > 0
                property real liveProgress: root.progress

                Rectangle {
                  id: seekTrack
                  height: 4
                  radius: 2
                  color: "#33ffffff"
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: 6

                  Rectangle {
                    width: seekTrack.width * seek.liveProgress
                    height: parent.height
                    radius: 2
                    color: root.artAccent
                  }
                }

                Text {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  text: Model.formatTime(root.trackPosition)
                  color: root.dim
                  font.pixelSize: 10
                }
                Text {
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  text: Model.formatTime(root.trackLength)
                  color: root.dim
                  font.pixelSize: 10
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.canSeek
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    root.seekTo((mouse.x / width) * root.trackLength)
                  }
                }
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                height: 36

                TransportButton {
                  glyph: "󰒝"
                  active: root.shuffleOn
                  enabled: root.live && root.player && root.player.shuffleSupported
                  onClicked: root.toggleShuffle()
                }
                TransportButton {
                  glyph: "󰒮"
                  enabled: root.live && root.player && root.player.canGoPrevious
                  onClicked: root.skipPrevious()
                }
                TransportButton {
                  glyph: root.playing ? "󰏤" : "󰐊"
                  accented: true
                  large: true
                  enabled: root.live
                  onClicked: root.playPause()
                }
                TransportButton {
                  glyph: "󰒭"
                  enabled: root.live && root.player && root.player.canGoNext
                  onClicked: root.skipNext()
                }
                TransportButton {
                  glyph: root.loopIcon
                  active: root.loopState !== MprisLoopState.None
                  enabled: root.live && root.player && root.player.loopSupported
                  onClicked: root.cycleLoop()
                }
              }

              Row {
                width: parent.width
                spacing: 8
                height: 18
                visible: root.live && root.player && root.player.volumeSupported

                Text {
                  text: root.live && root.player.volume < 0.01 ? "󰝟" : "󰕾"
                  color: root.dim
                  font.pixelSize: 14
                  width: 20
                  horizontalAlignment: Text.AlignHCenter
                }

                Item {
                  id: vol
                  width: parent.width - 28
                  height: 18
                  anchors.verticalCenter: parent.verticalCenter

                  Rectangle {
                    id: volTrack
                    height: 4
                    radius: 2
                    color: "#33ffffff"
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                      width: volTrack.width * (root.live ? root.player.volume : 0)
                      height: parent.height
                      radius: 2
                      color: root.artAccent
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      if (root.live) root.player.volume = Math.max(0, Math.min(1, mouse.x / width))
                    }
                    onPositionChanged: function(mouse) {
                      if (pressed && root.live)
                        root.player.volume = Math.max(0, Math.min(1, mouse.x / width))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
