// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "focus.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>

#include <KService>
#include <KShell>

#include <csignal>
#include <sys/stat.h>
#include <unistd.h>

static QByteArray readAll(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return QByteArray();
    }
    return file.readAll();
}

static QString unescapeUnit(const QString &text)
{
    QString result;
    for (int i = 0; i < text.size(); ++i) {
        if (text.at(i) == QLatin1Char('\\') && i + 3 < text.size() && text.at(i + 1) == QLatin1Char('x')) {
            bool ok = false;
            const int code = text.mid(i + 2, 2).toInt(&ok, 16);
            if (ok) {
                result.append(QChar(code));
                i += 3;
                continue;
            }
        }
        result.append(text.at(i));
    }
    return result;
}

static QString unitApplication(const QByteArray &cgroup)
{
    const QList<QByteArray> lines = cgroup.split('\n');
    for (const QByteArray &line : lines) {
        if (!line.startsWith("0::")) {
            continue;
        }
        const QString unit = QString::fromUtf8(line.mid(3)).trimmed().section(QLatin1Char('/'), -1);
        if (!unit.startsWith(QLatin1String("app-"))
            || (!unit.endsWith(QLatin1String(".service")) && !unit.endsWith(QLatin1String(".scope")))) {
            return QString();
        }
        QString id = unit.mid(4).section(QLatin1Char('.'), 0, -2);
        const int at = id.indexOf(QLatin1Char('@'));
        if (at >= 0) {
            id = id.left(at);
        } else if (unit.endsWith(QLatin1String(".scope")) && id.lastIndexOf(QLatin1Char('-')) > 0) {
            id = id.left(id.lastIndexOf(QLatin1Char('-')));
        }
        if (id.startsWith(QLatin1String("flatpak-"))) {
            id = id.mid(8);
        }
        return unescapeUnit(id);
    }
    return QString();
}

static QString programOf(const QString &exec)
{
    static const QSet<QString> launchers{
        QStringLiteral("env"), QStringLiteral("flatpak"), QStringLiteral("sh"), QStringLiteral("bash"),
        QStringLiteral("dash"), QStringLiteral("python"), QStringLiteral("python3"), QStringLiteral("perl"),
        QStringLiteral("java"), QStringLiteral("snap"), QStringLiteral("kioclient"), QStringLiteral("kioclient5"),
        QStringLiteral("xdg-open"), QStringLiteral("gtk-launch"), QStringLiteral("kstart"), QStringLiteral("kstart5"),
        QStringLiteral("pkexec"), QStringLiteral("sudo"),
    };
    const QStringList words = KShell::splitArgs(exec);
    for (const QString &word : words) {
        if (word.contains(QLatin1Char('=')) && !word.startsWith(QLatin1Char('/'))) {
            continue;
        }
        const QString program = QFileInfo(word).fileName();
        if (program == QLatin1String("env")) {
            continue;
        }
        return launchers.contains(program) ? QString() : program;
    }
    return QString();
}

Focus::Focus(QObject *parent)
    : QObject(parent)
{
}

QList<Focus::Target> Focus::targets(const QStringList &storageIds) const
{
    QList<Target> result;
    for (const QString &storageId : storageIds) {
        KService::Ptr service = KService::serviceByStorageId(storageId);
        if (!service) {
            continue;
        }
        Target target;
        target.desktopName = service->desktopEntryName();
        target.program = programOf(service->exec());
        target.name = service->name();
        target.icon = service->icon();
        QString bare = storageId;
        if (bare.endsWith(QLatin1String(".desktop"))) {
            bare.chop(8);
        }
        if (bare.startsWith(QLatin1String("org.lumo.focus")) || bare.startsWith(QLatin1String("org.lumo.settings"))) {
            continue;
        }
        target.storageId = bare;
        result.append(target);
    }
    return result;
}

QHash<QString, QList<int>> Focus::match(const QList<Target> &targets) const
{
    QHash<QString, QList<int>> found;
    if (targets.isEmpty()) {
        return found;
    }
    const uid_t self = getuid();
    const pid_t own = getpid();
    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        bool ok = false;
        const int pid = entry.toInt(&ok);
        if (!ok || pid <= 1 || pid == own) {
            continue;
        }
        const QString base = QStringLiteral("/proc/") + entry;
        struct stat info;
        if (::stat(QFile::encodeName(base).constData(), &info) != 0 || info.st_uid != self) {
            continue;
        }
        const QString unitApp = unitApplication(readAll(base + QStringLiteral("/cgroup")));
        const QString exe = QFileInfo(QFile::symLinkTarget(base + QStringLiteral("/exe"))).fileName();
        const QByteArray command = readAll(base + QStringLiteral("/cmdline"));
        const QString first = QFileInfo(QString::fromUtf8(command.left(command.indexOf('\0')))).fileName();
        if (unitApp.startsWith(QLatin1String("org.lumo.focus"))) {
            continue;
        }
        for (const Target &target : targets) {
            const bool byUnit = !unitApp.isEmpty()
                && (unitApp == target.storageId || unitApp == target.desktopName);
            const bool byProgram = !target.program.isEmpty() && (exe == target.program || first == target.program);
            if (byUnit || byProgram) {
                found[target.storageId].append(pid);
                break;
            }
        }
    }
    return found;
}

QVariantList Focus::running(const QStringList &storageIds) const
{
    const QList<Target> wanted = targets(storageIds);
    const QHash<QString, QList<int>> found = match(wanted);
    QVariantList result;
    for (const Target &target : wanted) {
        if (found.contains(target.storageId)) {
            result.append(QVariantMap{{QStringLiteral("storageId"), QString(target.storageId + QStringLiteral(".desktop"))},
                                      {QStringLiteral("name"), target.name},
                                      {QStringLiteral("icon"), target.icon}});
        }
    }
    return result;
}

QVariantList Focus::block(const QStringList &storageIds)
{
    const QList<Target> wanted = targets(storageIds);
    const QHash<QString, QList<int>> found = match(wanted);
    QVariantList result;
    for (const Target &target : wanted) {
        const auto pids = found.constFind(target.storageId);
        if (pids == found.constEnd()) {
            continue;
        }
        bool ended = false;
        for (const int pid : pids.value()) {
            ended = ::kill(pid, SIGTERM) == 0 || ended;
        }
        if (ended) {
            result.append(QVariantMap{{QStringLiteral("storageId"), QString(target.storageId + QStringLiteral(".desktop"))},
                                      {QStringLiteral("name"), target.name},
                                      {QStringLiteral("icon"), target.icon}});
        }
    }
    return result;
}
