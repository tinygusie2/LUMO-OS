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

    title: i18n("Cloud & network folders")
    subtitle: i18n("Added folders appear in Files, next to your own.")

    readonly property string tool: "/usr/libexec/kernora-locations"
    readonly property string sharing: "/usr/libexec/kernora-sharing"
    property var locations: []
    property bool shared: false
    property bool canShare: false
    property string form: ""
    property bool working: false
    property string problem: ""

    Places { id: places }

    function refresh(): void {
        Process.run(page.tool, ["list"], (code, output) => {
            page.locations = output.split("\n").filter(line => line.length > 0).map(line => {
                const parts = line.split("|");
                return { name: parts[0], kind: parts[1], on: parts[2] === "on", path: parts[3] };
            });
        });
        Process.run(page.sharing, ["status"], (code, output) => {
            page.canShare = output.indexOf("available=yes") >= 0;
            page.shared = output.indexOf("enabled=yes") >= 0;
        });
    }

    function add(args: var, label: string, secret: string): void {
        page.working = true;
        page.problem = "";
        Process.run(page.tool, ["add"].concat(args), (code, output) => {
            page.working = false;
            if (code !== 0) {
                page.problem = i18n("%1 could not be added. Check the details and the connection.", label);
            } else {
                const match = output.match(/^path=(.*)$/m);
                if (match) {
                    places.addBookmark(Qt.url("file://" + match[1]), label);
                }
                page.form = "";
                password.text = "";
            }
            page.refresh();
        }, secret + "\n");
    }

    function kindName(kind: string): string {
        return kind === "onedrive" ? i18n("OneDrive")
             : kind === "drive" ? i18n("Google Drive")
             : kind === "webdav" ? i18n("Nextcloud")
             : i18n("Network folder");
    }

    Component.onCompleted: refresh()

    MText {
        width: parent.width
        visible: page.problem.length > 0
        role: "bodyMedium"
        wrapMode: Text.Wrap
        color: M3.error
        text: page.problem
    }

    LinearProgress {
        width: parent.width
        visible: page.working
        indeterminate: true
    }

    Group {
        visible: page.locations.length > 0
        title: i18n("Your folders")

        Repeater {
            model: page.locations
            delegate: ListItem {
                id: location
                required property var modelData
                title: modelData.name
                subtitle: page.kindName(modelData.kind) + (modelData.on ? "" : " · " + i18n("Not connected"))
                icon: modelData.kind === "smb" ? "folder-network" : "folder-cloud"
                iconStyle: "plain"
                onClicked: Process.openUrl(Qt.url("file://" + modelData.path))

                IconButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "edit-delete"
                    text: i18n("Remove")
                    onClicked: Process.run(page.tool, ["remove", location.modelData.name], () => page.refresh())
                }
            }
        }
    }

    Group {
        title: i18n("Add a folder")

        ListItem {
            title: i18n("OneDrive")
            subtitle: i18n("Sign in opens in your browser")
            icon: "folder-cloud"
            iconStyle: "plain"
            enabled: !page.working
            onClicked: page.add(["onedrive"], i18n("OneDrive"), "")
        }
        ListItem {
            title: i18n("Google Drive")
            subtitle: i18n("Sign in opens in your browser")
            icon: "folder-cloud"
            iconStyle: "plain"
            enabled: !page.working
            onClicked: page.add(["drive"], i18n("Google Drive"), "")
        }
        ListItem {
            title: i18n("Nextcloud")
            subtitle: i18n("Your server, with an app password")
            icon: "folder-cloud"
            iconStyle: "plain"
            enabled: !page.working
            onClicked: page.form = "nextcloud"
        }
        ListItem {
            title: i18n("Network folder")
            subtitle: i18n("A Windows PC or a NAS on your network")
            icon: "folder-network"
            iconStyle: "plain"
            enabled: !page.working
            onClicked: page.form = "smb"
        }
    }

    ColumnLayout {
        width: parent.width
        visible: page.form.length > 0
        spacing: 8

        QQC2.TextField {
            id: server
            Layout.fillWidth: true
            placeholderText: page.form === "smb" ? i18n("Computer name or address") : i18n("Server address, such as https://cloud.example.com")
        }
        QQC2.TextField {
            id: account
            Layout.fillWidth: true
            placeholderText: page.form === "smb" ? i18n("User name (optional)") : i18n("User name")
        }
        QQC2.TextField {
            id: password
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: i18n("Password")
        }
        RowLayout {
            spacing: 8
            QQC2.Button {
                text: i18n("Add")
                highlighted: true
                enabled: !page.working && server.text.length > 0
                onClicked: page.form === "smb"
                    ? page.add(["smb", server.text, account.text], server.text, password.text)
                    : page.add(["nextcloud", server.text, account.text], i18n("Nextcloud"), password.text)
            }
            QQC2.Button {
                text: i18n("Cancel")
                flat: true
                onClicked: page.form = ""
            }
        }
    }

    Group {
        visible: page.canShare
        title: i18n("Share with other computers")

        ListItem {
            title: i18n("Share my Public folder")
            subtitle: page.shared ? i18n("Windows PCs can open it with your user name and the sharing password") : i18n("Choose a sharing password below first")
            icon: "folder-publicshare"
            iconStyle: "plain"
            checkable: true
            checked: page.shared
            onToggled: on => {
                if (on && sharePassword.text.length === 0) {
                    page.problem = i18n("Choose a sharing password first.");
                    page.refresh();
                    return;
                }
                Process.run("pkexec", [page.sharing, on ? "enable" : "disable"], code => {
                    page.problem = code !== 0 && code !== 126 ? i18n("Sharing could not be changed.") : "";
                    sharePassword.text = "";
                    page.refresh();
                }, on ? sharePassword.text + "\n" : "");
            }
        }
    }

    QQC2.TextField {
        id: sharePassword
        width: parent.width
        visible: page.canShare && !page.shared
        echoMode: TextInput.Password
        placeholderText: i18n("Sharing password")
    }
}
