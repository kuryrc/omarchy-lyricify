// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property color fill: "#080909"
    property real shoulder: 15
    property real corner: Math.min(30, height / 2)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillColor: root.fill
        startX: 0
        startY: 0

        PathLine {
            x: root.width
            y: 0
        }

        PathQuad {
            x: root.width - root.shoulder
            y: root.shoulder
            controlX: root.width - root.shoulder
            controlY: 0
        }

        PathLine {
            x: root.width - root.shoulder
            y: root.height - root.corner
        }

        PathQuad {
            x: root.width - root.shoulder - root.corner
            y: root.height
            controlX: root.width - root.shoulder
            controlY: root.height
        }

        PathLine {
            x: root.shoulder + root.corner
            y: root.height
        }

        PathQuad {
            x: root.shoulder
            y: root.height - root.corner
            controlX: root.shoulder
            controlY: root.height
        }

        PathLine {
            x: root.shoulder
            y: root.shoulder
        }

        PathQuad {
            x: 0
            y: 0
            controlX: root.shoulder
            controlY: 0
        }

    }

}
