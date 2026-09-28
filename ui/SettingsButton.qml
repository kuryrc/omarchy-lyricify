// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Controls.Basic as C
import "SettingsStyle.js" as Style

C.Button {
    id: control

    property bool primary: false
    property bool quiet: false
    property bool destructive: false

    implicitHeight: 36
    implicitWidth: Math.max(36, implicitContentWidth + leftPadding + rightPadding)
    leftPadding: 14
    rightPadding: 14
    topPadding: 8
    bottomPadding: 8
    hoverEnabled: true
    font.family: Style.fontFamily
    font.pixelSize: 12
    font.weight: Font.Medium
    opacity: enabled ? 1 : 0.4

    contentItem: SettingsLabel {
        text: control.text
        font: control.font
        color: control.destructive ? Style.danger : control.primary ? Style.accentInk : Style.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 9
        color: control.down ? (control.primary ? "#75bb98" : "#354345") : control.primary ? (control.hovered ? "#a6e5c5" : Style.accent) : control.hovered ? Style.hover : control.quiet ? "transparent" : Style.elevated
        border.color: control.visualFocus ? Style.accent : control.primary || control.quiet ? "transparent" : Style.border
        border.width: control.visualFocus ? 2 : 1

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

    }

}
