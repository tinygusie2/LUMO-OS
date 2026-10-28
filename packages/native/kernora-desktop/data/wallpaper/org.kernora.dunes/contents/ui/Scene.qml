/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
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

    function smooth(points: var): string {
        let path = "";
        for (let i = 0; i + 1 < points.length; ++i) {
            const a = points[Math.max(0, i - 1)];
            const b = points[i];
            const c = points[i + 1];
            const d = points[Math.min(points.length - 1, i + 2)];
            const c1x = Math.min(c[0], b[0] + (c[0] - a[0]) / 6);
            const c2x = Math.max(b[0], c[0] - (d[0] - b[0]) / 6);
            path += " C " + c1x.toFixed(1) + " " + (b[1] + (c[1] - a[1]) / 6).toFixed(1)
                + " " + c2x.toFixed(1) + " " + (c[1] - (d[1] - b[1]) / 6).toFixed(1)
                + " " + c[0].toFixed(1) + " " + c[1].toFixed(1);
        }
        return path;
    }

    function dune(points: var): string {
        return "M -10 1010 L " + points[0][0] + " " + points[0][1] + scene.smooth(points) + " L 1010 1010 Z";
    }

    function shade(points: var, crest: int, foot: var): string {
        const ridge = points.slice(crest);
        return "M " + ridge[0][0] + " " + ridge[0][1] + scene.smooth(ridge)
            + " L 1010 1010 L " + foot[0] + " " + foot[1] + " Z";
    }

    readonly property var dunes: [
        { tone: 84, shadow: 78, points: [[-10, 610], [180, 560], [380, 585], [600, 520], [820, 560], [1010, 540]], crest: 3, foot: [700, 1010] },
        { tone: 74, shadow: 66, points: [[-10, 700], [220, 640], [420, 690], [640, 650], [860, 700], [1010, 670]], crest: 1, foot: [380, 1010] },
        { tone: 62, shadow: 54, points: [[-10, 760], [260, 800], [500, 730], [760, 790], [1010, 750]], crest: 2, foot: [800, 1010] },
        { tone: 48, shadow: 40, points: [[-10, 880], [200, 840], [460, 900], [720, 850], [1010, 900]], crest: 1, foot: [360, 1010] }
    ]

    opacity: intro

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: scene.c("sky", 82) }
            GradientStop { position: 0.55; color: scene.c("sky", 94) }
            GradientStop { position: 1.0; color: scene.c("sky", 96) }
        }
    }

    Rectangle {
        readonly property real size: scene.unit * 0.34
        x: scene.width * (scene.portrait ? 0.62 : 0.3) - size / 2
        y: scene.height * (scene.portrait ? 0.36 : 0.32) - size / 2
        width: size
        height: size
        radius: size / 2
        color: scene.c("sun", 78)
    }

    Repeater {
        model: scene.dunes

        delegate: Shape {
            id: dune

            required property var modelData

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
                fillColor: scene.c("sand", dune.modelData.tone)
                PathSvg {
                    path: scene.dune(dune.modelData.points)
                }
            }
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: scene.c("sand", dune.modelData.shadow)
                PathSvg {
                    path: scene.shade(dune.modelData.points, dune.modelData.crest, dune.modelData.foot)
                }
            }
        }
    }
}
