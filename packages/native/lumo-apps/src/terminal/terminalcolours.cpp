// SPDX-FileCopyrightText: 2026 Lumo Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "terminalcolours.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>

TerminalColours::TerminalColours(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &TerminalColours::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &TerminalColours::reload);
    reload();
}

bool TerminalColours::dark() const
{
    return m_dark;
}

void TerminalColours::setDark(bool dark)
{
    if (m_dark == dark) {
        return;
    }
    m_dark = dark;
    Q_EMIT darkChanged();
    reload();
}

QString TerminalColours::colour() const
{
    return m_colour;
}

void TerminalColours::setColour(const QString &colour)
{
    if (m_colour == colour || colour.isEmpty()) {
        return;
    }
    m_colour = colour;
    Q_EMIT colourChanged();
    reload();
}

QVariantMap TerminalColours::colours() const
{
    return m_colours;
}

QString TerminalColours::userFile() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/alacritty/lumo-colors.toml");
}

QString TerminalColours::systemFile() const
{
    const QString name = m_dark ? QStringLiteral("dark.toml") : QStringLiteral("light.toml");
    const QString variant = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("lumo/terminal/%1/%2").arg(m_colour, name));
    if (!variant.isEmpty()) {
        return variant;
    }
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("lumo/terminal/") + name);
}

void TerminalColours::reload()
{
    const QString user = userFile();
    const QString folder = QFileInfo(user).absolutePath();
    QDir().mkpath(folder);
    if (!m_watcher.directories().contains(folder)) {
        m_watcher.addPath(folder);
    }
    if (QFileInfo::exists(user) && !m_watcher.files().contains(user)) {
        m_watcher.addPath(user);
    }

    QVariantMap result;
    for (const QString &path : {user, systemFile()}) {
        QFile file(path);
        if (path.isEmpty() || !file.open(QIODevice::ReadOnly)) {
            continue;
        }
        result = parse(file.readAll());
        if (!result.isEmpty()) {
            break;
        }
    }
    if (result != m_colours) {
        m_colours = result;
        Q_EMIT coloursChanged();
    }
}

QVariantMap TerminalColours::parse(const QByteArray &toml)
{
    static const QStringList names = {QStringLiteral("black"), QStringLiteral("red"), QStringLiteral("green"), QStringLiteral("yellow"),
                                      QStringLiteral("blue"), QStringLiteral("magenta"), QStringLiteral("cyan"), QStringLiteral("white")};
    QVariantMap result;
    QVariantList palette;
    for (int i = 0; i < 16; ++i) {
        palette.append(QVariant());
    }
    QString section;
    bool complete = true;
    for (const QByteArray &raw : toml.split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1Char('['))) {
            section = line.mid(1, line.indexOf(QLatin1Char(']')) - 1).trimmed();
            continue;
        }
        const int equals = line.indexOf(QLatin1Char('='));
        if (equals < 0) {
            continue;
        }
        const QString key = line.left(equals).trimmed();
        QString value = line.mid(equals + 1).trimmed();
        value.remove(QLatin1Char('"'));
        const QColor colour(value);
        if (!colour.isValid()) {
            continue;
        }
        if (section == QLatin1String("colors.primary")) {
            result.insert(key, colour);
        } else if (section == QLatin1String("colors.cursor")) {
            result.insert(key == QLatin1String("cursor") ? QStringLiteral("cursor") : QStringLiteral("cursorText"), colour);
        } else if (section == QLatin1String("colors.selection")) {
            result.insert(key == QLatin1String("background") ? QStringLiteral("selection") : QStringLiteral("selectionText"), colour);
        } else if (section == QLatin1String("colors.normal") || section == QLatin1String("colors.bright")) {
            const int index = names.indexOf(key);
            if (index >= 0) {
                palette[index + (section == QLatin1String("colors.bright") ? 8 : 0)] = colour;
            }
        }
    }
    for (const QVariant &entry : std::as_const(palette)) {
        complete = complete && entry.isValid();
    }
    if (!complete || !result.contains(QStringLiteral("background")) || !result.contains(QStringLiteral("foreground"))) {
        return {};
    }
    result.insert(QStringLiteral("palette"), palette);
    return result;
}
