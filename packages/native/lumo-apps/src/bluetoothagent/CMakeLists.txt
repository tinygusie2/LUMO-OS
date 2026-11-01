# SPDX-FileCopyrightText: 2026 Kernora Developers
# SPDX-License-Identifier: GPL-2.0-or-later

add_executable(lumo-bluetooth-agent main.cpp agent.cpp agent.h)
target_link_libraries(lumo-bluetooth-agent PRIVATE
    Qt6::Widgets Qt6::DBus Qt6::Qml Qt6::Quick Qt6::QuickControls2
    KF6::CoreAddons KF6::DBusAddons KF6::I18n KF6::I18nQml KF6::BluezQt)
target_compile_definitions(lumo-bluetooth-agent PRIVATE
    TRANSLATION_DOMAIN="lumo-bluetooth-agent"
    LUMO_APPS_VERSION="${PROJECT_VERSION}")
install(TARGETS lumo-bluetooth-agent ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
