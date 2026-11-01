// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Quick Share");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-share", "org.lumo.share", "share", "org.lumo.quickshare", true};
    return Lumo::run(argc, argv, application, displayName);
}
