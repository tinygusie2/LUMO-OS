// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Text Editor");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-editor", "org.lumo.editor", "editor", "org.lumo.editor", false};
    return Lumo::run(argc, argv, application, displayName);
}
