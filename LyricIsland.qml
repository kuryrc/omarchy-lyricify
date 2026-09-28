// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "core" as Core
import "core/I18n.js" as I18n
import "core/Release.js" as Release
import "core/Timeline.js" as Timeline
import "ui" as Ui

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool demo: false
    property bool opened: true
    property bool expanded: false
    property bool settingsOpen: false
    property bool pauseElapsed: false
    property bool fullscreenSimulation: false
    property bool collectMetrics: demo
    property real offsetMs: 0
    readonly property real configuredWidth: uiPreferences.display.width
    readonly property real configuredOffsetX: uiPreferences.display.offsetX
    property real dragOffset: 0
    property real dragStartOffset: 0
    property bool dragging: false
    property bool snapped: false
    readonly property real offsetX: dragging ? dragOffset : (Number.isFinite(positionStore.savedOffset) ? positionStore.savedOffset : configuredOffsetX)
    readonly property string monitorName: uiPreferences.display.monitor
    readonly property bool hideFullscreen: uiPreferences.display.hideFullscreen
    readonly property int pauseCollapseMs: uiPreferences.display.pauseCollapseMs
    property var stats: Timeline.newStats()
    readonly property bool collapsed: pauseElapsed && !playerState.playing && !expanded
    readonly property var selectedScreen: {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) if (screens[i].name === monitorName) {
            return screens[i];
        }
        return screens.length ? screens[0] : null;
    }
    readonly property var monitor: selectedScreen ? Hyprland.monitorFor(selectedScreen) : null
    readonly property bool fullscreen: {
        if (fullscreenSimulation)
            return true;

        if (!monitor)
            return false;

        var windows = Hyprland.toplevels.values;
        for (var i = 0; i < windows.length; i++) {
            var win = windows[i];
            if (win.monitor === monitor && win.workspace === monitor.activeWorkspace && win.wayland && win.wayland.fullscreen)
                return true;

        }
        return false;
    }
    readonly property bool shown: opened && playerState.available && !(hideFullscreen && fullscreen)
    readonly property real maxWidth: Timeline.placement(selectedScreen ? selectedScreen.width : 2560, configuredWidth, offsetX).width
    readonly property real leftEdge: Timeline.placement(selectedScreen ? selectedScreen.width : 2560, configuredWidth, offsetX).x

    function beginMove() {
        dragStartOffset = leftEdge - ((selectedScreen ? selectedScreen.width : 2560) - maxWidth) / 2;
        dragOffset = dragStartOffset;
        snapped = Math.abs(dragOffset) < 0.5;
        dragging = true;
    }

    function moveBy(deltaX) {
        if (!dragging || !Number.isFinite(deltaX))
            return ;

        var placement = Timeline.dragPlacement(selectedScreen ? selectedScreen.width : 2560, configuredWidth, dragStartOffset + deltaX, snapped);
        dragOffset = placement.offset;
        snapped = placement.snapped;
    }

    function finishMove(canceled) {
        if (!dragging)
            return ;

        if (!canceled)
            positionStore.save(dragOffset);

        dragging = false;
        snapped = false;
    }

    function open(payloadJson) {
        lifecycle.start();
        if (payloadJson) {
            try {
                var payload = JSON.parse(payloadJson);
                if (typeof payload.demo === "boolean")
                    demo = payload.demo;

                if (payload.settings === true)
                    settingsOpen = true;

            } catch (_) {
                return ;
            }
        }
        opened = true;
        if (!demo && !playerState.available)
            settingsOpen = true;

    }

    function close() {
        opened = false;
        expanded = false;
    }

    function toggle() {
        opened ? close() : open("");
    }

    function state() {
        return {
            "version": Release.version,
            "displaySettings": uiPreferences.display,
            "demo": demo,
            "backendStatus": demo ? "demo" : playerState.backend.status,
            "lyricsStatus": playerState.lyricStatus,
            "settingsOpen": settingsOpen,
            "available": playerState.available,
            "shown": shown,
            "playing": playerState.playing,
            "expanded": expanded,
            "collapsed": collapsed,
            "fullscreen": fullscreen,
            "positionMs": Math.round(playerState.positionMs),
            "lineIndex": content.activeIndex,
            "offsetMs": offsetMs,
            "offsetX": offsetX,
            "dragging": dragging,
            "snapped": snapped,
            "positionError": positionStore.error,
            "pauseElapsed": pauseElapsed,
            "pauseTimerRunning": pauseTimer.running,
            "x": leftEdge,
            "width": maxWidth,
            "height": card.height,
            "error": playerState.error,
            "render": content.renderState()
        };
    }

    Core.Playback {
        id: playerState

        active: lifecycle.running
        language: uiPreferences.language
        remoteArtwork: uiPreferences.remoteArtwork
        demo: root.demo
        tickEnabled: root.shown
        onPlayingChanged: root.pauseElapsed = false
        onAvailableChanged: {
            if (!available) {
                root.expanded = false;
                root.pauseElapsed = false;
            }
        }
    }

    Core.PositionStore {
        id: positionStore

        language: uiPreferences.language
        demo: root.demo
    }

    Core.UiPreferences {
        id: uiPreferences
    }

    Connections {
        function onSettled() {
            if (playerState.backend.bootstrap.state.status === "purged") {
                uiPreferences.reset();
                positionStore.reset();
            }
        }

        target: playerState.backend.bootstrap
    }

    Process {
        command: ["python3", Qt.resolvedUrl("scripts/launch.py").toString().replace("file://", ""), "--register"]
        running: !!root.shell && !!root.manifest
    }

    Core.IslandSession {
        id: lifecycle

        demo: root.demo
        runtimeStatus: playerState.backend.bootstrap.status
        backendStatus: playerState.backend.status
        onSettingsRequested: root.settingsOpen = true
        onExitRequested: {
            root.settingsOpen = false;
            root.close();
            if (root.shell && root.manifest)
                disablePlugin.running = true;
            else
                Qt.callLater(Qt.quit);
        }
    }

    Process {
        id: disablePlugin

        command: ["omarchy", "plugin", "disable", "kuryrc.lyricify"]
        onExited: (code) => {
            if (code !== 0) {
                lifecycle.start();
                root.opened = true;
                root.settingsOpen = true;
                settingsWindow.message = I18n.text(uiPreferences.language, "Could not disable Lyric Island. Try again.", "无法停用灵动岛，请重试。");
            }
        }
    }

    Ui.SettingsWindow {
        id: settingsWindow

        backend: playerState.backend
        preferences: uiPreferences
        opened: root.settingsOpen
        demo: root.demo
        monitorNames: Quickshell.screens.map(function(screen) {
            return screen.name;
        })
        onCenterRequested: positionStore.save(0)
        onResetPositionRequested: positionStore.save(uiPreferences.display.offsetX)
        onDismissed: root.settingsOpen = false
        onUseLive: root.demo = false
        onExitRequested: lifecycle.stop()
    }

    Timer {
        id: pauseTimer

        interval: root.pauseCollapseMs
        running: playerState.available && !playerState.playing && !root.pauseElapsed && !root.dragging
        onTriggered: root.pauseElapsed = true
    }

    PanelWindow {
        id: panel

        screen: root.selectedScreen
        visible: root.selectedScreen !== null
        color: "transparent"
        // A fixed surface keeps pointer scene coordinates stable throughout a drag.
        implicitHeight: 392
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "lyric-island"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            left: true
            right: true
        }

        Item {
            id: emptyRegion

            width: 0
            height: 0
        }

        Item {
            id: card

            readonly property real refreshHz: Screen.refreshRate > 0 ? Screen.refreshRate : 60

            x: root.leftEdge + (root.maxWidth - width) / 2
            width: root.collapsed ? 262 : root.maxWidth
            height: root.collapsed ? 48 : (root.expanded ? 348 : 86)
            y: root.shown ? 0 : -height
            opacity: root.shown ? 1 : 0
            visible: opacity > 0

            Ui.IslandShape {
                anchors.fill: parent
            }

            Ui.IslandContent {
                id: content

                anchors.fill: parent
                playback: playerState
                expanded: root.expanded
                collapsed: root.collapsed
                offsetMs: root.demo ? root.offsetMs : playerState.offsetMs
                motion: root.shown
                onToggleExpanded: root.expanded = !root.expanded
                onOpenSettings: root.settingsOpen = true
                onAdjustOffset: (delta) => {
                    if (root.demo)
                        root.offsetMs += delta;
                    else
                        playerState.adjustOffset(delta);
                }
                onMoveStarted: root.beginMove()
                onMoveRequested: (deltaX) => {
                    return root.moveBy(deltaX);
                }
                onMoveFinished: (canceled) => {
                    return root.finishMove(canceled);
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on height {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on y {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                }

            }

        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 1
            height: card.height + 12
            visible: root.dragging
            color: root.snapped ? "#72ecac" : "#7e979086"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: card.height + 16
            visible: root.dragging && root.snapped
            text: I18n.text(uiPreferences.language, "Centered", "居中")
            font.family: "Noto Sans CJK SC"
            font.pixelSize: 11
            color: "#baffd9"
        }

        Text {
            x: root.leftEdge
            y: card.height + 14
            width: root.maxWidth
            horizontalAlignment: Text.AlignHCenter
            visible: root.shown && !root.dragging && positionStore.error !== ""
            text: positionStore.error
            color: "#ffd3a4"
            font.family: "Noto Sans CJK SC"
            font.pixelSize: 12
        }

        mask: Region {
            item: root.shown ? card : emptyRegion
        }

    }

    FrameAnimation {
        running: root.collectMetrics && root.shown && playerState.playing
        onTriggered: Timeline.sample(root.stats, frameTime * 1000, card.refreshHz)
    }

    IpcHandler {
        function openIsland() : string {
            root.demo = false;
            root.open("");
            return "ok";
        }

        function quit() : string {
            Qt.callLater(lifecycle.stop);
            return "ok";
        }

        function state() : string {
            return JSON.stringify(root.state());
        }

        function metrics() : string {
            return JSON.stringify(Timeline.statsReport(root.stats));
        }

        function resetMetrics() : string {
            root.stats = Timeline.newStats();
            return "ok";
        }

        function settings(enabled: bool) : string {
            root.settingsOpen = enabled;
            return "ok";
        }

        function preview(enabled: bool) : string {
            root.demo = enabled;
            root.opened = true;
            return "ok";
        }

        function expand(enabled: bool) : string {
            root.expanded = enabled;
            return "ok";
        }

        function pause(paused: bool) : string {
            if (!root.demo)
                return "Demo control only";

            playerState.demoPlaying = !paused;
            return "ok";
        }

        function seek(ms: real) : string {
            if (!root.demo)
                return "Demo control only";

            playerState.seek(ms);
            return "ok";
        }

        function simulateFullscreen(enabled: bool) : string {
            if (!root.demo)
                return "Demo control only";

            root.fullscreenSimulation = enabled;
            return "ok";
        }

        function available(enabled: bool) : string {
            if (!root.demo)
                return "Demo control only";

            playerState.demoAvailable = enabled;
            return "ok";
        }

        function offset(ms: real) : string {
            if (!Number.isFinite(ms))
                return "Invalid offset";

            root.offsetMs = Timeline.clamp(ms, -10000, 10000);
            return "ok";
        }

        function setShown(enabled: bool) : string {
            root.opened = enabled;
            return "ok";
        }

        function movePreview(deltaX: real, finish: bool) : string {
            if (!root.demo || !Number.isFinite(deltaX))
                return "Demo control only";

            if (!root.dragging)
                root.beginMove();

            root.moveBy(deltaX);
            if (finish)
                root.finishMove(false);

            return "ok";
        }

        target: "lyricIsland"
    }

}
