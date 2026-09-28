// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Controls.Basic as C
import "SettingsStyle.js" as Style

C.Switch {
    id: control

    implicitWidth: 46
    implicitHeight: 32
    padding: 2
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4

    contentItem: Item {
    }

    background: Rectangle {
        color: "transparent"
        radius: 16
        border.color: control.visualFocus ? Style.accent : "transparent"
    }

    indicator: Rectangle {
        x: 2
        y: (control.height - height) / 2
        width: 42
        height: 24
        radius: 12
        color: control.checked ? Style.accent : control.hovered ? "#4c5e58" : "#3b4a46"

        Rectangle {
            x: control.checked ? parent.width - width - 3 : 3
            y: 3
            width: 18
            height: 18
            radius: 9
            color: control.checked ? Style.accentInk : "#d3ddd8"

            Behavior on x {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }

            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 140
            }

        }

    }

}
