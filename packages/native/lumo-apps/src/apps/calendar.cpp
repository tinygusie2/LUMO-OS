// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Calendar");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-calendar", "org.lumo.calendar", "calendar", "org.lumo.calendar", true};
    return Lumo::run(argc, argv, application, displayName);
}
