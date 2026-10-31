// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class Focus : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Focus(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList running(const QStringList &storageIds) const;
    Q_INVOKABLE QVariantList block(const QStringList &storageIds);

private:
    struct Target {
        QString storageId;
        QString desktopName;
        QString program;
        QString name;
        QString icon;
    };

    QList<Target> targets(const QStringList &storageIds) const;
    QHash<QString, QList<int>> match(const QList<Target> &targets) const;
};
