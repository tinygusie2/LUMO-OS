// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Settings");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-settings", "org.lumo.settings", "settings", "org.lumo.settings", true};
    return Lumo::run(argc, argv, application, displayName);
}
