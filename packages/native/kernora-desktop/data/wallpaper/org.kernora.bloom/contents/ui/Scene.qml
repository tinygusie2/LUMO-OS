/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "materialshapes.js" as MaterialShapes
import org.kernora.m3

Item {
    id: scene

    readonly property string colour: M3.colour
    Loader {
        id: paletteSource
        source: Qt.resolvedUrl("palettes/" + scene.colour + ".qml")
    }
    readonly property var colours: paletteSource.item ? paletteSource.item.palette : null

    function c(family: string, tone: real): color {
        const p = scene.colours;
        if (!p) {
            return "transparent";
        }
        let best = p.tones[0];
        for (const t of p.tones) {
            if (Math.abs(t - tone) < Math.abs(best - tone)) {
                best = t;
            }
        }
        return p.families[family][String(best)];
    }

    property real phase: 0
    property real intro: 1

    readonly property real unit: Math.min(width, height)
    readonly property bool portrait: height > width

    component Figure: Item {
        id: figure

        property string shape: "circle"
        property color colour: "white"
        property real size: 100
        property real cx: 0
        property real cy: 0
        property real angle: 0

        x: cx - size / 2
        y: cy - size / 2
        width: size
        height: size
        rotation: angle

        Shape {
            width: MaterialShapes.units
            height: MaterialShapes.units
            scale: figure.size / MaterialShapes.units
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: figure.colour
                PathSvg {
                    path: MaterialShapes.shapes[figure.shape].path
                }
            }
        }
    }

    readonly property real s: scene.unit

    opacity: intro

    Rectangle {
        anchors.fill: parent
        color: scene.c("base", 92)
    }

    Figure {
        shape: "flower"
        colour: scene.c("petal", 72)
        size: scene.s * 1.15
        cx: scene.width * (scene.portrait ? 0.86 : 0.84)
        cy: scene.height * (scene.portrait ? 0.3 : 0.4)
        angle: 12
    }
    Figure {
        shape: "circle"
        colour: scene.c("petal", 86)
        size: scene.s * 0.38
        cx: scene.width * (scene.portrait ? 0.86 : 0.84)
        cy: scene.height * (scene.portrait ? 0.3 : 0.4)
    }
    Figure {
        shape: "cookie12"
        colour: scene.c("pink", 82)
        size: scene.s * 0.78
        cx: scene.width * (scene.portrait ? 0.12 : 0.14)
        cy: scene.height * (scene.portrait ? 0.92 : 0.98)
        angle: -8
    }
    Figure {
        shape: "clover4"
        colour: scene.c("leaf", 78)
        size: scene.s * 0.3
        cx: scene.width * (scene.portrait ? 0.2 : 0.16)
        cy: scene.height * (scene.portrait ? 0.14 : 0.18)
        angle: 20
    }
    Figure {
        shape: "sunny"
        colour: scene.c("amber", 86)
        size: scene.s * 0.24
        cx: scene.width * (scene.portrait ? 0.56 : 0.48)
        cy: scene.height * (scene.portrait ? 0.62 : 0.7)
        angle: 8
    }
    Figure {
        shape: "pill"
        colour: scene.c("petal", 60)
        size: scene.s * 0.2
        cx: scene.width * (scene.portrait ? 0.38 : 0.36)
        cy: scene.height * (scene.portrait ? 0.4 : 0.36)
        angle: -42
    }
    Figure {
        shape: "circle"
        colour: scene.c("soft", 84)
        size: scene.s * 0.09
        cx: scene.width * (scene.portrait ? 0.66 : 0.6)
        cy: scene.height * (scene.portrait ? 0.82 : 0.9)
    }
    Figure {
        shape: "gem"
        colour: scene.c("leaf", 66)
        size: scene.s * 0.11
        cx: scene.width * (scene.portrait ? 0.3 : 0.28)
        cy: scene.height * (scene.portrait ? 0.7 : 0.62)
        angle: 15
    }
}
