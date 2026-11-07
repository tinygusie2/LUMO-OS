// SPDX-FileCopyrightText: 2026 Lumo Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class TerminalColours : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(QString colour READ colour WRITE setColour NOTIFY colourChanged)
    Q_PROPERTY(QVariantMap colours READ colours NOTIFY coloursChanged)

public:
    explicit TerminalColours(QObject *parent = nullptr);

    bool dark() const;
    void setDark(bool dark);
    QString colour() const;
    void setColour(const QString &colour);
    QVariantMap colours() const;

    static QVariantMap parse(const QByteArray &toml);

Q_SIGNALS:
    void darkChanged();
    void colourChanged();
    void coloursChanged();

private:
    void reload();
    QString userFile() const;
    QString systemFile() const;

    bool m_dark = true;
    QString m_colour = QStringLiteral("lumo");
    QVariantMap m_colours;
    QFileSystemWatcher m_watcher;
};
