// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "host.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>
#include <QIcon>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QUrl>

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>

#include <unistd.h>

namespace Lumo
{
static QString interfaceFile(const Application &application)
{
    const QByteArray variable = "LUMO_QML_" + QByteArray(application.folder).toUpper();
    const QString override = qEnvironmentVariable(variable.constData());
    if (!override.isEmpty()) {
        return QDir(override).filePath(QStringLiteral("Main.qml"));
    }
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                  QStringLiteral("lumo/%1/Main.qml").arg(QString::fromLatin1(application.folder)));
}

static bool replacedOnDisk()
{
    char target[4096];
    const ssize_t length = ::readlink("/proc/self/exe", target, sizeof(target) - 1);
    return length > 0 && QByteArray(target, length).endsWith(" (deleted)");
}

static QStringList normalised(const QStringList &arguments, const QString &workingDirectory)
{
    QStringList result;
    for (const QString &argument : arguments) {
        if (argument.startsWith(QLatin1Char('-')) || argument.contains(QLatin1String("://"))) {
            result.append(argument);
            continue;
        }
        const QFileInfo file(QDir(workingDirectory).absoluteFilePath(argument));
        result.append(file.exists() ? QUrl::fromLocalFile(file.absoluteFilePath()).toString() : argument);
    }
    return result;
}

int run(int &argc, char **argv, const Application &application, KLocalizedString (*displayName)())
{
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.lumo.desktop"));
    }
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(application.component);

    KAboutData about(QString::fromLatin1(application.component), displayName().toString(),
                     QStringLiteral(LUMO_APPS_VERSION), QString(), KAboutLicense::GPL_V2,
                     i18nc("@info:credit", "© 2026 Lumo"));
    about.setDesktopFileName(QString::fromLatin1(application.desktopFileName));
    about.setOrganizationDomain("lumo.invalid");
    KAboutData::setApplicationData(about);
    QApplication::setWindowIcon(QIcon::fromTheme(QString::fromLatin1(application.icon)));

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.addPositionalArgument(QStringLiteral("arguments"), i18n("Files or pages to open."), QStringLiteral("[arguments…]"));
    QCommandLineOption moduleArguments(QStringLiteral("args"), QString(), QStringLiteral("arguments"));
    moduleArguments.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOption(moduleArguments);
    QCommandLineOption firstRun(QStringLiteral("first-run"));
    firstRun.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOption(firstRun);
    QCommandLineOption whatsNew(QStringLiteral("whats-new"));
    whatsNew.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOption(whatsNew);
    QCommandLineOption kernelPanic(QStringLiteral("kernel-panic"));
    kernelPanic.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOption(kernelPanic);
    parser.process(app);
    about.processCommandLine(&parser);
    QStringList arguments = normalised(parser.positionalArguments(), QDir::currentPath());
    if (parser.isSet(firstRun)) {
        arguments.prepend(QStringLiteral("--first-run"));
    }
    if (parser.isSet(whatsNew)) {
        arguments.prepend(QStringLiteral("--whats-new"));
    }
    if (parser.isSet(kernelPanic)) {
        arguments.prepend(QStringLiteral("--kernel-panic"));
    }

    std::unique_ptr<KDBusService> service;
    if (application.unique) {
        service = std::make_unique<KDBusService>(KDBusService::Unique);
    }

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    if (application.setup) {
        application.setup(engine);
    }
    engine.rootContext()->setContextProperty(QStringLiteral("startArguments"), arguments);

    const QString file = interfaceFile(application);
    if (file.isEmpty()) {
        qCritical("%s: the interface is not installed", application.component);
        return 1;
    }
    engine.load(QUrl::fromLocalFile(file));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    if (service) {
        QObject::connect(service.get(), &KDBusService::activateRequested, &engine,
                         [&engine, &service, &application](const QStringList &received, const QString &workingDirectory) {
                             if (replacedOnDisk()) {
                                 const QString program = QStandardPaths::findExecutable(QString::fromLatin1(application.component));
                                 if (!program.isEmpty()) {
                                     service->unregister();
                                     QProcess::startDetached(program, received.mid(1), workingDirectory);
                                     QCoreApplication::quit();
                                     return;
                                 }
                             }
                             QObject *root = engine.rootObjects().value(0);
                             if (!root) {
                                 return;
                             }
                             const QStringList forwarded = normalised(received.mid(1), workingDirectory);
                             QMetaObject::invokeMethod(root, "handleArguments", Q_ARG(QVariant, QVariant(forwarded)));
                             const QVariant show = root->property("showOnActivate");
                             if (show.isValid() && !show.toBool()) {
                                 return;
                             }
                             if (auto *window = qobject_cast<QQuickWindow *>(root)) {
                                 window->show();
                                 window->raise();
                                 window->requestActivate();
                             }
                         });
    }
    return app.exec();
}

}
