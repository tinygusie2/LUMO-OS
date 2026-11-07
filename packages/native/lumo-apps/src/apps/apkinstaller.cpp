// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Android App Installer");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-apkinstaller", "org.lumo.apkinstaller", "apkinstaller", "org.lumo.apkinstaller", false};
    return Lumo::run(argc, argv, application, displayName);
}
