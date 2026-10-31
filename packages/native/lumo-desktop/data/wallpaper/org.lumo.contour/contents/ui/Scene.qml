/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "materialshapes.js" as MaterialShapes
import org.lumo.m3

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

    readonly property real cx: scene.width * (scene.portrait ? 0.5 : 0.66)
    readonly property real cy: scene.height * (scene.portrait ? 0.4 : 0.44)
    readonly property real line: Math.max(1.5, scene.unit / 420)

    readonly property var rings: {
        const list = [];
        const count = 16;
        for (let i = 0; i < count; ++i) {
            const t = i / (count - 1);
            list.push({
                size: scene.unit * (0.2 + 2.1 * Math.pow(t, 1.25)),
                angle: i * 7,
                tone: 62 - 34 * t,
                alpha: 0.95 - 0.55 * t
            });
        }
        return list;
    }

    opacity: intro

    Rectangle {
        anchors.fill: parent
        color: scene.c("ink", 8)
    }

    Shape {
        id: glow
        readonly property real size: scene.unit * 1.3
        x: scene.cx - size / 2
        y: scene.cy - size / 2
        width: size
        height: size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glow.width / 2
                centerY: glow.height / 2
                centerRadius: glow.width / 2
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: M3.withAlpha(scene.c("glow", 40), 0.55) }
                GradientStop { position: 0.6; color: M3.withAlpha(scene.c("glow", 24), 0.18) }
                GradientStop { position: 1.0; color: M3.withAlpha(scene.c("glow", 24), 0) }
            }
            PathAngleArc {
                centerX: glow.width / 2
                centerY: glow.height / 2
                radiusX: glow.width / 2
                radiusY: glow.height / 2
                sweepAngle: 360
            }
        }
    }

    Repeater {
        model: scene.rings

        delegate: Item {
            id: ring

            required property var modelData
            required property int index

            x: scene.cx - modelData.size / 2
            y: scene.cy - modelData.size / 2
            width: modelData.size
            height: modelData.size
            rotation: modelData.angle

            Shape {
                width: MaterialShapes.units
                height: MaterialShapes.units
                scale: ring.modelData.size / MaterialShapes.units
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: scene.line * MaterialShapes.units / ring.modelData.size
                    strokeColor: M3.withAlpha(scene.c("line", ring.modelData.tone), ring.modelData.alpha)
                    fillColor: ring.index === 0 ? scene.c("glow", 66) : "transparent"
                    PathSvg {
                        path: MaterialShapes.shapes["cookie9"].path
                    }
                }
            }
        }
    }
}
