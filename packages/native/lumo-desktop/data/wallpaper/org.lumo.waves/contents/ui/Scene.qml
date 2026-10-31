/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
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
    readonly property real loopSeconds: 60
    readonly property int frameInterval: 40

    readonly property real tau: 2 * Math.PI
    readonly property real unit: Math.min(width, height)
    readonly property bool portrait: height > width
    readonly property real horizon: height * (portrait ? 0.46 : 0.5)

    function wave(cycles: int, offset: real): real {
        return Math.sin(scene.tau * (scene.phase * cycles + offset));
    }

    function crest(period: real, amplitude: real, length: real, depth: real): string {
        if (!(period > 1) || !(length > 0)) {
            return "";
        }
        const half = period / 2;
        let x = half;
        let path = "M 0 " + amplitude + " Q " + (period / 4) + " 0 " + x + " " + amplitude;
        while (x < length + period) {
            x += half;
            path += " T " + x + " " + amplitude;
        }
        return path + " L " + x + " " + depth + " L 0 " + depth + " Z";
    }

    readonly property var layers: [
        { tone: 80, crests: 9, amplitude: 0.006, depth: 0.0, cycles: 2, bob: 1, offset: 0.1 },
        { tone: 70, crests: 7, amplitude: 0.009, depth: 0.08, cycles: -3, bob: 2, offset: 0.4 },
        { tone: 58, crests: 5, amplitude: 0.013, depth: 0.19, cycles: 4, bob: 1, offset: 0.7 },
        { tone: 46, crests: 4, amplitude: 0.018, depth: 0.32, cycles: -5, bob: 2, offset: 0.25 },
        { tone: 34, crests: 3, amplitude: 0.024, depth: 0.48, cycles: 6, bob: 1, offset: 0.55 }
    ]

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: scene.c("sky", 75) }
            GradientStop { position: 0.3; color: scene.c("sky", 85) }
            GradientStop { position: scene.horizon / Math.max(1, scene.height); color: scene.c("sky", 92) }
            GradientStop { position: 1.0; color: scene.c("sea", 40) }
        }
    }

    Item {
        id: sun

        readonly property real size: scene.unit * 0.3
        x: scene.width * (scene.portrait ? 0.62 : 0.7) - size / 2
        y: scene.horizon - size * 0.62 + (1 - scene.intro) * size * 0.3
        width: size
        height: size

        Shape {
            id: halo
            anchors.centerIn: parent
            width: sun.size * 2.6
            height: width
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: halo.width / 2
                    centerY: halo.height / 2
                    centerRadius: halo.width / 2
                    focalX: centerX
                    focalY: centerY
                    GradientStop { position: 0.0; color: M3.withAlpha(scene.c("sun", 96), 0.55) }
                    GradientStop { position: 0.5; color: M3.withAlpha(scene.c("sun", 90), 0.14) }
                    GradientStop { position: 1.0; color: M3.withAlpha(scene.c("sun", 90), 0) }
                }
                PathAngleArc {
                    centerX: halo.width / 2
                    centerY: halo.height / 2
                    radiusX: halo.width / 2
                    radiusY: halo.height / 2
                    sweepAngle: 360
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: scene.c("sun", 94)
        }
    }

    Repeater {
        model: scene.layers

        delegate: Item {
            id: layer

            required property var modelData
            required property int index

            readonly property real period: Math.ceil(scene.width / modelData.crests)
            readonly property real amplitude: modelData.amplitude * scene.unit * 2
            readonly property real surface: scene.horizon + modelData.depth * (scene.height - scene.horizon) - amplitude
            readonly property real drift: ((scene.phase * Math.abs(modelData.cycles)) % 1) * period

            z: index
            x: modelData.cycles > 0 ? -drift : drift - period
            y: surface + amplitude * 0.35 * scene.wave(modelData.bob, modelData.offset) + (1 - scene.intro) * scene.unit * 0.04 * (index + 1)
            width: scene.width + period
            height: scene.height - surface + amplitude

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: -1
                    strokeColor: "transparent"
                    fillColor: scene.c("sea", layer.modelData.tone)
                    PathSvg {
                        path: scene.crest(layer.period, layer.amplitude, scene.width, layer.height)
                    }
                }
            }
        }
    }

    Repeater {
        model: 7

        delegate: Rectangle {
            id: glint

            required property int index

            z: 1.5
            readonly property real shimmer: 0.5 + 0.5 * scene.wave(3 + index % 3, index * 0.37)
            x: sun.x + sun.width / 2 - width / 2 + scene.unit * 0.012 * scene.wave(2, index * 0.21)
            y: scene.horizon + scene.unit * (0.02 + index * 0.022)
            width: sun.size * (0.9 - index * 0.09) * (0.75 + 0.25 * shimmer)
            height: Math.max(2, scene.unit * 0.006)
            radius: height / 2
            color: scene.c("sun", 96)
            opacity: (0.25 + 0.45 * shimmer) * (1 - index / 9) * scene.intro
        }
    }
}
