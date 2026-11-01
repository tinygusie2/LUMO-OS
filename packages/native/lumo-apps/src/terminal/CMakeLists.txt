# SPDX-FileCopyrightText: 2026 Lumo Developers
# SPDX-License-Identifier: GPL-2.0-or-later

ecm_add_qml_module(lumoterminal URI "org.lumo.terminal" VERSION 1.0 GENERATE_PLUGIN_SOURCE)

target_sources(lumoterminal PRIVATE
    terminalcolours.cpp terminalcolours.h
    terminalview.cpp terminalview.h
)

target_link_libraries(lumoterminal PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
    PkgConfig::VTERM
    util
)

ecm_finalize_qml_module(lumoterminal DESTINATION ${KDE_INSTALL_QMLDIR})
target_compile_definitions(lumoterminal PRIVATE TRANSLATION_DOMAIN="lumo-terminal")
