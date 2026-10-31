// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <sys/types.h>

class Tasks : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Tasks(QObject *parent = nullptr);

    Q_INVOKABLE QVariantMap sample();
    Q_INVOKABLE QVariantMap hardware() const;
    Q_INVOKABLE QVariantMap details(int pid) const;
    Q_INVOKABLE bool end(int pid, bool force = false);
    Q_INVOKABLE QVariantList endAll(const QVariantList &pids, bool force = false);
    Q_INVOKABLE QVariantList setEfficiency(const QVariantList &pids, bool on);

private:
    struct CpuTimes {
        quint64 busy = 0;
        quint64 total = 0;
    };

    struct Origin {
        quint64 started = 0;
        QString unit;
        QString app;
        bool autostarted = false;
    };

    struct Application {
        QString name;
        QString icon;
        bool found = false;
    };

    QList<CpuTimes> readCpu() const;
    QVariantList readProcesses(quint64 elapsedTicks, int threads, double seconds, int &threadCount);
    Origin readOrigin(const QString &base, int pid, quint64 started);
    Application application(const QString &id);
    QString userName(uid_t uid);
    QVariantMap readGpu() const;
    QVariantList readDisks(double seconds, quint64 &total);
    QVariantList readNetworks(double seconds, quint64 &received, quint64 &sent);
    double readSpeed() const;

    QList<CpuTimes> m_cpu;
    QHash<int, quint64> m_processTicks;
    QHash<int, quint64> m_processIo;
    QHash<int, Origin> m_origins;
    QHash<QString, Application> m_applications;
    QHash<uid_t, QString> m_users;
    QHash<QString, quint64> m_diskBytes;
    QHash<QString, quint64> m_diskTicks;
    QHash<QString, quint64> m_netReceived;
    QHash<QString, quint64> m_netSent;
    QElapsedTimer m_clock;
    bool m_primed = false;
};
