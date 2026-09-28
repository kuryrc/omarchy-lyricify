// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import "SettingsStyle.js" as Style

Text {
    font.family: Style.fontFamily
    font.pixelSize: 13
    color: Style.text
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    lineHeight: 1.25
    renderType: Text.QtRendering
}
