/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
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

    title: i18n("Focus mode")
    subtitle: i18n("Block distracting apps while the Focus timer runs. When it ends, or after a restart, everything is back to normal.")

    readonly property string configFile: "lumofocusrc"
    readonly property var chosen: String(appsEntry.value || "").split(",").filter(id => id.length > 0)
    readonly property var entries: chosen.map(id => {
        const info = Process.application(id);
        return { id: id, name: info.name || id.replace(/\.desktop$/, ""), icon: info.icon || "application-x-executable" };
    })
    readonly property var hidden: ["org.lumo.focus.desktop", "org.lumo.settings.desktop", "systemsettings.desktop"]

    function setApps(list: var): void {
        appsEntry.value = list.join(",");
    }

    function isOn(entry: var): bool {
        return entry.value === true || entry.value === "true";
    }

    ConfigEntry { id: appsEntry; file: page.configFile; group: "General"; key: "Apps"; defaultValue: "" }
    ConfigEntry { id: focusEntry; file: page.configFile; group: "General"; key: "FocusMinutes"; defaultValue: 25 }
    ConfigEntry { id: breakEntry; file: page.configFile; group: "General"; key: "BreakMinutes"; defaultValue: 5 }
    ConfigEntry { id: roundsEntry; file: page.configFile; group: "General"; key: "Rounds"; defaultValue: 4 }
    ConfigEntry { id: dndEntry; file: page.configFile; group: "General"; key: "DoNotDisturb"; defaultValue: true }
    ConfigEntry { id: breakAppsEntry; file: page.configFile; group: "General"; key: "AppsInBreaks"; defaultValue: false }

    Group {
        ListItem {
            title: i18n("Start focus")
            subtitle: i18np("%2 min focus and %3 min break, %1 round", "%2 min focus and %3 min break, %1 rounds",
                            Number(roundsEntry.value), Number(focusEntry.value), Number(breakEntry.value))
            icon: "media-playback-start"
            accent: 0
            chevron: true
            onClicked: Process.startDetached("lumo-focus", ["start"])
        }
    }

    Group {
        title: i18n("Distracting apps")
        note: page.entries.length === 0 ? i18n("No apps are blocked yet.") : ""

        Repeater {
            model: page.entries
            delegate: ListItem {
                id: row
                required property var modelData
                title: modelData.name
                leading: Component {
                    AppIcon {
                        name: row.modelData.icon
                    }
                }
                trailing: Component {
                    IconButton {
                        iconName: "list-remove"
                        text: i18n("Remove")
                        onClicked: page.setApps(page.chosen.filter(id => id !== row.modelData.id))
                    }
                }
            }
        }

        ListItem {
            title: i18n("Add an app")
            icon: "list-add"
            accent: 4
            chevron: true
            onClicked: addDialog.open()
        }
    }

    Group {
        title: i18n("Pomodoro timer")

        SliderItem {
            title: i18n("Focus time")
            icon: "lumo-timer"
            accent: 0
            from: 5
            to: 90
            stepSize: 5
            value: Number(focusEntry.value)
            formatValue: v => i18np("%1 minute", "%1 minutes", Math.round(v))
            onMoved: value => focusEntry.value = Math.round(value)
        }
        SliderItem {
            title: i18n("Break")
            icon: "caffeine"
            accent: 3
            from: 1
            to: 30
            stepSize: 1
            value: Number(breakEntry.value)
            formatValue: v => i18np("%1 minute", "%1 minutes", Math.round(v))
            onMoved: value => breakEntry.value = Math.round(value)
        }
        SliderItem {
            title: i18n("Rounds")
            icon: "view-refresh"
            accent: 2
            from: 1
            to: 8
            stepSize: 1
            value: Number(roundsEntry.value)
            formatValue: v => i18np("%1 round", "%1 rounds", Math.round(v))
            onMoved: value => roundsEntry.value = Math.round(value)
        }
    }

    Group {
        title: i18n("While you focus")

        ListItem {
            title: i18n("Do Not Disturb")
            subtitle: i18n("Hold back notifications during focus rounds")
            icon: "notifications-disabled"
            accent: 4
            checkable: true
            checked: page.isOn(dndEntry)
            onToggled: on => dndEntry.value = on
        }
        ListItem {
            title: i18n("Allow distracting apps during breaks")
            subtitle: i18n("Otherwise they stay blocked until every round is done")
            icon: "caffeine"
            accent: 3
            checkable: true
            checked: page.isOn(breakAppsEntry)
            onToggled: on => breakAppsEntry.value = on
        }
    }

    ChoiceDialog {
        id: addDialog
        title: i18n("Block during focus")
        searchable: true
        options: addDialog.visible
            ? Autostart.applications()
                .filter(a => page.hidden.indexOf(a.storageId) < 0 && page.chosen.indexOf(a.storageId) < 0)
                .map(a => ({ value: a.storageId, label: a.name, appIcon: a.icon }))
            : []
        onChosen: value => page.setApps(page.chosen.concat([value]))
    }
}
