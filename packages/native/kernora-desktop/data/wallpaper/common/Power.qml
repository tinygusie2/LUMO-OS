/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

Item {
    id: power

    property bool active: true

    readonly property var battery: batteryLoader.item
    readonly property var profiles: profileLoader.item
    readonly property bool unplugged: battery !== null && battery.hasInternalBatteries === true && battery.pluggedIn === false
    readonly property bool low: unplugged && battery.percent <= 20
    readonly property bool saver: profiles !== null && profiles.activeProfile === "power-saver"

    Loader {
        id: batteryLoader
        active: power.active
        source: "PowerBattery.qml"
    }
    Loader {
        id: profileLoader
        active: power.active
        source: "PowerProfile.qml"
    }
}
