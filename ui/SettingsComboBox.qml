// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Controls.Basic as C
import "SettingsStyle.js" as Style

C.ComboBox {
    id: control

    implicitWidth: 180
    implicitHeight: 36
    leftPadding: 12
    rightPadding: 32
    font.family: Style.fontFamily
    font.pixelSize: 12
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4

    contentItem: SettingsLabel {
        text: control.displayText
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

    indicator: Item {
        x: control.width - 23
        y: (control.height - height) / 2
        width: 10
        height: 6

        Rectangle {
            x: 1
            y: 2
            width: 6
            height: 1.5
            radius: 0.75
            rotation: 45
            color: Style.secondary
        }

        Rectangle {
            x: 5
            y: 2
            width: 6
            height: 1.5
            radius: 0.75
            rotation: -45
            color: Style.secondary
        }

    }

    background: Rectangle {
        radius: 9
        color: control.hovered ? Style.hover : Style.elevated
        border.color: control.visualFocus || control.popup.visible ? Style.accent : Style.border

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

    }

    delegate: C.ItemDelegate {
        required property int index
        required property var modelData

        width: control.popup.availableWidth
        height: 36
        highlighted: control.highlightedIndex === index
        hoverEnabled: true

        contentItem: SettingsLabel {
            text: modelData
            font.pixelSize: 12
            color: control.currentIndex === index ? Style.accent : Style.text
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 6
            color: parent.highlighted || parent.hovered ? Style.hover : "transparent"
        }

    }

    popup: C.Popup {
        y: control.height + 6
        width: control.width
        padding: 6
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 228)

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }

        background: Rectangle {
            color: Style.elevated
            border.color: Style.border
            radius: 12
        }

    }

}
