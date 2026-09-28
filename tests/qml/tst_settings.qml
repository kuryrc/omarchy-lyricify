import QtQuick
import QtTest
import "../../ui" as Ui

Item {
    id: stage
    width: 640
    height: 760

    QtObject {
        id: fakeBackend
        property bool ready: true
        property string status: "ready"
        property var snapshot: ({player: {displayName: "Spotify"}, lyrics: {status: "disabled"}})
        property var scope: ({playerInstanceId: "fixture", trackKey: "original-fixture", trackEpoch: 1})
        property var bootstrap: ({ready: true, updatePending: false, downloadAvailable: false, status: "ready"})
        property var requests: []
        function request(operation, params, scoped) {
            requests.push({operation: operation, params: params, scoped: scoped});
        }
    }
    QtObject {
        id: fakePreferences
        property string language: "en"
        property bool remoteArtwork: false
        property int saves: 0
        property string error: ""
        property var display: ({width: 520, offsetX: 430, monitor: "", hideFullscreen: true, pauseCollapseMs: 5000})
        function saveDisplay(key, value) { var next = Object.assign({}, display); next[key] = value; display = next; saves++; }
        function saveLanguage(value) { language = value; saves++; }
        function saveRemoteArtwork(value) { remoteArtwork = value; saves++; }
    }
    Component {
        id: panelComponent
        Ui.SettingsPanel {
            width: stage.width
            height: stage.height
            backend: fakeBackend
            preferences: fakePreferences
            players: ["spotify", "mpv"]
        }
    }
    SignalSpy { id: exportSpy; signalName: "exportRequested" }
    SignalSpy { id: purgeSpy; signalName: "purgeRequested" }
    SignalSpy { id: exitSpy; signalName: "exitRequested" }
    SignalSpy { id: centerSpy; signalName: "centerRequested" }
    TestCase {
        name: "SettingsInteractions"
        when: windowShown
        property var panel
        function sourceSettings(qq, netease) { return {sources: [
            {id: "qq", name: "QQ Music", chineseName: "QQ 音乐", enabled: qq},
            {id: "netease", name: "NetEase Music", chineseName: "网易云音乐", enabled: netease}
        ]}; }
        function init() {
            fakeBackend.requests = [];
            fakeBackend.snapshot = {player: {displayName: "Spotify"}, lyrics: {status: "disabled"}};
            fakePreferences.language = "en";
            fakePreferences.remoteArtwork = false;
            fakePreferences.saves = 0;
            stage.height = 760;
            panel = createTemporaryObject(panelComponent, stage);
            verify(panel);
            panel.settings = sourceSettings(false, false);
            fakeBackend.bootstrap = {ready: true, updatePending: false, downloadAvailable: false, status: "ready", error: ""};
            exportSpy.target = panel;
            purgeSpy.target = panel;
            exitSpy.target = panel;
            centerSpy.target = panel;
            centerSpy.clear();
            exitSpy.clear();
            exportSpy.clear();
            purgeSpy.clear();
            waitForRendering(panel);
        }
        function control(name) {
            var result = findChild(panel, name);
            verify(result, name);
            return result;
        }
        function click(item) { mouseClick(item, item.width / 2, item.height / 2); }
        function reveal(item) {
            var scroll = control("settingsScroll");
            scroll.contentItem.contentY += item.mapToItem(scroll, 0, 0).y - 50;
            waitForRendering(panel);
        }
        function test_display_controls_and_center_action() {
            var fullscreen = control("islandFullscreen");
            reveal(fullscreen);
            var previous = fakePreferences.display.hideFullscreen;
            click(fullscreen);
            compare(fakePreferences.display.hideFullscreen, !previous);
            var width = control("islandWidth");
            reveal(width);
            mouseClick(width, width.width * 0.75, width.height / 2);
            verify(fakePreferences.display.width > 600 && fakePreferences.display.width <= 900);
            var center = control("centerIsland");
            reveal(center);
            click(center);
            compare(centerSpy.count, 1);
        }
        function test_runtime_errors_and_exit_are_accessible_without_player() {
            fakeBackend.bootstrap = {ready: false, updatePending: false, downloadAvailable: true, status: "needsRuntime", error: "hash_mismatch"};
            verify(control("runtimeStatus").text.indexOf("verification failed") >= 0);
            click(control("exitIsland"));
            compare(exitSpy.count, 1);
            compare(fakeBackend.requests.length, 0);
        }
        function test_registered_source_needs_no_source_specific_ui() {
            panel.settings = {sources: [{id: "fixture", name: "Original source", chineseName: "原创词源", enabled: false}]};
            click(control("fixtureEnabledSwitch"));
            compare(fakeBackend.requests, [{operation: "settings.update", params: {sources: {fixture: true}}, scoped: false}]);
        }
        function test_lyric_error_reason_is_visible() {
            panel.settings = sourceSettings(true, false);
            fakeBackend.snapshot = {player: {displayName: "Spotify"}, lyrics: {status: "error", errorCode: "invalid_lyrics"}};
            var status = control("lyricMatchStatus");
            verify(status.visible);
            verify(status.text.indexOf("could not be parsed") >= 0);
            fakeBackend.snapshot = {player: {displayName: "Spotify"}, lyrics: {status: "error", errorCode: "rate_limited"}};
            verify(status.text.indexOf("rate-limiting") >= 0);
            compare(fakeBackend.requests.length, 0);
        }
        function test_candidate_selection_keeps_resolution_scope() {
            panel.settings = sourceSettings(true, false);
            panel.candidateResolution = "fixture-resolution";
            panel.candidates = [{candidateId: "original", title: "Window of Light", artists: ["Fixture Artist"], album: "Test Album", provider: "qq", reasons: []}];
            fakeBackend.snapshot = {player: {displayName: "Spotify"}, lyrics: {status: "ready"}};
            var status = control("lyricMatchStatus");
            verify(status.visible);
            verify(status.text.indexOf("already loaded") >= 0);
            compare(fakeBackend.requests.length, 0);
            fakeBackend.snapshot = {player: {displayName: "Spotify"}, lyrics: {status: "ambiguous"}};
            verify(status.visible);
            verify(status.text.indexOf("Choose the correct version") >= 0);
            var scroll = control("settingsScroll");
            mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -1600, Qt.NoButton);
            tryCompare(scroll.contentItem, "moving", false);
            var candidate = control("lyricCandidate_original");
            click(candidate);
            compare(fakeBackend.requests, [{operation: "lyrics.select", params: {resolutionId: "fixture-resolution", candidateId: "original"}, scoped: true}]);
        }
        function test_switches_require_user_action() {
            var qq = control("qqEnabledSwitch");
            var netease = control("neteaseEnabledSwitch");
            compare(qq.checked, false);
            compare(netease.checked, false);
            compare(fakeBackend.requests.length, 0);
            panel.settings = sourceSettings(true, false);
            waitForRendering(panel);
            qq = control("qqEnabledSwitch");
            tryCompare(qq, "checked", true);
            compare(fakeBackend.requests.length, 0);
            panel.settings = sourceSettings(false, false);
            waitForRendering(panel);
            qq = control("qqEnabledSwitch");
            netease = control("neteaseEnabledSwitch");
            tryCompare(qq, "checked", false);
            click(qq);
            compare(JSON.stringify(fakeBackend.requests), JSON.stringify([{operation: "settings.update", params: {sources: {qq: true}}, scoped: false}]));
            compare(netease.checked, false);
            click(control("artworkSwitch"));
            compare(fakePreferences.remoteArtwork, true);
            compare(fakePreferences.saves, 1);
            compare(fakeBackend.requests.length, 1);
        }
        function test_language_selection_and_short_window_scroll() {
            var scroll = control("settingsScroll");
            compare(scroll.contentItem.contentY, 0);
            var language = control("languageSelector");
            click(language);
            tryCompare(language.popup, "visible", true);
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Return);
            tryCompare(fakePreferences, "language", "zh_CN");
            tryCompare(language.popup, "visible", false);
            compare(fakePreferences.saves, 1);
            waitForRendering(panel);
            stage.height = 520;
            tryVerify(function() { return scroll.contentHeight > scroll.height; });
            var remove = control("purgeData");
            var point = remove.mapToItem(panel, 0, 0);
            verify(point.y >= 0 && point.y + remove.height <= panel.height);
            mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -1600, Qt.NoButton);
            var exportButton = control("exportDiagnostics");
            tryVerify(function() {
                var p = exportButton.mapToItem(scroll, 0, 0);
                return p.y >= 0 && p.y + exportButton.height <= scroll.height;
            });
            tryCompare(scroll.contentItem, "moving", false);
            click(exportButton);
            compare(exportSpy.count, 1);
            click(remove);
            compare(purgeSpy.count, 1);
            compare(fakeBackend.requests.length, 0);
            waitForRendering(panel);
        }
    }
}
