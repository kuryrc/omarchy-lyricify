import "Artwork.js" as Artwork
import "I18n.js" as I18n
import QtQuick

Item {
    id: root

    property bool demo: false
    property bool active: true
    property string language: "auto"
    property bool remoteArtwork: false
    property bool tickEnabled: true
    property alias demoPlaying: preview.demoPlaying
    property alias demoAvailable: preview.demoAvailable
    readonly property var source: demo ? preview : live
    readonly property bool available: source.available
    readonly property bool playing: source.playing
    readonly property real positionMs: source.positionMs
    readonly property real durationMs: source.durationMs
    readonly property string title: source.title
    readonly property string artist: source.artist
    readonly property string artUrl: demo ? preview.artUrl : Artwork.source(live.artUrl, remoteArtwork)
    readonly property var lines: source.lines
    readonly property string documentId: demo ? "demo" : live.documentId
    readonly property real offsetMs: demo ? 0 : live.offsetMs
    readonly property string lyricStatus: demo ? "ready" : live.lyricStatus
    readonly property string statusText: demo ? I18n.text(language, "Original preview · Interlude", "原创动画演示 · 间奏") : live.statusText
    readonly property string error: source.error
    readonly property bool canSeek: source.canSeek
    readonly property bool canToggle: source.canToggle
    readonly property bool canNext: source.canNext
    readonly property bool canPrevious: source.canPrevious
    readonly property var backend: live.client

    function seek(ms) {
        source.seek(ms);
    }

    function togglePlaying() {
        source.togglePlaying();
    }

    function next() {
        source.next();
    }

    function previous() {
        source.previous();
    }

    function adjustOffset(delta) {
        if (!demo)
            live.adjustOffset(delta);

    }

    DemoPlayback {
        id: preview

        tickEnabled: root.demo && root.tickEnabled
    }

    PlaybackView {
        id: live

        language: root.language
        active: root.active && !root.demo
        tickEnabled: root.tickEnabled
    }

}
