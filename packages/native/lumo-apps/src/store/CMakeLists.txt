# SPDX-FileCopyrightText: 2026 Kernora Developers
# SPDX-License-Identifier: GPL-2.0-or-later

ecm_add_qml_module(lumostore URI "org.lumo.store" VERSION 1.0 GENERATE_PLUGIN_SOURCE)

target_sources(lumostore PRIVATE
    appmodel.cpp appmodel.h
    debianbackend.cpp debianbackend.h
    flatpakbackend.cpp flatpakbackend.h
    store.cpp store.h
)

target_link_libraries(lumostore PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network
    KF6::CoreAddons KF6::I18n KF6::KIOGui KF6::Notifications KF6::Service
    AppStreamQt
    PK::packagekitqt6
    PkgConfig::FLATPAK
)

ecm_finalize_qml_module(lumostore DESTINATION ${KDE_INSTALL_QMLDIR})
target_compile_definitions(lumostore PRIVATE TRANSLATION_DOMAIN="lumo-store")
