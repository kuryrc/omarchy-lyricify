// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Layouts
import "SettingsStyle.js" as Style

Rectangle {
    id: root

    property string title: ""
    default property alias contents: content.data

    implicitHeight: layout.implicitHeight + 32
    radius: 14
    color: Style.surface
    border.color: "#293335"

    data: ColumnLayout {
        id: layout

        x: 20
        y: 16
        width: parent.width - 40
        spacing: 12

        SettingsLabel {
            text: root.title
            visible: text.length > 0
            font.pixelSize: 13
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }

        ColumnLayout {
            id: content

            Layout.fillWidth: true
            spacing: 10
        }

    }

}
