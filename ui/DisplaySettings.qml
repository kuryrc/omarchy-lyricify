// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import "../core/I18n.js" as I18n
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Layouts
import "SettingsStyle.js" as Style

SettingsCard {
    id: root

    required property var preferences
    property var monitorNames: []
    readonly property var monitors: [""].concat(monitorNames).concat(preferences.display.monitor && monitorNames.indexOf(preferences.display.monitor) < 0 ? [preferences.display.monitor] : [])

    signal centerRequested()
    signal resetPositionRequested()

    function tr(en, zh) {
        return I18n.text(preferences.language, en, zh);
    }

    title: tr("Island display", "岛体显示")

    RowLayout {
        Layout.fillWidth: true

        SettingsLabel {
            Layout.fillWidth: true
            text: root.tr("Width", "宽度")
        }

        SettingsLabel {
            text: Math.round(root.preferences.display.width) + " px"
            color: Style.secondary
        }

    }

    C.Slider {
        objectName: "islandWidth"
        Layout.fillWidth: true
        from: 300
        to: 900
        stepSize: 10
        value: root.preferences.display.width
        Accessible.name: root.tr("Island width", "岛体宽度")
        onMoved: root.preferences.saveDisplay("width", Math.round(value))
    }

    RowLayout {
        Layout.fillWidth: true

        SettingsLabel {
            Layout.fillWidth: true
            text: root.tr("Monitor", "显示器")
        }

        SettingsComboBox {
            objectName: "islandMonitor"
            Layout.preferredWidth: 220
            model: root.monitors.map(function(name) {
                return name || root.tr("First available", "首个可用显示器");
            })
            currentIndex: root.monitors.indexOf(root.preferences.display.monitor)
            Accessible.name: root.tr("Monitor", "显示器")
            onActivated: root.preferences.saveDisplay("monitor", root.monitors[currentIndex])
        }

    }

    RowLayout {
        Layout.fillWidth: true

        SettingsLabel {
            Layout.fillWidth: true
            text: root.tr("Hide during fullscreen", "全屏时隐藏")
        }

        SettingsSwitch {
            objectName: "islandFullscreen"
            checked: root.preferences.display.hideFullscreen
            Accessible.name: root.tr("Hide during fullscreen", "全屏时隐藏")
            onToggled: root.preferences.saveDisplay("hideFullscreen", checked)
        }

    }

    RowLayout {
        Layout.fillWidth: true

        SettingsLabel {
            Layout.fillWidth: true
            text: root.tr("Collapse after pausing", "暂停后收起")
        }

        SettingsComboBox {
            property var delays: [1000, 3000, 5000, 10000, 30000, 60000]

            objectName: "islandPauseDelay"
            Layout.preferredWidth: 220
            model: delays.map(function(ms) {
                return ms / 1000 + root.tr(" seconds", " 秒");
            })
            currentIndex: delays.indexOf(root.preferences.display.pauseCollapseMs)
            displayText: root.preferences.display.pauseCollapseMs / 1000 + root.tr(" seconds", " 秒")
            Accessible.name: root.tr("Collapse after pausing", "暂停后收起")
            onActivated: root.preferences.saveDisplay("pauseCollapseMs", delays[currentIndex])
        }

    }

    SettingsLabel {
        Layout.fillWidth: true
        font.pixelSize: 12
        color: Style.secondary
        text: root.tr("Drag the island horizontally to move it. It snaps to the screen center.", "横向拖拽岛体可调整位置，靠近屏幕中心时自动吸附。")
    }

    RowLayout {
        SettingsButton {
            objectName: "centerIsland"
            text: root.tr("Center", "居中")
            onClicked: root.centerRequested()
        }

        SettingsButton {
            text: root.tr("Default position", "默认位置")
            onClicked: root.resetPositionRequested()
        }

    }

}
