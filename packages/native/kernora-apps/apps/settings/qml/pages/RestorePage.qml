/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kernora.m3
import org.kernora.ui
import org.kernora.system
import "../components"

SettingsPage {
    id: page

    title: i18n("Restore points")
    subtitle: i18n("Lumo saves the system before every update. Your own files are not changed.")

    readonly property string tool: "/usr/libexec/kernora-snapshots"
    property bool loaded: false
    property bool available: false
    property string booted: ""
    property var points: []
    property string chosen: ""
    property string chosenDate: ""
    property bool working: false
    property bool done: false
    property bool failed: false

    function refresh(): void {
        Process.run(page.tool, ["status"], (code, output) => {
            const list = [];
            for (const line of output.split("\n")) {
                const at = line.indexOf("=");
                if (at <= 0) {
                    continue;
                }
                const key = line.slice(0, at);
                const value = line.slice(at + 1);
                if (key === "enabled") {
                    page.available = value === "yes";
                } else if (key === "booted") {
                    page.booted = value;
                } else if (key === "point") {
                    const parts = value.split("|");
                    list.push({ number: parts[0], date: parts[1] || "" });
                }
            }
            page.points = list;
            page.loaded = true;
        });
    }

    function restore(): void {
        page.working = true;
        page.failed = false;
        Process.run("pkexec", [page.tool, "restore", page.chosen], code => {
            page.working = false;
            page.failed = code !== 0 && code !== 126;
            page.done = code === 0;
        });
    }

    Component.onCompleted: refresh()

    onBootedChanged: {
        if (booted.length > 0) {
            chosen = booted;
        }
    }

    readonly property string headline: {
        if (done) {
            return i18n("Restart to finish");
        }
        if (failed) {
            return i18n("The system could not be restored");
        }
        if (booted.length > 0) {
            return i18n("You started from a restore point");
        }
        if (chosen.length > 0) {
            return i18n("Go back to %1?", chosenDate);
        }
        if (loaded && !available) {
            return i18n("Restore points are off");
        }
        return points.length > 0 ? i18n("Choose a restore point") : i18n("No restore points yet");
    }

    readonly property string detail: {
        if (done) {
            return i18n("Lumo starts from the restore point after the restart. The previous system is kept until the next time you restore.");
        }
        if (failed) {
            return i18n("Nothing was changed.");
        }
        if (booted.length > 0) {
            return i18n("What you change now is lost at the next restart. If everything works, keep this version.");
        }
        if (chosen.length > 0) {
            return i18n("Programs and system settings go back to that moment. Your documents and other files stay as they are.");
        }
        if (loaded && !available) {
            return i18n("They need a system installed on btrfs.");
        }
        return points.length > 0
            ? i18n("If Lumo no longer starts, you find these under Restore points in the boot menu.")
            : i18n("The first one is made at the next update.");
    }

    Rectangle {
        id: summary
        width: parent.width
        implicitHeight: content.implicitHeight + 48
        radius: M3.classic ? M3.cornerCard : 28
        color: page.failed ? M3.errorContainer
             : page.done || page.booted.length > 0 ? M3.tertiaryContainer : M3.surfaceContainerHigh

        readonly property color ink: page.failed ? M3.errorContainerContent
             : page.done || page.booted.length > 0 ? M3.tertiaryContainerContent : M3.surfaceContent

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 24
            spacing: 12

            MText {
                Layout.fillWidth: true
                role: "titleLarge"
                text: page.headline
                wrapMode: Text.Wrap
                color: summary.ink
            }
            MText {
                Layout.fillWidth: true
                role: "bodyMedium"
                text: page.detail
                visible: text.length > 0
                wrapMode: Text.Wrap
                color: summary.ink
            }
            LinearProgress {
                Layout.fillWidth: true
                visible: page.working
                indeterminate: true
            }
            RowLayout {
                spacing: 8
                visible: !page.working && (page.done || page.chosen.length > 0)
                QQC2.Button {
                    visible: page.done
                    text: i18n("Restart")
                    icon.name: "system-reboot"
                    highlighted: true
                    onClicked: DBus.call("session", "org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptReboot", [], null)
                }
                QQC2.Button {
                    visible: !page.done
                    text: page.booted.length > 0 ? i18n("Keep this version") : i18n("Go back")
                    icon.name: "document-revert"
                    highlighted: true
                    onClicked: page.restore()
                }
                QQC2.Button {
                    visible: !page.done && page.booted.length === 0
                    text: i18n("Cancel")
                    flat: true
                    onClicked: page.chosen = ""
                }
            }
        }
    }

    Group {
        visible: page.points.length > 0 && page.booted.length === 0 && !page.done

        Repeater {
            model: page.points
            delegate: ListItem {
                required property var modelData
                title: modelData.date
                subtitle: i18n("Before an update")
                icon: "document-revert"
                accent: 1
                onClicked: {
                    page.chosen = modelData.number;
                    page.chosenDate = modelData.date;
                    page.failed = false;
                }
            }
        }
    }
}
