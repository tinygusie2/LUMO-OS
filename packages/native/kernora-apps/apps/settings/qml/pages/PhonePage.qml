/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kernora.m3
import org.kernora.ui
import org.kernora.system
import "../components"

SettingsPage {
    id: page

    title: i18n("Phone")
    subtitle: i18n("See your phone's notifications here, send texts, share files and the clipboard, and find your phone.")

    readonly property string tool: Process.findExecutable("kdeconnect-cli")
    readonly property bool quickShare: Process.findExecutable("rquickshare").length > 0
    readonly property string quickShareStartup: "org.kernora.quickshare-resident.desktop"
    property int startupRevision: 0
    readonly property bool quickShareAlways: {
        startupRevision;
        const entry = Autostart.entries().find(e => e.id === quickShareStartup);
        return entry !== undefined && entry.enabled;
    }
    property var devices: []
    property bool loaded: false
    property string busy: ""
    property var smsTarget: null

    readonly property var paired: devices.filter(d => d.paired)
    readonly property var nearby: devices.filter(d => !d.paired && d.reachable)

    function refresh(): void {
        if (tool.length === 0) {
            loaded = true;
            return;
        }
        Process.run("env", ["LANGUAGE=C", "LC_ALL=C", tool, "-l"], (code, output) => {
            const found = [];
            for (const line of output.split("\n")) {
                const m = line.match(/^- (.+): (\S+) \((.+)\)\s*$/);
                if (m) {
                    found.push({ name: m[1], id: m[2], paired: m[3].includes("paired"), reachable: m[3].includes("reachable") });
                }
            }
            page.devices = found;
            page.loaded = true;
        });
    }

    function command(device: var, args: var, done: string, failed: string): void {
        busy = device.id;
        Process.run(tool, ["-d", device.id].concat(args), code => {
            page.busy = "";
            page.notify(code === 0 ? done : failed);
            page.refresh();
        });
    }

    Component.onCompleted: {
        if (tool.length > 0) {
            Process.run(tool, ["--refresh"], () => page.refresh());
        }
        refresh();
    }

    Timer {
        interval: 4000
        running: page.visible && page.tool.length > 0
        repeat: true
        onTriggered: page.refresh()
    }

    FileDialog {
        id: shareDialog
        property var device: null
        title: i18n("Send files to your phone")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (const file of selectedFiles) {
                page.command(device, ["--share", file.toString()], i18n("Sent to %1", device.name), i18n("Couldn't send the file"));
            }
        }
    }

    Dialog {
        id: smsDialog
        title: i18n("Send a text message")
        text: page.smsTarget ? i18n("The message is sent from %1.", page.smsTarget.name) : ""
        acceptText: i18n("Send")
        acceptEnabled: number.text.trim().length > 0 && message.text.trim().length > 0
        onAccepted: page.command(page.smsTarget, ["--send-sms", message.text.trim(), "--destination", number.text.trim()],
                                 i18n("Text message sent"), i18n("Couldn't send the text message"))
        InputField { id: number; Layout.fillWidth: true; label: i18n("Phone number") }
        InputField { id: message; Layout.fillWidth: true; label: i18n("Message") }
    }

    Group {
        visible: page.tool.length === 0
        title: i18n("Phone link is not installed")
        note: i18n("Install the kdeconnect package to connect your phone.")
    }

    Group {
        title: i18n("Quick Share")
        visible: page.quickShare
        note: i18n("Share with an Android phone the way you share between phones: on the phone, choose Share, then Quick Share, and pick this computer. Both need to be on the same network.")

        ListItem {
            title: i18n("Open Quick Share")
            subtitle: i18n("Send files: drag them into the window and pick the phone")
            icon: "rquickshare"
            chevron: true
            onClicked: Process.launchApplication("org.kernora.quickshare.desktop", [])
        }
        ListItem {
            title: i18n("Always ready to receive")
            subtitle: i18n("Quick Share starts when you log in and waits in the status area")
            icon: "document-save"
            checkable: true
            checked: page.quickShareAlways
            onToggled: on => {
                Autostart.setEnabled(page.quickShareStartup, on);
                page.startupRevision += 1;
                if (on) {
                    Process.startDetached("kernora-quickshare", ["resident"]);
                }
            }
        }
    }

    Group {
        title: i18n("Your phones")
        visible: page.tool.length > 0
        note: !page.loaded ? i18n("Looking for phones…")
            : page.paired.length === 0 ? i18n("No phone connected yet. Set one up below.") : ""

        Repeater {
            model: page.paired
            delegate: ListItem {
                required property var modelData
                title: modelData.name
                subtitle: modelData.reachable ? i18n("Connected") : i18n("Not nearby · connects when on the same network")
                icon: "phone"
                accent: modelData.reachable ? 0 : -1
                iconStyle: modelData.reachable ? "circle" : "plain"
                interactive: false
            }
        }
    }

    Repeater {
        model: page.paired.filter(d => d.reachable)
        delegate: Group {
            id: actions
            required property var modelData
            width: parent ? parent.width : 0
            title: modelData.name

            ListItem {
                title: i18n("Send files")
                subtitle: i18n("Photos, documents, anything")
                icon: "document-send"
                chevron: true
                enabled: page.busy.length === 0
                onClicked: {
                    shareDialog.device = actions.modelData;
                    shareDialog.open();
                }
            }
            ListItem {
                title: i18n("Browse the phone")
                subtitle: i18n("Copy photos and files from the phone in Files")
                icon: "folder-pictures"
                chevron: true
                onClicked: Process.launchApplication("org.kernora.files.desktop", [Qt.url("kdeconnect://" + actions.modelData.id + "/")])
            }
            ListItem {
                title: i18n("Send a text message")
                subtitle: i18n("Through the phone's own number")
                icon: "mail-message-new"
                chevron: true
                onClicked: {
                    page.smsTarget = actions.modelData;
                    number.text = "";
                    message.text = "";
                    smsDialog.open();
                }
            }
            ListItem {
                title: i18n("Messages")
                subtitle: i18n("Read and answer your conversations")
                icon: "dialog-messages"
                chevron: true
                visible: Process.application("org.kde.kdeconnect.sms.desktop").name !== undefined
                onClicked: Process.launchApplication("org.kde.kdeconnect.sms.desktop", [])
            }
            ListItem {
                title: i18n("Find my phone")
                subtitle: i18n("Make it ring, even when it is on silent")
                icon: "audio-volume-high"
                enabled: page.busy.length === 0
                onClicked: page.command(actions.modelData, ["--ring"], i18n("%1 is ringing", actions.modelData.name), i18n("Couldn't reach the phone"))
            }
            ListItem {
                title: i18n("Disconnect this phone")
                icon: "list-remove"
                destructive: true
                onClicked: page.command(actions.modelData, ["--unpair"], i18n("%1 is disconnected", actions.modelData.name), i18n("Couldn't disconnect"))
            }
        }
    }

    Group {
        title: i18n("Connect a phone")
        visible: page.tool.length > 0
        note: i18n("1. Install KDE Connect on your phone: from Google Play or F-Droid on Android, or from the App Store on iPhone.\n2. Connect the phone to the same Wi-Fi as this computer.\n3. Open KDE Connect on the phone; it appears below. Choose Connect and accept on the phone.")

        Repeater {
            model: page.nearby
            delegate: ListItem {
                id: nearbyRow
                required property var modelData
                title: modelData.name
                subtitle: page.busy === modelData.id ? i18n("Waiting for the phone…") : i18n("Nearby")
                icon: "phone"
                trailing: Component {
                    QQC2.Button {
                        text: i18n("Connect")
                        highlighted: true
                        enabled: page.busy.length === 0
                        onClicked: page.command(nearbyRow.modelData, ["--pair"], i18n("Accept on %1 to finish", nearbyRow.modelData.name), i18n("Couldn't connect"))
                    }
                }
            }
        }
        ListItem {
            title: i18n("Look again")
            icon: "view-refresh"
            onClicked: Process.run(page.tool, ["--refresh"], () => page.refresh())
        }
    }

    Group {
        title: i18n("What works")
        visible: page.tool.length > 0
        ListItem {
            title: i18n("Notifications from your phone")
            subtitle: i18n("Appear here as normal notifications. Android only")
            icon: "preferences-desktop-notification"
            interactive: false
        }
        ListItem {
            title: i18n("Shared clipboard")
            subtitle: i18n("Copy on one device, paste on the other")
            icon: "edit-paste"
            interactive: false
        }
        ListItem {
            title: i18n("More options")
            subtitle: i18n("Choose per phone what it may do")
            icon: "applications-system"
            chevron: true
            onClicked: Process.openModule("kcm_kdeconnect")
        }
    }
}
