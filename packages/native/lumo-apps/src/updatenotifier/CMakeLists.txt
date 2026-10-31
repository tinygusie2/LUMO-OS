# SPDX-FileCopyrightText: 2026 Kernora Developers
# SPDX-License-Identifier: GPL-2.0-or-later

add_executable(lumo-update-notifier main.cpp)
target_link_libraries(lumo-update-notifier PRIVATE
    Qt6::Gui Qt6::DBus Qt6::Network
    KF6::ConfigCore KF6::CoreAddons KF6::DBusAddons KF6::I18n KF6::Notifications
    PK::packagekitqt6)
target_compile_definitions(lumo-update-notifier PRIVATE
    TRANSLATION_DOMAIN="lumo-update-notifier"
    LUMO_APPS_VERSION="${PROJECT_VERSION}")
install(TARGETS lumo-update-notifier ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
