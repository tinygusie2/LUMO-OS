// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include <QApplication>
#include <QDBusConnection>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QTimer>

#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include "portal.h"
#include "types.h"

using namespace Qt::StringLiterals;

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(u"org.lumo.desktop"_s);
    }
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain("lumo-files");

    QCoreApplication::setApplicationName(u"lumo-filechooser"_s);
    QCoreApplication::setApplicationVersion(QStringLiteral(LUMO_APPS_VERSION));
    QGuiApplication::setDesktopFileName(u"org.lumo.filechooser"_s);
    QApplication::setWindowIcon(QIcon::fromTheme(u"org.lumo.files"_s));

    Portal::registerTypes();
    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);

    FileChooser chooser(&engine);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(u"/org/freedesktop/portal/desktop"_s, &chooser,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties)) {
        qCritical("lumo-filechooser: cannot register the portal object");
        return 1;
    }
    if (!bus.registerService(u"org.freedesktop.impl.portal.desktop.lumo"_s)) {
        qCritical("lumo-filechooser: the portal name is taken");
        return 1;
    }

    QTimer idle;
    idle.setSingleShot(true);
    idle.setInterval(std::chrono::minutes(5));
    QObject::connect(&idle, &QTimer::timeout, &app, [&chooser] {
        if (chooser.pending() == 0) {
            QApplication::quit();
        }
    });
    QObject::connect(&chooser, &FileChooser::idle, &idle, qOverload<>(&QTimer::start));
    idle.start();

    return app.exec();
}
