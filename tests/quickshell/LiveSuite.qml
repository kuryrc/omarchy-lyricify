import QtQuick
import Quickshell
import Quickshell.Io
import "../../core" as Core

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 64; implicitHeight: 64
        Core.PlaybackView { id: view; active: true; tickEnabled: true }
    }
    IpcHandler {
        target: "liveTest"
        function state(): string {
            return JSON.stringify({status: view.client.status, epoch: view.client.epoch,
                available: view.available, playing: view.playing, positionMs: view.positionMs,
                canToggle: view.canToggle, documentId: view.documentId, scope: view.client.scope});
        }
        function command(operation: string, parameters: string): string {
            return view.client.request(operation, JSON.parse(parameters), operation.indexOf("playback.") === 0 || operation.indexOf("lyrics.") === 0);
        }
        function enabled(value: bool): string { view.active = value; return "ok"; }
        function ticking(value: bool): string { view.tickEnabled = value; return "ok"; }
        function quit(): string { Qt.callLater(Qt.quit); return "ok"; }
    }
}
