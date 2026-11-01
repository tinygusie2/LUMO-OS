/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.lumo.m3
import org.lumo.ui
import org.lumo.system
import "../components"

SettingsPage {
    id: page

    property var group

    title: group ? group.name : ""
    subtitle: group && group.multiple ? i18n("Several can be on at once") : i18n("Only one can be on")

    Group {
        Repeater {
            model: page.group ? page.group.options : []
            delegate: ListItem {
                required property var modelData
                title: modelData.name
                checkable: true
                checked: Locales.keyboardOptions.includes(modelData.id)
                onToggled: on => {
                    if (page.group.multiple) {
                        Locales.setKeyboardOption(modelData.id, on);
                    } else {
                        Locales.setKeyboardGroupChoice(page.group.id, on ? modelData.id : "");
                    }
                }
            }
        }
    }
}
