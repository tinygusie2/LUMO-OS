// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Focus");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-focus", "org.lumo.focus", "focus", "org.lumo.focus", true};
    return Lumo::run(argc, argv, application, displayName);
}
