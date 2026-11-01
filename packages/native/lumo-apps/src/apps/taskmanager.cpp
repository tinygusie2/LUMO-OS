// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

static KLocalizedString displayName()
{
    return ki18nc("@title application name", "Task Manager");
}

int main(int argc, char **argv)
{
    static const Lumo::Application application{"lumo-taskmanager", "org.lumo.taskmanager", "taskmanager", "org.lumo.taskmanager", true};
    return Lumo::run(argc, argv, application, displayName);
}
