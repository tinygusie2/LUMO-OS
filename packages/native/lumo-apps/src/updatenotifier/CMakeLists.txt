# SPDX-FileCopyrightText: 2026 Kernora Developers
# SPDX-License-Identifier: GPL-2.0-or-later

add_library(lumo-appicons STATIC appicons.cpp appicons.h appiconsync.cpp appiconsync.h)
target_link_libraries(lumo-appicons PUBLIC Qt6::Gui Qt6::DBus KF6::ConfigCore KF6::Service)

add_executable(lumo-update-notifier main.cpp avatarsync.cpp avatarsync.h greetersync.cpp greetersync.h)
target_link_libraries(lumo-update-notifier PRIVATE
    lumo-appicons
    Qt6::Gui Qt6::DBus Qt6::Network
    KF6::ConfigCore KF6::CoreAddons KF6::DBusAddons KF6::I18n KF6::Notifications
    PK::packagekitqt6)
target_compile_definitions(lumo-update-notifier PRIVATE
    TRANSLATION_DOMAIN="lumo-update-notifier"
    LUMO_APPS_VERSION="${PROJECT_VERSION}")
install(TARGETS lumo-update-notifier ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})

add_executable(lumo-app-icons appiconstool.cpp)
target_link_libraries(lumo-app-icons PRIVATE lumo-appicons)
install(TARGETS lumo-app-icons ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
