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
    readonly property real loopSeconds: 120
    readonly property int frameInterval: 50

    readonly property real tau: 2 * Math.PI
    readonly property real unit: Math.min(width, height)
    readonly property real dot: Math.max(1, unit / 900)
    readonly property bool portrait: height > width

    function wave(cycles: int, offset: real): real {
        return Math.sin(scene.tau * (scene.phase * cycles + offset));
    }

    function sequence(seed: int): var {
        let state = seed >>> 0;
        return () => {
            state = (state + 0x6D2B79F5) >>> 0;
            let t = state;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }

    readonly property var stars: {
        const next = sequence(1310);
        const list = [];
        for (let i = 0; i < 110; ++i) {
            list.push({
                x: next(),
                y: Math.pow(next(), 1.3) * 0.7,
                size: 0.7 + next() * next() * 2.0,
                tone: 80 + Math.round(next() * 16),
                opacity: 0.35 + next() * 0.6
            });
        }
        return list;
    }

    readonly property var bands: [
        { base: 215, amplitude: 50, thickness: 170, frequency: 1.4, shift: 0.55, family: "glow", tone: 84, strength: 1.6, cycles: 3, offset: 0.35, sway: 0.05 },
        { base: 330, amplitude: 70, thickness: 240, frequency: 1.1, shift: 0.1, family: "mint", tone: 78, strength: 1, cycles: 2, offset: 0.0, sway: 0.04 },
        { base: 420, amplitude: 40, thickness: 150, frequency: 2.1, shift: 0.3, family: "mint", tone: 84, strength: 0.9, cycles: 1, offset: 0.7, sway: 0.03 }
    ]

    function band(spec: var, reach: real): string {
        const points = [];
        for (let i = 0; i <= 48; ++i) {
            const x = i * 1000 / 48;
            points.push([x, spec.base + spec.amplitude * Math.sin(scene.tau * (x / 1000 * spec.frequency + spec.shift))]);
        }
        const lift = spec.thickness * reach;
        let path = "M " + points[0][0] + " " + (points[0][1] - lift).toFixed(1);
        for (const p of points) {
            path += " L " + p[0].toFixed(1) + " " + (p[1] - lift).toFixed(1);
        }
        for (let i = points.length - 1; i >= 0; --i) {
            path += " L " + points[i][0].toFixed(1) + " " + points[i][1].toFixed(1);
        }
        return path + " Z";
    }

    readonly property var veils: [
        { reach: 1.0, alpha: 0.07, lift: -4 },
        { reach: 0.8, alpha: 0.08, lift: -2 },
        { reach: 0.6, alpha: 0.1, lift: 0 },
        { reach: 0.42, alpha: 0.12, lift: 2 },
        { reach: 0.26, alpha: 0.16, lift: 4 },
        { reach: 0.12, alpha: 0.22, lift: 6 },
        { reach: 0.03, alpha: 0.45, lift: 10 }
    ]

    function ridge(seed: int, base: real, rough: real, peaks: int): string {
        const next = sequence(seed);
        const points = [];
        let x = -40;
        while (x < 1080) {
            points.push([x, base - rough * (0.35 + next() * 0.65)]);
            x += 1000 / peaks * (0.6 + next() * 0.8);
            points.push([x, base + rough * next() * 0.25]);
            x += 1000 / peaks * (0.3 + next() * 0.4);
        }
        let path = "M -40 1000 L " + points[0][0] + " " + points[0][1].toFixed(1);
        for (let i = 0; i + 1 < points.length; ++i) {
            const a = points[Math.max(0, i - 1)];
            const b = points[i];
            const c = points[i + 1];
            const d = points[Math.min(points.length - 1, i + 2)];
            const c1x = Math.min(c[0], b[0] + (c[0] - a[0]) / 6);
            const c1y = b[1] + (c[1] - a[1]) / 6;
            const c2x = Math.max(b[0], c[0] - (d[0] - b[0]) / 6);
            const c2y = c[1] - (d[1] - b[1]) / 6;
            path += " C " + c1x.toFixed(1) + " " + c1y.toFixed(1) + " " + c2x.toFixed(1) + " " + c2y.toFixed(1) + " " + c[0].toFixed(1) + " " + c[1].toFixed(1);
        }
        return path + " L " + points[points.length - 1][0].toFixed(1) + " 1000 Z";
    }

    opacity: intro

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: scene.c("night", 4) }
            GradientStop { position: 0.5; color: scene.c("night", 10) }
            GradientStop { position: 0.8; color: scene.c("night", 16) }
            GradientStop { position: 1.0; color: scene.c("night", 20) }
        }
    }

    Repeater {
        model: scene.stars

        delegate: Rectangle {
            required property var modelData

            x: modelData.x * scene.width - width / 2
            y: modelData.y * scene.height - height / 2
            width: modelData.size * scene.dot
            height: width
            radius: width / 2
            color: scene.c("star", modelData.tone)
            opacity: modelData.opacity
        }
    }

    Repeater {
        model: scene.bands

        delegate: Item {
            id: band

            required property var modelData

            x: -scene.width * 0.1 + modelData.sway * scene.width * scene.wave(modelData.cycles, modelData.offset)
            y: 0
            width: scene.width * 1.2
            height: scene.height
            opacity: 0.55 + 0.3 * scene.wave(modelData.cycles + 1, modelData.offset + 0.5)
            transform: Scale {
                origin.y: band.modelData.base / 1000 * band.height
                yScale: 1 + 0.08 * scene.wave(band.modelData.cycles, band.modelData.offset + 0.25)
            }

            Repeater {
                model: scene.veils

                delegate: Shape {
                    id: veil

                    required property var modelData

                    width: 1000
                    height: 1000
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale {
                        xScale: band.width / 1000
                        yScale: band.height / 1000
                    }

                    ShapePath {
                        strokeWidth: -1
                        strokeColor: "transparent"
                        fillColor: M3.withAlpha(scene.c(band.modelData.family, band.modelData.tone + veil.modelData.lift), Math.min(0.8, veil.modelData.alpha * band.modelData.strength))
                        PathSvg {
                            path: scene.band(band.modelData, veil.modelData.reach)
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: scene.rays

        delegate: Rectangle {
            required property var modelData

            x: modelData.x * scene.width - width / 2 + scene.unit * 0.012 * scene.wave(modelData.cycles, modelData.offset)
            y: modelData.y * scene.height
            width: Math.max(1, modelData.width * scene.unit * 0.5)
            height: modelData.height * scene.height
            radius: width / 2
            opacity: 0.08 + 0.14 * (0.5 + 0.5 * scene.wave(modelData.cycles + 1, modelData.offset + 0.3))
            gradient: Gradient {
                GradientStop { position: 0.0; color: M3.withAlpha(scene.c(modelData.family, 88), 0) }
                GradientStop { position: 0.7; color: scene.c(modelData.family, 88) }
                GradientStop { position: 1.0; color: M3.withAlpha(scene.c(modelData.family, 88), 0) }
            }
        }
    }

    Shape {
        width: 1000
        height: 1000
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            xScale: scene.width / 1000
            yScale: scene.height / 1000
        }

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: scene.c("ridge", 10)
            PathSvg {
                path: scene.ridge(7, scene.portrait ? 760 : 740, 150, 5)
            }
        }
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: scene.c("ridge", 6)
            PathSvg {
                path: scene.ridge(19, scene.portrait ? 860 : 850, 110, 7)
            }
        }
    }
}
