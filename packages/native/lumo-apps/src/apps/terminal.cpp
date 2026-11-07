// SPDX-FileCopyrightText: 2026 Lumo Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Terminal");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-terminal", "org.lumo.terminal", "terminal", "org.lumo.terminal", false};
    return Lumo::run(argc, argv, application, displayName);
}
