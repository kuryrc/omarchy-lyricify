// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import "../core/I18n.js" as I18n
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "SettingsStyle.js" as Style

PanelWindow {
    id: root

    required property var backend
    required property var preferences
    property bool opened: false
    property bool demo: false
    property var monitorNames: []
    property var settings: ({
        "sources": []
    })
    property var players: []
    property var candidates: []
    property string candidateResolution: ""
    property string message: ""

    signal dismissed()
    signal useLive()
    signal exitRequested()
    signal centerRequested()
    signal resetPositionRequested()

    function tr(en, zh) {
        return I18n.text(preferences.language, en, zh);
    }

    function refresh() {
        if (!backend.ready)
            return ;

        backend.request("settings.get", {
        }, false);
        backend.request("player.list", {
        }, false);
        if (backend.scope)
            backend.request("lyrics.candidates", {
        }, true);

    }

    visible: opened
    implicitWidth: Math.min(640, screen ? screen.width - 48 : 640)
    implicitHeight: Math.min(760, screen ? screen.height - 48 : 760)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lyric-island-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    onVisibleChanged: {
        if (visible) {
            refresh();
            Qt.callLater(function() {
                panel.forceActiveFocus();
            });
        } else {
            dismissed();
        }
    }

    Connections {
        function onReadyChanged() {
            if (root.opened && root.backend.ready)
                root.refresh();

        }

        function onResponse(id, operation, result, code) {
            if (!root.opened)
                return ;

            if (code) {
                root.message = I18n.status(root.preferences.language, code);
                return ;
            }
            if (operation === "settings.get" || operation === "settings.update") {
                root.settings = result;
            } else if (operation === "player.list") {
                root.players = result.players;
            } else if (operation === "lyrics.candidates") {
                root.candidates = result.candidates;
                root.candidateResolution = result.resolutionId;
            } else if (operation === "diagnostics.export")
                root.message = root.tr("Diagnostics saved", "诊断已保存");
            else if (operation === "lyrics.import")
                root.message = root.tr("Lyrics imported", "歌词已导入");
            else if (operation === "cache.clear")
                root.message = root.tr("Cache cleared; your imports and corrections are kept", "缓存已清理，导入和校正已保留");
        }

        function onSnapshotChanged() {
            if (root.opened && root.backend.scope)
                root.backend.request("lyrics.candidates", {
            }, true);

        }

        target: root.backend
    }

    FileDialog {
        id: importer

        title: root.tr("Import lyrics", "导入歌词")
        nameFilters: ["Lyrics (*.lrc *.qrc *.yrc *.json)"]
        onAccepted: root.backend.request("lyrics.import", {
            "path": decodeURIComponent(selectedFile.toString().replace("file://", ""))
        }, true)
    }

    C.Dialog {
        id: purgeConfirm

        title: root.tr("Delete local data?", "删除本地数据？")
        modal: true
        width: Math.min(440, root.width - 48)
        implicitHeight: 260
        padding: 22
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        onAccepted: root.backend.purgeData()
        onOpened: cancelDelete.forceActiveFocus()

        background: Rectangle {
            color: Style.surface
            radius: 18
            border.color: Style.border
        }

        header: SettingsLabel {
            text: purgeConfirm.title
            font.pixelSize: 17
            font.weight: Font.DemiBold
            padding: 22
            bottomPadding: 0
        }

        contentItem: SettingsLabel {
            text: root.tr("Saved positions, preferences, imported lyrics, timing adjustments, cache and downloaded runtimes will be removed. The plugin stays installed.", "将删除位置、偏好、导入歌词、校正、缓存和下载的运行组件。插件本身会保留安装。")
            font.pixelSize: 13
            color: Style.secondary
        }

        footer: Item {
            implicitHeight: 62

            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.top: parent.top
                spacing: 10

                SettingsButton {
                    id: cancelDelete

                    text: root.tr("Cancel", "取消")
                    onClicked: purgeConfirm.reject()
                }

                SettingsButton {
                    destructive: true
                    text: root.tr("Delete data", "删除数据")
                    onClicked: purgeConfirm.accept()
                }

            }

        }

    }

    FileDialog {
        id: diagnostics

        title: root.tr("Save diagnostics", "保存诊断")
        fileMode: FileDialog.SaveFile
        nameFilters: ["JSON (*.json)"]
        defaultSuffix: "json"
        onAccepted: root.backend.request("diagnostics.export", {
            "path": decodeURIComponent(selectedFile.toString().replace("file://", ""))
        }, false)
    }

    SettingsPanel {
        id: panel

        anchors.fill: parent
        backend: root.backend
        preferences: root.preferences
        demo: root.demo
        monitorNames: root.monitorNames
        onCenterRequested: root.centerRequested()
        onResetPositionRequested: root.resetPositionRequested()
        settings: root.settings
        players: root.players
        candidates: root.candidates
        candidateResolution: root.candidateResolution
        message: root.message
        onCloseRequested: root.dismissed()
        onExitRequested: root.exitRequested()
        onUseLive: root.useLive()
        onImportRequested: importer.open()
        onExportRequested: diagnostics.open()
        onPurgeRequested: purgeConfirm.open()
    }

}
