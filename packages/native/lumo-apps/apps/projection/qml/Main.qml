/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import org.lumo.m3
import org.lumo.system
import org.kde.layershell 1.0 as LayerShell

Window {
    id: app

    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: i18n("Project")

    readonly property bool showOnActivate: false
    readonly property bool available: displays.ready && displays.count > 1
    readonly property var choices: [
        { mode: "main", icon: "osd-shutd-screen", title: i18n("PC screen only"), text: i18n("Only the main screen shows a picture") },
        { mode: "duplicate", icon: "osd-duplicate", title: i18n("Duplicate"), text: i18n("Every screen shows the same") },
        { mode: "extend", icon: "osd-sbs-left", title: i18n("Extend"), text: i18n("The screens form one large desktop") },
        { mode: "second", icon: "osd-shutd-laptop", title: i18n("Second screen only"), text: i18n("The main screen turns off") }
    ]
    property int highlighted: 0
    property string chosen: ""

    LayerShell.Window.scope: "lumo-projection"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.screenConfiguration: LayerShell.Window.ScreenFromCompositor

    Displays {
        id: displays
    }

    function currentIndex(): int {
        const index = choices.findIndex(c => c.mode === displays.projection);
        return index >= 0 ? index : 2;
    }

    function open(): void {
        highlighted = currentIndex();
        panel.offset = 400;
        app.visible = true;
        app.requestActivate();
        slideIn.restart();
        content.forceActiveFocus();
    }

    function dismiss(): void {
        app.visible = false;
    }

    function choose(index: int): void {
        if (!available || index < 0 || index >= choices.length) {
            return;
        }
        highlighted = index;
        chosen = choices[index].mode;
        dismiss();
        applyTimer.restart();
    }

    Timer {
        id: applyTimer
        interval: 150
        onTriggered: {
            if (app.chosen.length > 0 && app.chosen !== displays.projection) {
                displays.setProjection(app.chosen);
            }
            app.chosen = "";
        }
    }

    function handleArguments(args: var): void {
        if (args.indexOf("resident") >= 0) {
            return;
        }
        if (app.visible) {
            highlighted = (highlighted + 1) % choices.length;
        } else {
            open();
        }
    }

    Component.onCompleted: {
        if (startArguments.indexOf("resident") < 0) {
            open();
        }
    }

    onActiveChanged: {
        if (!active && visible) {
            dismiss();
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: app.dismiss()
        Keys.onUpPressed: app.highlighted = (app.highlighted + app.choices.length - 1) % app.choices.length
        Keys.onDownPressed: app.highlighted = (app.highlighted + 1) % app.choices.length
        Keys.onTabPressed: app.highlighted = (app.highlighted + 1) % app.choices.length
        Keys.onBacktabPressed: app.highlighted = (app.highlighted + app.choices.length - 1) % app.choices.length
        Keys.onReturnPressed: app.choose(app.highlighted)
        Keys.onEnterPressed: app.choose(app.highlighted)
        Keys.onSpacePressed: app.choose(app.highlighted)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_P && (event.modifiers & Qt.MetaModifier)) {
                app.highlighted = (app.highlighted + 1) % app.choices.length;
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: app.dismiss()
        }

        MultiEffect {
            source: panel
            anchors.fill: panel
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.3
            shadowBlur: 0.8
            shadowHorizontalOffset: -2
            blurMax: 32
        }

        Rectangle {
            id: panel
            property real offset: 0
            x: app.width - width - 16 + offset
            width: Math.min(360, app.width - 32)
            height: column.implicitHeight + 40
            y: Math.max(16, (app.height - height) / 2)
            radius: 28
            color: M3.surfaceContainer

            NumberAnimation {
                id: slideIn
                target: panel
                property: "offset"
                to: 0
                duration: M3.durationMedium2
                easing.type: Easing.Bezier
                easing.bezierCurve: M3.easingEmphasizedDecelerate
            }

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 8

                MText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.bottomMargin: 4
                    role: "titleLarge"
                    text: i18n("Project")
                    color: M3.surfaceContent
                }

                MText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.bottomMargin: 4
                    visible: !app.available
                    role: "bodyMedium"
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    text: displays.ready ? i18n("Connect a second screen or projector to choose how it is used.") : i18n("Looking for screens…")
                    color: M3.surfaceVariantContent
                }

                Repeater {
                    model: app.choices

                    delegate: Rectangle {
                        id: choice

                        required property int index
                        required property var modelData
                        readonly property bool current: app.available && displays.projection === modelData.mode
                        readonly property bool highlighted: app.available && app.highlighted === index

                        Layout.fillWidth: true
                        implicitHeight: 72
                        radius: 20
                        opacity: app.available ? 1 : 0.38
                        color: current ? M3.secondaryContainer : M3.surfaceContainerHigh
                        border.width: highlighted ? 2 : 0
                        border.color: M3.primary

                        Behavior on color { ColorAnimation { duration: M3.durationShort4 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 16

                            Rectangle {
                                implicitWidth: 48
                                implicitHeight: 48
                                radius: 14
                                color: choice.current ? M3.primary : M3.surfaceContainerHighest
                                MIcon {
                                    anchors.centerIn: parent
                                    size: 28
                                    source: choice.modelData.icon
                                    color: choice.current ? M3.primaryContent : M3.surfaceVariantContent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                MText {
                                    Layout.fillWidth: true
                                    role: "titleMedium"
                                    text: choice.modelData.title
                                    color: choice.current ? M3.secondaryContainerContent : M3.surfaceContent
                                }
                                MText {
                                    Layout.fillWidth: true
                                    role: "bodySmall"
                                    text: choice.modelData.text
                                    color: choice.current ? M3.secondaryContainerContent : M3.surfaceVariantContent
                                }
                            }
                        }

                        MStateLayer {
                            radius: choice.radius
                            hovered: hover.containsMouse && app.available
                            pressed: hover.pressed && app.available
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: app.available
                            cursorShape: Qt.PointingHandCursor
                            onEntered: app.highlighted = choice.index
                            onClicked: app.choose(choice.index)
                        }
                    }
                }
            }
        }
    }
}
