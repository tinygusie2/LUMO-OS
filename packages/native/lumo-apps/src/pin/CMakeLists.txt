# SPDX-FileCopyrightText: 2026 Lumo contributors
# SPDX-License-Identifier: GPL-2.0-or-later

add_executable(lumo-pin pin.c)
target_link_libraries(lumo-pin PRIVATE PkgConfig::LIBCRYPT)
install(TARGETS lumo-pin DESTINATION libexec)
install(FILES lumo-pin.pam-config DESTINATION ${KDE_INSTALL_DATADIR}/pam-configs RENAME lumo-pin)
install(FILES org.lumo.pin.policy DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions)
