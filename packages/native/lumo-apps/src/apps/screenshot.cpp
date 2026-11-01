// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Screenshot");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-screenshot", "org.lumo.screenshot", "screenshot", "org.lumo.screenshot", true};
    return Lumo::run(argc, argv, application, displayName);
}
