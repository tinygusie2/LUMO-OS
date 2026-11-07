/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.lumo.m3
import org.lumo.ui
import org.lumo.system
import "../components"

SettingsPage {
    id: page

    title: i18n("Firewall")
    subtitle: i18n("The firewall blocks connections from other computers. Apps can still reach the internet.")

    readonly property string tool: "/usr/libexec/lumo-firewall"
    property var info: ({})
    property bool failed: false

    function refresh(): void {
        Process.run(page.tool, ["status"], (code, output) => {
            const values = {};
            for (const line of output.split("\n")) {
                const at = line.indexOf("=");
                if (at > 0) {
                    values[line.slice(0, at)] = line.slice(at + 1);
                }
            }
            page.info = values;
        });
    }

    function change(args: var): void {
        page.failed = false;
        Process.run("pkexec", [page.tool].concat(args), code => {
            page.failed = code !== 0 && code !== 126;
            page.refresh();
        });
    }

    Component.onCompleted: refresh()

    MText {
        width: parent.width
        visible: page.info.available === "no" || page.failed
        role: "bodyMedium"
        wrapMode: Text.Wrap
        color: M3.error
        text: page.failed ? i18n("The firewall could not be changed.") : i18n("The firewall is not installed on this system.")
    }

    Group {
        visible: page.info.available === "yes"

        ListItem {
            title: i18n("Firewall")
            subtitle: page.info.enabled === "yes" ? i18n("On") : i18n("Off: other computers can reach this one")
            icon: "security-high"
            iconStyle: "plain"
            checkable: true
            checked: page.info.enabled === "yes"
            onToggled: on => page.change([on ? "on" : "off"])
        }
    }

    Group {
        visible: page.info.available === "yes"
        title: i18n("Allowed through")

        ListItem {
            title: i18n("Phone")
            subtitle: i18n("Lets your phone connect to Lumo")
            icon: "smartphone"
            iconStyle: "plain"
            checkable: true
            checked: page.info.phone === "yes"
            onToggled: on => page.change([on ? "allow" : "deny", "phone"])
        }
        ListItem {
            title: i18n("File sharing")
            subtitle: i18n("Lets other computers open your shared folder")
            icon: "folder-network"
            iconStyle: "plain"
            checkable: true
            checked: page.info.sharing === "yes"
            onToggled: on => page.change([on ? "allow" : "deny", "sharing"])
        }
    }
}
