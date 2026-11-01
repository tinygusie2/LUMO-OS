/*
    SPDX-FileCopyrightText: 2026 Lumo Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.lumo.m3
import org.lumo.ui
import org.lumo.system
import org.lumo.terminal

AppWindow {
    id: app

    width: 960
    height: 600
    minimumWidth: 420
    minimumHeight: 280
    color: M3.surfaceContainer
    visible: true
    title: current && current.title.length > 0 ? current.title : i18n("Terminal")

    ConfigEntry { id: zoom; file: "lumo-terminalrc"; group: "General"; key: "FontSize"; defaultValue: 11 }
    ConfigEntry { id: ignoreCase; file: "lumo-terminalrc"; group: "General"; key: "IgnoreCase"; defaultValue: true }
    readonly property real fontSize: Number(zoom.value) > 0 ? Number(zoom.value) : 11
    readonly property var current: views.count > 0 && pages.currentIndex >= 0 ? views.itemAt(pages.currentIndex) : null
    property int nextId: 1

    TerminalColours {
        id: palette
        dark: M3.dark
        colour: M3.colour
    }

    ListModel { id: tabs }

    function startDirectory(arguments: var): string {
        for (const argument of arguments || []) {
            if (!String(argument).startsWith("-")) {
                return String(argument);
            }
        }
        return "";
    }

    function newTab(directory: string): void {
        tabs.append({ uid: nextId++, title: "", directory: directory });
        pages.currentIndex = tabs.count - 1;
    }

    function closeTab(index: int): void {
        if (index < 0 || index >= tabs.count) {
            return;
        }
        tabs.remove(index);
        if (tabs.count === 0) {
            Qt.quit();
            return;
        }
        pages.currentIndex = Math.min(index, tabs.count - 1);
        focusCurrent();
    }

    function focusCurrent(): void {
        Qt.callLater(() => { if (app.current) app.current.terminal.forceActiveFocus(); });
    }

    function setZoom(size: real): void {
        zoom.value = Math.max(7, Math.min(32, Math.round(size)));
    }

    function handleArguments(arguments: var): void {
        newTab(startDirectory(arguments));
        app.show();
        app.raise();
        app.requestActivate();
    }

    Component.onCompleted: newTab(startDirectory(startArguments))

    Shortcut { sequences: ["Ctrl+Shift+T"]; onActivated: app.newTab(app.current ? app.current.terminal.workingDirectory : "") }
    Shortcut { sequences: ["Ctrl+Shift+W"]; onActivated: app.closeTab(pages.currentIndex) }
    Shortcut { sequences: ["Ctrl+Shift+N"]; onActivated: Process.startDetached("lumo-terminal", app.current ? [app.current.terminal.workingDirectory] : []) }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: { pages.currentIndex = (pages.currentIndex + 1) % tabs.count; app.focusCurrent(); } }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: { pages.currentIndex = (pages.currentIndex + tabs.count - 1) % tabs.count; app.focusCurrent(); } }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: app.setZoom(app.fontSize + 1) }
    Shortcut { sequences: ["Ctrl+-"]; onActivated: app.setZoom(app.fontSize - 1) }
    Shortcut { sequences: ["Ctrl+0"]; onActivated: app.setZoom(11) }
    Shortcut { sequences: ["Ctrl+Shift+F"]; onActivated: app.visibility === Window.FullScreen ? app.showNormal() : app.showFullScreen() }
    Shortcut { sequences: ["F11"]; onActivated: app.visibility === Window.FullScreen ? app.showNormal() : app.showFullScreen() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 56
            Layout.leftMargin: M3.spacingS
            Layout.rightMargin: M3.spacingS
            spacing: M3.spacingXS

            ListView {
                id: strip

                Layout.fillHeight: true
                Layout.preferredWidth: Math.min(contentWidth, parent.width - addButton.width - menuButton.width - M3.spacingL)
                orientation: ListView.Horizontal
                spacing: M3.spacingXS
                clip: true
                interactive: contentWidth > width
                boundsBehavior: Flickable.StopAtBounds
                model: tabs
                currentIndex: pages.currentIndex
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: M3.durationMedium2; easing.type: Easing.Bezier; easing.bezierCurve: M3.easingEmphasizedDecelerate }
                    NumberAnimation { property: "scale"; from: 0.85; to: 1; duration: M3.durationMedium2; easing.type: Easing.Bezier; easing.bezierCurve: M3.easingEmphasizedDecelerate }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x"; duration: M3.durationMedium2; easing.type: Easing.Bezier; easing.bezierCurve: M3.easingEmphasized }
                }

                delegate: QQC2.AbstractButton {
                    id: tab

                    required property int index
                    required property string title
                    readonly property bool selected: index === pages.currentIndex

                    width: Math.max(140, Math.min(240, (app.width - 160) / Math.max(1, tabs.count)))
                    height: 40
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    text: title.length > 0 ? title : i18n("Terminal")
                    Accessible.role: Accessible.PageTab
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered && label.truncated
                    QQC2.ToolTip.delay: 600

                    onClicked: { pages.currentIndex = index; app.focusCurrent(); }

                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: app.closeTab(tab.index)
                    }

                    MMorph { id: pressMorph; active: tab.pressed }

                    background: Rectangle {
                        radius: M3.classic ? height / 2 : height / 2 - (height / 2 - Math.round(height * 0.3)) * pressMorph.value
                        color: tab.selected ? M3.secondaryContainer : "transparent"
                        Behavior on color { ColorAnimation { duration: M3.durationShort4 } }

                        MStateLayer {
                            radius: parent.radius
                            color: tab.selected ? M3.secondaryContainerContent : M3.surfaceVariantContent
                            hovered: tab.hovered
                            pressed: tab.pressed
                        }
                    }

                    contentItem: RowLayout {
                        spacing: M3.spacingS

                        MIcon {
                            Layout.leftMargin: M3.spacingM
                            size: 20
                            source: "org.lumo.terminal"
                            color: tab.selected ? M3.secondaryContainerContent : M3.surfaceVariantContent
                        }
                        MText {
                            id: label
                            Layout.fillWidth: true
                            role: "labelLarge"
                            text: tab.text
                            color: tab.selected ? M3.secondaryContainerContent : M3.surfaceVariantContent
                        }
                        IconButton {
                            Layout.rightMargin: M3.spacingXS
                            implicitWidth: 28
                            implicitHeight: 28
                            iconName: "window-close"
                            text: i18n("Close tab")
                            ink: tab.selected ? M3.secondaryContainerContent : M3.surfaceVariantContent
                            opacity: tab.selected || tab.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: M3.durationShort4 } }
                            onClicked: app.closeTab(tab.index)
                        }
                    }
                }
            }

            IconButton {
                id: addButton
                iconName: "list-add"
                text: i18n("New tab (Ctrl+Shift+T)")
                onClicked: app.newTab(app.current ? app.current.terminal.workingDirectory : "")
            }

            Item { Layout.fillWidth: true }

            IconButton {
                id: menuButton
                iconName: "overflow-menu"
                text: i18n("More")
                onClicked: mainMenu.popup(menuButton, 0, menuButton.height)
            }
        }

        StackLayout {
            id: pages

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: M3.spacingS
            Layout.rightMargin: M3.spacingS
            Layout.bottomMargin: M3.spacingS

            Repeater {
                id: views
                model: tabs

                delegate: Rectangle {
                    id: pane

                    required property int index
                    required property string directory
                    readonly property alias terminal: view
                    readonly property string title: view.title

                    radius: M3.cornerCard
                    color: palette.colours.background ?? M3.surface
                    onTitleChanged: tabs.setProperty(index, "title", title)

                    TerminalView {
                        id: view

                        anchors.fill: parent
                        anchors.leftMargin: M3.spacingL
                        anchors.topMargin: M3.spacingM
                        anchors.bottomMargin: M3.spacingM
                        anchors.rightMargin: M3.spacingL + scrollBar.width
                        fontFamily: "Hack"
                        fontSize: app.fontSize
                        colours: palette.colours
                        focus: true

                        Component.onCompleted: {
                            start(pane.directory);
                            forceActiveFocus();
                        }
                        onFinished: app.closeTab(pane.index)
                        onContextMenuRequested: (x, y) => {
                            if (hasSelection) {
                                copy();
                                clearSelection();
                                app.showMessage(i18n("Copied"), "", null);
                            } else {
                                paste();
                            }
                        }
                    }

                    QQC2.ScrollBar {
                        id: scrollBar

                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: M3.spacingXS
                        orientation: Qt.Vertical
                        policy: view.historySize > 0 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
                        readonly property real total: view.historySize + view.rows
                        size: total > 0 ? view.rows / total : 1
                        position: total > 0 ? (view.historySize - view.scrollOffset) / total : 0
                        onPositionChanged: {
                            if (pressed) {
                                view.scrollOffset = Math.round(view.historySize - position * total);
                            }
                        }
                    }
                }
            }
        }
    }

    QQC2.Menu {
        id: mainMenu

        QQC2.MenuItem { text: i18n("New tab"); icon.name: "list-add"; onTriggered: app.newTab(app.current ? app.current.terminal.workingDirectory : "") }
        QQC2.MenuItem { text: i18n("New window"); icon.name: "window-new"; onTriggered: Process.startDetached("lumo-terminal", app.current ? [app.current.terminal.workingDirectory] : []) }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: i18n("Copy"); icon.name: "edit-copy"; enabled: app.current && app.current.terminal.hasSelection; onTriggered: app.current.terminal.copy() }
        QQC2.MenuItem { text: i18n("Paste"); icon.name: "edit-paste"; onTriggered: app.current.terminal.paste() }
        QQC2.MenuItem { text: i18n("Select all"); icon.name: "edit-select-all"; onTriggered: app.current.terminal.selectAll() }
        QQC2.MenuItem { text: i18n("Clear screen"); icon.name: "edit-clear-all"; onTriggered: { app.current.terminal.clearHistory(); app.current.terminal.sendText("\x0c"); } }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: i18n("Bigger text"); icon.name: "zoom-in"; onTriggered: app.setZoom(app.fontSize + 1) }
        QQC2.MenuItem { text: i18n("Smaller text"); icon.name: "zoom-out"; onTriggered: app.setZoom(app.fontSize - 1) }
        QQC2.MenuItem { text: i18n("Ignore upper and lower case"); checkable: true; checked: ignoreCase.value === true || ignoreCase.value === "true"; onTriggered: ignoreCase.value = checked }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: i18n("Open folder in Files"); icon.name: "folder"; onTriggered: Process.startDetached("lumo-files", [app.current.terminal.workingDirectory]) }
        QQC2.MenuItem { text: i18n("Windows commands"); icon.name: "help-contents"; onTriggered: app.current.terminal.sendText("help\n") }
    }
}
