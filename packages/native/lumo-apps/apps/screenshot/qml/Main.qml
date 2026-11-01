/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.lumo.m3
import org.lumo.ui
import org.lumo.system
import org.kde.notification
import org.kde.layershell 1.0 as LayerShell

AppWindow {
    id: app

    width: 760
    height: 560
    minimumWidth: 480
    minimumHeight: 380
    color: M3.surfaceContainer
    visible: false
    title: i18n("Screenshot")

    property url saved
    property url original
    property int originalWidth: 0
    property int originalHeight: 0
    property var current: null
    property int pending: 0
    property int captured: 0
    property string firstError: ""
    property bool capturing: false
    property bool reopen: false
    readonly property bool showOnActivate: false
    property var temporaries: []

    property string tool: "pen"
    property color penColor: "#202124"
    property color markerColor: "#ffeb3b"
    property var strokes: []
    property var redoStack: []

    readonly property string mode: modeEntry.value === "freeform" ? "freeform" : "rectangle"
    readonly property var penColors: ["#202124", "#e53935", "#1e88e5", "#43a047", "#ffffff"]
    readonly property var markerColors: ["#ffeb3b", "#76ff03", "#40c4ff", "#ff4081", "#ffab40"]

    ConfigEntry {
        id: modeEntry
        file: "lumo-screenshotrc"
        group: "General"
        key: "mode"
        defaultValue: "rectangle"
        notify: false
    }

    function setMode(value: string): void {
        modeEntry.value = value;
    }

    function keep(url: url): void {
        if (String(url).length > 0) {
            temporaries = temporaries.concat([url]);
        }
    }

    function tidy(): void {
        const kept = [];
        for (let i = 0; i < temporaries.length; ++i) {
            if (String(temporaries[i]) === String(original)) {
                kept.push(temporaries[i]);
            } else {
                Screenshot.discard(temporaries[i]);
            }
        }
        temporaries = kept;
    }

    function idle(): void {
        closeOverlays();
        app.hide();
        tidy();
    }

    function start(): void {
        capturing = true;
        reopen = app.visible;
        snipToast.close();
        if (app.visible) {
            startTimer.restart();
        } else {
            captureScreens();
        }
    }
    Timer {
        id: startTimer
        interval: 250
        onTriggered: {
            if (app.visible) {
                app.hide();
                restart();
                return;
            }
            app.captureScreens();
        }
    }

    function captureScreens(): void {
        if (overlays.count === 0) {
            fail("");
            return;
        }
        pending = overlays.count;
        captured = 0;
        firstError = "";
        for (let i = 0; i < overlays.count; ++i) {
            const overlay = overlays.objectAt(i);
            overlay.frozen = "";
            Screenshot.captureScreen(overlay.screen.name, false, (ok, url, width, height) => {
                if (ok) {
                    app.keep(url);
                    overlay.frozen = url;
                    overlay.frozenWidth = width;
                    overlay.frozenHeight = height;
                    app.captured += 1;
                } else if (app.firstError.length === 0) {
                    app.firstError = url;
                }
                app.pending -= 1;
                if (app.pending === 0) {
                    app.openOverlays();
                }
            });
        }
    }

    function openOverlays(): void {
        if (captured === 0) {
            fail(firstError);
            return;
        }
        current = null;
        for (let i = 0; i < overlays.count; ++i) {
            const overlay = overlays.objectAt(i);
            if (String(overlay.frozen).length > 0) {
                overlay.open();
            }
        }
    }

    function closeOverlays(): void {
        for (let i = 0; i < overlays.count; ++i) {
            overlays.objectAt(i).hide();
        }
    }

    function cancel(): void {
        closeOverlays();
        capturing = false;
        if (reopen) {
            app.show();
            app.raise();
        } else {
            tidy();
        }
    }

    function fail(message: string): void {
        capturing = false;
        saved = "";
        failure.text = message || i18n("The screen could not be captured.");
        app.show();
        app.raise();
    }

    function finish(url: url): void {
        closeOverlays();
        capturing = false;
        saved = Screenshot.save(url);
        if (String(saved).length === 0) {
            fail(i18n("The screenshot could not be saved."));
            return;
        }
        keep(url);
        original = url;
        tidy();
        strokes = [];
        redoStack = [];
        Screenshot.copyToClipboard(saved);
        failure.text = "";
        if (reopen) {
            openEditor();
            return;
        }
        snipToast.urls = [app.saved];
        snipToast.sendEvent();
    }

    function snipFullScreen(): void {
        const overlay = current;
        if (overlay) {
            finish(overlay.frozen);
        }
    }

    function snipWindow(): void {
        closeOverlays();
        Screenshot.captureInteractive(0, false, (ok, url) => ok ? app.finish(url) : app.cancel());
    }

    function snipRectangle(overlay: var, x: real, y: real, width: real, height: real): void {
        const scale = overlay.frozenWidth / overlay.width;
        finish(Screenshot.crop(overlay.frozen, Math.round(x * scale), Math.round(y * scale),
                               Math.round(width * scale), Math.round(height * scale)));
    }

    function snipFreeform(overlay: var, points: var): void {
        const scale = overlay.frozenWidth / overlay.width;
        const scaled = [];
        for (let i = 0; i < points.length; ++i) {
            scaled.push(points[i].x * scale, points[i].y * scale);
        }
        finish(Screenshot.cropShape(overlay.frozen, scaled));
    }

    function openEditor(): void {
        if (String(saved).length === 0) {
            return;
        }
        app.show();
        app.raise();
        app.requestActivate();
        snipToast.close();
    }

    function commit(): void {
        if (String(saved).length === 0 || String(original).length === 0) {
            return;
        }
        if (Screenshot.annotate(original, saved, strokes)) {
            Screenshot.copyToClipboard(saved);
        }
        ink.requestPaint();
    }

    function undo(): void {
        if (strokes.length === 0) {
            return;
        }
        const list = strokes.slice();
        redoStack = redoStack.concat([list.pop()]);
        strokes = list;
        commit();
    }

    function redo(): void {
        if (redoStack.length === 0) {
            return;
        }
        const list = redoStack.slice();
        strokes = strokes.concat([list.pop()]);
        redoStack = list;
        commit();
    }

    function clearInk(): void {
        if (strokes.length === 0) {
            return;
        }
        strokes = [];
        redoStack = [];
        commit();
    }

    function handleArguments(args: var): void {
        if (args.indexOf("resident") < 0) {
            start();
        }
    }
    Component.onCompleted: {
        if (startArguments.indexOf("resident") < 0) {
            start();
        }
    }

    onClosing: close => {
        close.accepted = false;
        app.hide();
    }

    Instantiator {
        id: overlays
        model: Qt.application.screens

        delegate: Window {
            id: overlay

            required property var modelData
            property url frozen
            property int frozenWidth: 0
            property int frozenHeight: 0
            readonly property bool current: app.current === overlay

            function open(): void {
                picker.reset();
                show();
                raise();
                if (app.current === null) {
                    app.current = overlay;
                    requestActivate();
                }
            }

            screen: modelData
            transientParent: null
            width: modelData.width
            height: modelData.height
            LayerShell.Window.scope: "lumo-screenshot"
            LayerShell.Window.layer: LayerShell.Window.LayerOverlay
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
            LayerShell.Window.screenConfiguration: LayerShell.Window.ScreenFromQWindow
            onActiveChanged: {
                if (active) {
                    app.current = overlay;
                }
            }

            flags: Qt.FramelessWindowHint
            color: "black"
            title: i18n("Take a screenshot")

            onClosing: close => {
                close.accepted = false;
                app.cancel();
            }

            Image {
                anchors.fill: parent
                source: overlay.frozen
                fillMode: Image.Stretch
                cache: false
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        app.current = overlay;
                    }
                }
            }

            readonly property bool showRegion: app.mode === "rectangle" && picker.active
            Rectangle { color: "#80000000"; visible: !overlay.showRegion; anchors.fill: parent }
            Rectangle { visible: overlay.showRegion; color: "#80000000"; x: 0; y: 0; width: parent.width; height: picker.boxTop }
            Rectangle { visible: overlay.showRegion; color: "#80000000"; x: 0; y: picker.boxTop + picker.boxHeight; width: parent.width; height: parent.height - y }
            Rectangle { visible: overlay.showRegion; color: "#80000000"; x: 0; y: picker.boxTop; width: picker.boxLeft; height: picker.boxHeight }
            Rectangle { visible: overlay.showRegion; color: "#80000000"; x: picker.boxLeft + picker.boxWidth; y: picker.boxTop; width: parent.width - x; height: picker.boxHeight }
            Rectangle {
                visible: overlay.showRegion
                x: picker.boxLeft
                y: picker.boxTop
                width: picker.boxWidth
                height: picker.boxHeight
                color: "transparent"
                border.width: 1
                border.color: "white"
            }

            Shape {
                anchors.fill: parent
                visible: app.mode === "freeform" && picker.active
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "white"
                    strokeWidth: 2
                    fillColor: "#33ffffff"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathPolyline { path: picker.points }
                }
            }

            MouseArea {
                id: picker

                property bool active: false
                property real startX: 0
                property real startY: 0
                property real endX: 0
                property real endY: 0
                property var points: []
                readonly property real boxLeft: Math.min(startX, endX)
                readonly property real boxTop: Math.min(startY, endY)
                readonly property real boxWidth: Math.abs(endX - startX)
                readonly property real boxHeight: Math.abs(endY - startY)

                function reset(): void {
                    active = false;
                    points = [];
                    startX = startY = endX = endY = 0;
                }

                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                onPressed: mouse => {
                    app.current = overlay;
                    active = true;
                    startX = endX = mouse.x;
                    startY = endY = mouse.y;
                    points = [Qt.point(mouse.x, mouse.y)];
                }
                onPositionChanged: mouse => {
                    if (!active) {
                        return;
                    }
                    endX = Math.max(0, Math.min(overlay.width, mouse.x));
                    endY = Math.max(0, Math.min(overlay.height, mouse.y));
                    if (app.mode === "freeform") {
                        points = points.concat([Qt.point(endX, endY)]);
                    }
                }
                onReleased: {
                    if (!active) {
                        return;
                    }
                    if (app.mode === "freeform") {
                        if (points.length > 2 && boxWidth >= 4 && boxHeight >= 4) {
                            app.snipFreeform(overlay, points.concat([points[0]]));
                            return;
                        }
                    } else if (boxWidth >= 4 && boxHeight >= 4) {
                        app.snipRectangle(overlay, boxLeft, boxTop, boxWidth, boxHeight);
                        return;
                    }
                    reset();
                }
            }

            Rectangle {
                id: toolbar
                visible: overlay.current && !picker.active
                anchors.horizontalCenter: parent.horizontalCenter
                y: overlay.current ? 16 : -height
                Behavior on y { NumberAnimation { duration: M3.durationMedium2; easing.type: Easing.OutCubic } }
                width: tools.implicitWidth + 16
                height: 56
                radius: M3.classic ? M3.cornerCard : 28
                color: M3.surfaceContainerHigh

                RowLayout {
                    id: tools
                    anchors.centerIn: parent
                    spacing: 4

                    IconButton {
                        iconName: "lumo-select-region"
                        text: i18n("Rectangle")
                        checked: app.mode === "rectangle"
                        onClicked: app.setMode("rectangle")
                    }
                    IconButton {
                        iconName: "lumo-select-freeform"
                        text: i18n("Freeform")
                        checked: app.mode === "freeform"
                        onClicked: app.setMode("freeform")
                    }
                    IconButton {
                        iconName: "lumo-select-window"
                        text: i18n("Window")
                        onClicked: app.snipWindow()
                    }
                    IconButton {
                        iconName: "view-fullscreen"
                        text: i18n("Full screen")
                        onClicked: app.snipFullScreen()
                    }
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 24
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        color: M3.outlineVariant
                    }
                    IconButton {
                        iconName: "window-close"
                        text: i18n("Close (Esc)")
                        onClicked: app.cancel()
                    }
                }
            }

            Shortcut { sequences: ["Escape"]; onActivated: app.cancel() }
        }
    }

    Notification {
        id: snipToast


        componentName: "lumo-screenshot"
        eventId: "captured"
        title: i18n("Snip copied to clipboard")
        text: i18n("Select here to mark up and share.")
        iconName: "org.lumo.screenshot"
        autoDelete: false
        defaultAction: NotificationAction {
            label: i18n("Mark up")
            onActivated: app.openEditor()
        }
        actions: [
            NotificationAction {
                label: i18n("Mark up")
                onActivated: app.openEditor()
            }
        ]
    }

    Shortcut { sequences: [StandardKey.New]; onActivated: app.start() }
    Shortcut { sequences: [StandardKey.Undo]; onActivated: app.undo() }
    Shortcut { sequences: [StandardKey.Redo]; onActivated: app.redo() }
    Shortcut { sequences: [StandardKey.Copy]; onActivated: Screenshot.copyToClipboard(app.saved) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            QQC2.Button {
                text: i18n("New")
                icon.name: "list-add"
                highlighted: true
                onClicked: app.start()
            }
            Item { Layout.preferredWidth: 8 }
            IconButton {
                visible: String(app.saved).length > 0
                iconName: "lumo-pen"
                text: i18n("Pen")
                checked: app.tool === "pen"
                onClicked: app.tool = "pen"
            }
            IconButton {
                visible: String(app.saved).length > 0
                iconName: "lumo-highlighter"
                text: i18n("Highlighter")
                checked: app.tool === "marker"
                onClicked: app.tool = "marker"
            }
            Repeater {
                model: String(app.saved).length > 0 ? (app.tool === "pen" ? app.penColors : app.markerColors) : []
                delegate: QQC2.AbstractButton {
                    id: swatch
                    required property var modelData
                    readonly property bool chosen: Qt.colorEqual(modelData, app.tool === "pen" ? app.penColor : app.markerColor)
                    implicitWidth: 32
                    implicitHeight: 40
                    hoverEnabled: true
                    Accessible.name: i18n("Colour")
                    contentItem: Item {}
                    background: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: swatch.chosen ? 26 : 20
                            height: width
                            radius: width / 2
                            color: swatch.modelData
                            border.width: swatch.chosen ? 2 : 1
                            border.color: swatch.chosen ? M3.primary : M3.outline
                            Behavior on width { NumberAnimation { duration: M3.durationShort4 } }
                        }
                    }
                    onClicked: {
                        if (app.tool === "pen") {
                            app.penColor = modelData;
                        } else {
                            app.markerColor = modelData;
                        }
                    }
                }
            }
            Item { Layout.preferredWidth: 8 }
            IconButton {
                visible: String(app.saved).length > 0
                enabled: app.strokes.length > 0
                iconName: "edit-undo"
                text: i18n("Undo")
                onClicked: app.undo()
            }
            IconButton {
                visible: String(app.saved).length > 0
                enabled: app.redoStack.length > 0
                iconName: "edit-redo"
                text: i18n("Redo")
                onClicked: app.redo()
            }
            IconButton {
                visible: String(app.saved).length > 0
                enabled: app.strokes.length > 0
                iconName: "edit-clear-history"
                text: i18n("Clear ink")
                onClicked: app.clearInk()
            }
            Item { Layout.fillWidth: true }
            IconButton {
                visible: String(app.saved).length > 0
                iconName: "edit-copy"
                text: i18n("Copy")
                onClicked: Screenshot.copyToClipboard(app.saved)
            }
            IconButton {
                visible: String(app.saved).length > 0
                iconName: "system-file-manager"
                text: i18n("Show in Files")
                onClicked: Process.launchApplication("org.lumo.files.desktop", [app.saved])
            }
            IconButton {
                visible: String(app.saved).length > 0
                iconName: "user-trash"
                text: i18n("Delete")
                onClicked: {
                    Screenshot.discard(app.saved);
                    app.saved = "";
                    app.original = "";
                    app.idle();
                }
            }
        }

        RoundedClip {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: M3.classic ? M3.cornerImage : 24
            visible: String(app.saved).length > 0
            Rectangle { anchors.fill: parent; color: M3.surfaceContainerHighest }
            Image {
                id: preview
                anchors.fill: parent
                anchors.margins: 8
                source: app.original
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: true

                Canvas {
                    id: ink

                    property var live: null
                    readonly property real ratio: preview.sourceSize.width > 0 ? preview.paintedWidth / preview.sourceSize.width : 1

                    function drawStroke(context: var, stroke: var): void {
                        const points = stroke.points;
                        if (points.length < 2) {
                            return;
                        }
                        context.globalAlpha = stroke.highlighter ? 0.4 : 1;
                        context.strokeStyle = stroke.color;
                        context.lineWidth = stroke.width;
                        context.lineCap = stroke.highlighter ? "square" : "round";
                        context.lineJoin = "round";
                        context.beginPath();
                        context.moveTo(points[0], points[1]);
                        if (points.length < 4) {
                            context.lineTo(points[0] + 0.01, points[1]);
                        }
                        for (let i = 2; i + 1 < points.length; i += 2) {
                            context.lineTo(points[i], points[i + 1]);
                        }
                        context.stroke();
                    }

                    x: (preview.width - preview.paintedWidth) / 2
                    y: (preview.height - preview.paintedHeight) / 2
                    width: preview.paintedWidth
                    height: preview.paintedHeight
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const context = getContext("2d");
                        context.reset();
                        context.scale(ratio, ratio);
                        for (let i = 0; i < app.strokes.length; ++i) {
                            drawStroke(context, app.strokes[i]);
                        }
                        if (live) {
                            drawStroke(context, live);
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        onPressed: mouse => {
                            const marker = app.tool === "marker";
                            const unit = 1 / Math.max(0.01, ink.ratio);
                            ink.live = {
                                color: String(marker ? app.markerColor : app.penColor),
                                width: (marker ? 18 : 3) * unit,
                                highlighter: marker,
                                points: [mouse.x * unit, mouse.y * unit]
                            };
                            ink.requestPaint();
                        }
                        onPositionChanged: mouse => {
                            if (!ink.live) {
                                return;
                            }
                            const unit = 1 / Math.max(0.01, ink.ratio);
                            ink.live.points.push(mouse.x * unit, mouse.y * unit);
                            ink.requestPaint();
                        }
                        onReleased: {
                            if (!ink.live) {
                                return;
                            }
                            app.strokes = app.strokes.concat([ink.live]);
                            app.redoStack = [];
                            ink.live = null;
                            app.commit();
                        }
                    }
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: failure.text.length > 0
            icon: "dialog-error"
            title: i18n("No screenshot")
            text: failure.text
        }
        Text { id: failure; visible: false }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: String(app.saved).length > 0
            MText { role: "titleMedium"; text: i18n("Saved and copied") }
            MText {
                Layout.fillWidth: true
                role: "bodySmall"
                color: M3.surfaceVariantContent
                text: decodeURIComponent(String(app.saved).replace(/^file:\/\//, ""))
                elide: Text.ElideMiddle
            }
        }
    }
}
