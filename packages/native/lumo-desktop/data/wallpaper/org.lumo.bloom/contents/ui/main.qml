/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Scene {
        anchors.fill: parent
        intro: 0

        NumberAnimation on intro {
            from: 0
            to: 1
            duration: Kirigami.Units.longDuration <= 1 ? 0 : 900
            easing.type: Easing.OutCubic
        }
    }
}
