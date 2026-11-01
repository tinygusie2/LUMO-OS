// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Project");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-projection", "org.lumo.projection", "projection", "osd-duplicate", true};
    return Lumo::run(argc, argv, application, displayName);
}
