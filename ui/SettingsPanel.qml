// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import "../core/I18n.js" as I18n
import "../core/Release.js" as Release
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Layouts
import "SettingsStyle.js" as Style

FocusScope {
    id: root

    required property var backend
    required property var preferences
    property bool demo: false
    property var monitorNames: []
    property var settings: ({
        "sources": []
    })
    property var players: []
    property var candidates: []
    property string candidateResolution: ""
    property string message: ""
    readonly property bool hasPlayer: !!(backend.ready && backend.snapshot && backend.snapshot.player)
    readonly property bool canFindLyrics: backend.ready && backend.scope !== null
    readonly property bool onlineEnabled: (settings.sources || []).some(function(source) {
        return source.enabled;
    })

    signal closeRequested()
    signal exitRequested()
    signal useLive()
    signal importRequested()
    signal exportRequested()
    signal purgeRequested()
    signal centerRequested()
    signal resetPositionRequested()

    function tr(en, zh) {
        return I18n.text(preferences.language, en, zh);
    }

    function playerName(id) {
        return id === "spotify" ? "Spotify" : id === "mpv" ? "mpv" : id;
    }

    function lyricStatusText() {
        if (!backend.snapshot)
            return tr("Play a song to find lyrics.", "播放一首歌曲后开始匹配。");

        var status = backend.snapshot.lyrics.status;
        if (status === "ready" && backend.snapshot.lyrics.errorCode === "cache_write_failed")
            return tr("Lyrics loaded, but could not be cached for later.", "歌词已加载，但未能缓存供下次使用。");

        if (status === "ready")
            return candidates.length ? tr("Lyrics already loaded. Choose below only to switch versions.", "歌词已加载，无需再选；下方列表可用于更换版本。") : tr("Lyrics loaded. Synced with your player.", "歌词已加载，与播放器进度同步。");

        if (status === "ambiguous")
            return tr("No certain match. Choose the correct version below.", "暂时无法确定匹配，请在下方选择正确版本。");

        return I18n.lyricStatus(preferences.language, status, backend.snapshot.lyrics.errorCode);
    }

    function candidateHint(candidate) {
        var explanations = {
            "title_or_version_differs": tr("Different title or version", "歌名或版本不同"),
            "artists_differ": tr("Different artists", "艺人不同"),
            "additional_artist_credits": tr("Same primary artist; guest credits differ", "主要艺人相同，合作署名有差异"),
            "duration_differs_or_missing": tr("Check the track length", "需确认歌曲时长"),
            "album_differs_or_missing": tr("Different album release", "专辑发行信息不同"),
            "recording_version_differs": tr("Different recording version", "录音版本不同")
        };
        var reasons = (candidate.reasons || []).map(function(reason) {
            return explanations[reason] || reason;
        });
        return reasons.length ? reasons.join(" · ") : tr("Title, artists, album and length match", "歌名、艺人、专辑和时长匹配");
    }

    implicitWidth: 640
    implicitHeight: 760
    focus: true
    Keys.onEscapePressed: closeRequested()

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Style.background
        border.color: Style.border
    }

    RowLayout {
        id: header

        x: 28
        y: 26
        width: parent.width - 56
        height: 46
        spacing: 14

        Rectangle {
            implicitWidth: 44
            implicitHeight: 44
            Layout.minimumWidth: 44
            Layout.maximumWidth: 44
            radius: 13
            color: "#243c33"

            Row {
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [10, 19, 27, 17, 10]

                    Rectangle {
                        required property int modelData

                        width: 3
                        height: modelData
                        y: (27 - height) / 2
                        radius: 1.5
                        color: Style.accent
                    }

                }

            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            SettingsLabel {
                text: "Lyric Island"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    color: root.hasPlayer ? Style.accent : "#bfa47a"
                }

                SettingsLabel {
                    objectName: "connectionStatus"
                    font.pixelSize: 11
                    color: Style.secondary
                    Layout.fillWidth: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    text: root.demo ? root.tr("Animation preview", "动画演示") : root.hasPlayer ? root.backend.snapshot.player.displayName + root.tr(" connected", " 已连接") : root.backend.ready ? root.tr("Waiting for a player", "等待播放器") : I18n.status(root.preferences.language, root.backend.status)
                }

            }

        }

        SettingsComboBox {
            objectName: "languageSelector"
            Layout.preferredWidth: 130
            Layout.minimumWidth: 130
            Layout.maximumWidth: 130
            model: [root.tr("System", "跟随系统"), "English", "简体中文"]
            currentIndex: ["auto", "en", "zh_CN"].indexOf(root.preferences.language)
            Accessible.name: root.tr("Language", "界面语言")
            onActivated: root.preferences.saveLanguage(["auto", "en", "zh_CN"][currentIndex])
        }

        SettingsButton {
            objectName: "closeSettings"
            implicitWidth: 32
            implicitHeight: 32
            Layout.minimumWidth: 32
            Layout.maximumWidth: 32
            leftPadding: 0
            rightPadding: 0
            text: "×"
            font.pixelSize: 22
            quiet: true
            Accessible.name: root.tr("Close settings", "关闭设置")
            onClicked: root.closeRequested()
        }

        SettingsButton {
            objectName: "exitIsland"
            text: root.tr("Quit", "退出")
            Accessible.name: root.tr("Quit Lyric Island", "退出灵动岛")
            quiet: true
            onClicked: root.exitRequested()
        }

    }

    C.ScrollView {
        id: scroll

        objectName: "settingsScroll"
        anchors.top: header.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.bottom: feedback.visible ? feedback.top : footer.top
        anchors.bottomMargin: 12
        contentWidth: availableWidth
        contentHeight: sections.implicitHeight
        clip: true
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff

        ColumnLayout {
            id: sections

            width: scroll.availableWidth
            spacing: 12

            SettingsCard {
                visible: root.demo || !root.backend.ready || root.backend.bootstrap.updatePending || !!root.backend.bootstrap.error
                Layout.fillWidth: true
                title: root.demo ? root.tr("Connect your music", "连接你的音乐") : root.tr("Playback component", "播放组件")

                SettingsLabel {
                    Layout.fillWidth: true
                    color: Style.secondary
                    font.pixelSize: 12
                    objectName: "runtimeStatus"
                    text: root.demo ? root.tr("Switch to your player to use real lyrics.", "切换到播放器，使用正在播放的真实歌曲。") : root.backend.bootstrap.error ? I18n.runtimeError(root.preferences.language, root.backend.bootstrap.error) : root.backend.bootstrap.downloadAvailable ? root.tr("Download required · ", "需要下载 · ") + Math.ceil(root.backend.bootstrap.sizeBytes / 1.04858e+06) + " MiB" : !root.backend.bootstrap.ready ? root.tr("No downloadable runtime is available for this build.", "此构建尚未提供可下载的运行组件。") : I18n.status(root.preferences.language, root.backend.status)
                }

                RowLayout {
                    SettingsButton {
                        visible: root.demo
                        primary: true
                        text: root.tr("Connect player", "连接播放器")
                        onClicked: root.useLive()
                    }

                    SettingsButton {
                        visible: !root.demo && !root.backend.ready
                        text: root.tr("Retry connection", "重新连接")
                        onClicked: root.backend.retry()
                    }

                    SettingsButton {
                        visible: !root.demo && (!root.backend.bootstrap.ready || root.backend.bootstrap.updatePending)
                        text: root.tr("Download and install", "下载并安装")
                        primary: true
                        enabled: root.backend.bootstrap.downloadAvailable && root.backend.bootstrap.status !== "downloading"
                        onClicked: root.backend.bootstrap.download()
                    }

                    SettingsButton {
                        visible: root.backend.bootstrap.status === "downloading"
                        text: root.tr("Cancel", "取消")
                        onClicked: root.backend.bootstrap.cancel()
                    }

                }

            }

            SettingsCard {
                Layout.fillWidth: true
                title: root.tr("Playback & appearance", "播放与显示")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        SettingsLabel {
                            text: root.tr("Music player", "音乐播放器")
                        }

                        SettingsLabel {
                            text: root.tr("Local connection. No sign-in needed.", "本机连接，无需额外登录")
                            color: Style.muted
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }

                    }

                    SettingsComboBox {
                        objectName: "playerSelector"
                        Layout.preferredWidth: Math.min(184, sections.width * 0.4)
                        model: root.players.map(root.playerName)
                        enabled: root.backend.ready
                        displayText: root.hasPlayer ? root.backend.snapshot.player.displayName : root.tr("Select player", "选择播放器")
                        Accessible.name: root.tr("Music player", "音乐播放器")
                        onActivated: root.backend.request("player.select", {
                            "applicationId": root.players[currentIndex]
                        }, false)
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: "#2c3638"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        SettingsLabel {
                            text: root.tr("Online cover art", "在线封面")
                        }

                        SettingsLabel {
                            text: root.tr("Load covers from the player's image source.", "从播放器提供的图片地址加载封面")
                            color: Style.muted
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }

                    }

                    SettingsSwitch {
                        objectName: "artworkSwitch"
                        checked: root.preferences.remoteArtwork
                        Accessible.name: root.tr("Online cover art", "在线封面")
                        onToggled: root.preferences.saveRemoteArtwork(checked)
                    }

                }

            }

            SettingsCard {
                Layout.fillWidth: true
                title: root.tr("Lyric sources", "歌词来源")

                SettingsLabel {
                    Layout.fillWidth: true
                    color: Style.secondary
                    font.pixelSize: 12
                    text: root.tr("When enabled, song title, artists, album and duration are sent to the selected service to find matching lyrics.", "开启后，歌名、艺人、专辑和时长将发送给所选服务，用于匹配歌词。")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.settings.sources || []

                        Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 68
                            radius: 10
                            color: Style.elevated

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 9

                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: 9
                                    color: Style.accentInk

                                    SettingsLabel {
                                        anchors.centerIn: parent
                                        text: modelData.name.charAt(0)
                                        color: Style.accent
                                        font.pixelSize: 16
                                        font.weight: Font.DemiBold
                                    }

                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    SettingsLabel {
                                        text: root.tr(modelData.name, modelData.chineseName)
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        Layout.fillWidth: true
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideRight
                                    }

                                    SettingsLabel {
                                        text: modelData.enabled ? root.tr("Enabled", "已开启") : root.tr("Off", "未开启")
                                        font.pixelSize: 10
                                        color: modelData.enabled ? Style.accent : Style.muted
                                    }

                                }

                                SettingsSwitch {
                                    objectName: modelData.id + "EnabledSwitch"
                                    checked: !!modelData.enabled
                                    enabled: root.backend.ready
                                    Accessible.name: root.tr(modelData.name, modelData.chineseName)
                                    onToggled: {
                                        var change = {
                                        };
                                        change[modelData.id] = checked;
                                        root.backend.request("settings.update", {
                                            "sources": change
                                        }, false);
                                    }
                                }

                            }

                        }

                    }

                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SettingsButton {
                        objectName: "importLyrics"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        primary: true
                        text: root.tr("Import local lyrics", "导入本地歌词")
                        enabled: root.canFindLyrics
                        onClicked: root.importRequested()
                    }

                    SettingsButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: root.tr("Search again", "重新匹配")
                        enabled: root.canFindLyrics && root.onlineEnabled
                        onClicked: root.backend.request("lyrics.refresh", {
                        }, true)
                    }

                }

                SettingsLabel {
                    visible: !root.onlineEnabled
                    Layout.fillWidth: true
                    text: root.tr("Turn on a source above to fetch lyrics, or import a local file.", "打开上方任一歌词来源即可开始查找，也可以导入本地歌词。")
                    font.pixelSize: 11
                    color: Style.muted
                }

            }

            SettingsCard {
                visible: root.onlineEnabled || root.candidates.length > 0
                Layout.fillWidth: true
                title: root.tr("Lyric matches", "匹配结果") + (root.candidates.length ? " · " + root.candidates.length : "")

                SettingsLabel {
                    objectName: "lyricMatchStatus"
                    Layout.fillWidth: true
                    color: Style.secondary
                    font.pixelSize: 12
                    text: root.lyricStatusText()
                }

                ListView {
                    visible: root.candidates.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 240)
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.candidates

                    delegate: C.Button {
                        required property var modelData

                        objectName: "lyricCandidate_" + modelData.candidateId
                        width: ListView.view.width
                        height: 58
                        leftPadding: 12
                        rightPadding: 12
                        hoverEnabled: true
                        text: modelData.title
                        onClicked: root.backend.request("lyrics.select", {
                            "resolutionId": root.candidateResolution,
                            "candidateId": modelData.candidateId
                        }, true)
                        C.ToolTip.visible: hovered
                        C.ToolTip.delay: 500
                        C.ToolTip.text: root.candidateHint(modelData)

                        background: Rectangle {
                            radius: 9
                            color: parent.hovered ? Style.hover : Style.elevated
                            border.color: parent.visualFocus ? Style.accent : "transparent"
                        }

                        contentItem: ColumnLayout {
                            spacing: 2

                            SettingsLabel {
                                text: modelData.title
                                font.weight: Font.Medium
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            SettingsLabel {
                                text: modelData.artists.join(" / ") + " · " + modelData.album + " · " + (modelData.provider === "qq" ? "QQ" : root.tr("NetEase", "网易"))
                                color: Style.muted
                                font.pixelSize: 11
                                Layout.fillWidth: true
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                        }

                    }

                }

            }

            DisplaySettings {
                Layout.fillWidth: true
                preferences: root.preferences
                monitorNames: root.monitorNames
                onCenterRequested: root.centerRequested()
                onResetPositionRequested: root.resetPositionRequested()
            }

            SettingsLabel {
                Layout.fillWidth: true
                visible: !!root.preferences.error
                text: root.tr("Could not save preferences. Check access to your configuration directory.", "无法保存设置，请检查配置目录的访问权限。")
                color: Style.secondary
            }

            SettingsCard {
                Layout.fillWidth: true
                title: root.tr("Data & privacy", "数据与隐私")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SettingsButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: root.tr("Clear cache", "清理缓存")
                        enabled: root.backend.ready
                        onClicked: root.backend.request("cache.clear", {
                        }, false)
                    }

                    SettingsButton {
                        objectName: "exportDiagnostics"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: root.tr("Export diagnostics", "导出诊断")
                        enabled: root.backend.ready
                        onClicked: root.exportRequested()
                    }

                }

                SettingsLabel {
                    Layout.fillWidth: true
                    font.pixelSize: 11
                    color: Style.muted
                    text: root.tr("Cleanup keeps imports and corrections. Diagnostics exclude titles, lyrics and accounts.", "清理缓存保留导入歌词与校正。诊断不包含歌名、歌词正文或账号。")
                }

            }

        }

        C.ScrollBar.vertical: C.ScrollBar {
            policy: C.ScrollBar.AsNeeded
            width: 4
            padding: 0

            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: Style.muted
                opacity: parent.active ? 0.8 : 0.3
            }

            background: Item {
            }

        }

    }

    SettingsLabel {
        id: feedback

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 28
        anchors.bottom: footer.top
        anchors.bottomMargin: 12
        visible: text.length > 0
        text: root.message
        font.pixelSize: 11
        color: "#dcc59d"
        maximumLineCount: 3
        elide: Text.ElideRight
    }

    Item {
        id: footer

        objectName: "settingsFooter"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 52

        Rectangle {
            x: 28
            width: parent.width - 56
            height: 1
            color: Style.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 18
            spacing: 12

            SettingsLabel {
                text: "Lyric Island  ·  " + Release.version
                font.pixelSize: 10
                color: Style.muted
                Layout.fillWidth: true
            }

            SettingsButton {
                objectName: "purgeData"
                text: root.tr("Delete local data…", "删除本地数据…")
                font.pixelSize: 11
                quiet: true
                destructive: true
                onClicked: root.purgeRequested()
            }

        }

    }

}
