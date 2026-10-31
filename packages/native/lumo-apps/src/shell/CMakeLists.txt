# SPDX-FileCopyrightText: 2026 Kernora Developers
# SPDX-License-Identifier: GPL-2.0-or-later

ecm_add_qml_module(lumoshell URI "org.lumo.shell" VERSION 1.0 GENERATE_PLUGIN_SOURCE)

target_sources(lumoshell PRIVATE
    appletsettings.cpp appletsettings.h
)

target_link_libraries(lumoshell PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
    Plasma::Plasma Plasma::PlasmaQuick
)

ecm_finalize_qml_module(lumoshell DESTINATION ${KDE_INSTALL_QMLDIR})
