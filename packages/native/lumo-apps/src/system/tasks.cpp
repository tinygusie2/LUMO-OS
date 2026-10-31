// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "tasks.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>

#include <KService>

#include <arpa/inet.h>
#include <cerrno>
#include <csignal>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <pwd.h>
#include <sys/resource.h>
#include <unistd.h>

static QByteArray readAll(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return QByteArray();
    }
    return file.readAll();
}

static QString readLine(const QString &path)
{
    return QString::fromUtf8(readAll(path)).trimmed();
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

Tasks::Tasks(QObject *parent)
    : QObject(parent)
{
}

QList<Tasks::CpuTimes> Tasks::readCpu() const
{
    QList<CpuTimes> result;
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/stat")).split('\n');
    for (const QByteArray &line : lines) {
        if (!line.startsWith("cpu")) {
            break;
        }
        CpuTimes times;
        const QList<QByteArray> fields = line.simplified().split(' ');
        for (int i = 1; i < fields.size() && i <= 8; ++i) {
            const quint64 value = fields.at(i).toULongLong();
            times.total += value;
            if (i != 4 && i != 5) {
                times.busy += value;
            }
        }
        result.append(times);
    }
    return result;
}

Tasks::Application Tasks::application(const QString &id)
{
    const auto cached = m_applications.constFind(id);
    if (cached != m_applications.constEnd()) {
        return cached.value();
    }
    Application app;
    KService::Ptr service = KService::serviceByDesktopName(id);
    if (!service) {
        service = KService::serviceByStorageId(id + QStringLiteral(".desktop"));
    }
    if (service && !service->name().isEmpty()) {
        app.name = service->name();
        app.icon = service->icon();
        app.found = true;
    }
    m_applications.insert(id, app);
    return app;
}

Tasks::Origin Tasks::readOrigin(const QString &base, int pid, quint64 started)
{
    const auto cached = m_origins.constFind(pid);
    if (cached != m_origins.constEnd() && cached->started == started) {
        return cached.value();
    }
    Origin origin;
    origin.started = started;
    const QList<QByteArray> lines = readAll(base + QStringLiteral("/cgroup")).split('\n');
    for (const QByteArray &line : lines) {
        if (!line.startsWith("0::")) {
            continue;
        }
        const QString path = QString::fromUtf8(line.mid(3)).trimmed();
        const QString unit = path.section(QLatin1Char('/'), -1);
        if (!unit.endsWith(QLatin1String(".service")) && !unit.endsWith(QLatin1String(".scope"))) {
            continue;
        }
        origin.unit = unit;
        if (unit.startsWith(QLatin1String("app-"))) {
            QString id = unit.mid(4).section(QLatin1Char('.'), 0, -2);
            const int at = id.indexOf(QLatin1Char('@'));
            if (at >= 0) {
                origin.autostarted = id.mid(at + 1) == QLatin1String("autostart");
                id = id.left(at);
            } else if (unit.endsWith(QLatin1String(".scope")) && id.lastIndexOf(QLatin1Char('-')) > 0) {
                id = id.left(id.lastIndexOf(QLatin1Char('-')));
            }
            if (id.startsWith(QLatin1String("flatpak-"))) {
                id = id.mid(8);
            }
            origin.app = unescapeUnit(id);
        }
    }
    m_origins.insert(pid, origin);
    return origin;
}

QString Tasks::userName(uid_t uid)
{
    const auto cached = m_users.constFind(uid);
    if (cached != m_users.constEnd()) {
        return cached.value();
    }
    const passwd *entry = getpwuid(uid);
    const QString name = entry ? QString::fromLocal8Bit(entry->pw_name) : QString::number(uid);
    m_users.insert(uid, name);
    return name;
}

QVariantList Tasks::readProcesses(quint64 elapsedTicks, int threads, double seconds, int &threadCount)
{
    QVariantList result;
    QHash<int, quint64> ticks;
    QHash<int, quint64> io;
    QHash<int, Origin> origins;
    const uid_t self = getuid();
    const long pageSize = sysconf(_SC_PAGESIZE);
    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        bool ok = false;
        const int pid = entry.toInt(&ok);
        if (!ok) {
            continue;
        }
        const QString base = QStringLiteral("/proc/") + entry;
        const QByteArray stat = readAll(base + QStringLiteral("/stat"));
        const int close = stat.lastIndexOf(')');
        if (close < 0) {
            continue;
        }
        const QList<QByteArray> fields = stat.mid(close + 2).split(' ');
        if (fields.size() < 22) {
            continue;
        }
        const quint64 used = fields.at(11).toULongLong() + fields.at(12).toULongLong();
        const qint64 rss = fields.at(21).toLongLong() * pageSize;
        const int threadsHere = fields.at(17).toInt();
        threadCount += threadsHere;
        ticks.insert(pid, used);
        if (rss <= 0) {
            continue;
        }

        uid_t owner = 0;
        qint64 memory = rss;
        const QByteArray status = readAll(base + QStringLiteral("/status"));
        const int uidAt = status.indexOf("\nUid:");
        if (uidAt >= 0) {
            owner = status.mid(uidAt + 5, status.indexOf('\n', uidAt + 1) - uidAt - 5).simplified().split(' ').value(0).toUInt();
        }
        const int anonAt = status.indexOf("\nRssAnon:");
        if (anonAt >= 0) {
            const qint64 anon = status.mid(anonAt + 9, status.indexOf('\n', anonAt + 1) - anonAt - 9).simplified().split(' ').value(0).toLongLong() * 1024;
            if (anon > 0) {
                memory = anon;
            }
        }

        QString name = QString::fromUtf8(stat.mid(stat.indexOf('(') + 1, close - stat.indexOf('(') - 1));
        QByteArray command = readAll(base + QStringLiteral("/cmdline"));
        const QString program = QString::fromUtf8(command.left(command.indexOf('\0')));
        if (!program.isEmpty()) {
            const QString file = program.section(QLatin1Char('/'), -1);
            if (file.startsWith(name) || name.size() >= 15) {
                name = file;
            }
        }
        command.replace('\0', ' ');

        double cpu = 0;
        if (m_primed && elapsedTicks > 0) {
            const quint64 before = m_processTicks.value(pid, used);
            cpu = qMin(100.0, 100.0 * double(used - qMin(used, before)) / (double(elapsedTicks) * threads));
        }

        double disk = -1;
        const QList<QByteArray> ioLines = readAll(base + QStringLiteral("/io")).split('\n');
        if (ioLines.size() > 5) {
            quint64 bytes = 0;
            for (const QByteArray &line : ioLines) {
                if (line.startsWith("read_bytes:") || line.startsWith("write_bytes:")) {
                    bytes += line.mid(line.indexOf(':') + 1).trimmed().toULongLong();
                }
            }
            io.insert(pid, bytes);
            disk = 0;
            if (m_primed && seconds > 0 && m_processIo.contains(pid)) {
                const quint64 before = m_processIo.value(pid);
                disk = double(bytes - qMin(bytes, before)) / seconds;
            }
        }

        const Origin origin = readOrigin(base, pid, fields.at(19).toULongLong());
        origins.insert(pid, origin);
        QString appName;
        QString appIcon;
        if (!origin.app.isEmpty()) {
            const Application app = application(origin.app);
            if (app.found) {
                appName = app.name;
                appIcon = app.icon;
            }
        }

        QVariantMap process;
        process.insert(QStringLiteral("pid"), pid);
        process.insert(QStringLiteral("ppid"), fields.at(1).toInt());
        process.insert(QStringLiteral("name"), name);
        process.insert(QStringLiteral("command"), QString::fromUtf8(command.trimmed()));
        process.insert(QStringLiteral("state"), QString::fromLatin1(fields.at(0)));
        process.insert(QStringLiteral("nice"), fields.at(16).toInt());
        process.insert(QStringLiteral("threads"), threadsHere);
        process.insert(QStringLiteral("cpu"), cpu);
        process.insert(QStringLiteral("memory"), memory);
        process.insert(QStringLiteral("disk"), disk);
        process.insert(QStringLiteral("user"), userName(owner));
        process.insert(QStringLiteral("mine"), owner == self);
        process.insert(QStringLiteral("unit"), origin.unit);
        process.insert(QStringLiteral("app"), appName.isEmpty() ? QString() : origin.app);
        process.insert(QStringLiteral("appName"), appName);
        process.insert(QStringLiteral("appIcon"), appIcon);
        process.insert(QStringLiteral("autostarted"), origin.autostarted);
        result.append(process);
    }
    m_processTicks = ticks;
    m_processIo = io;
    m_origins = origins;
    return result;
}

QVariantMap Tasks::readGpu() const
{
    const QStringList cards = QDir(QStringLiteral("/sys/class/drm")).entryList({QStringLiteral("card?")}, QDir::Dirs | QDir::System);
    int busy = -1;
    qint64 memoryUsed = -1;
    qint64 memoryTotal = -1;
    for (const QString &card : cards) {
        const QString device = QStringLiteral("/sys/class/drm/%1/device/").arg(card);
        bool ok = false;
        const int value = readLine(device + QStringLiteral("gpu_busy_percent")).toInt(&ok);
        if (ok && value >= busy) {
            busy = value;
            bool usedOk = false;
            bool totalOk = false;
            const qint64 used = readLine(device + QStringLiteral("mem_info_vram_used")).toLongLong(&usedOk);
            const qint64 total = readLine(device + QStringLiteral("mem_info_vram_total")).toLongLong(&totalOk);
            if (usedOk && totalOk && total > 0) {
                memoryUsed = used;
                memoryTotal = total;
            }
        }
    }
    return {{QStringLiteral("busy"), busy}, {QStringLiteral("memoryUsed"), memoryUsed}, {QStringLiteral("memoryTotal"), memoryTotal}};
}

QVariantList Tasks::readDisks(double seconds, quint64 &total)
{
    QVariantList result;
    QHash<QString, quint64> bytes;
    QHash<QString, quint64> busy;
    static const QRegularExpression whole(QStringLiteral("^(sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\\d+n\\d+|mmcblk\\d+)$"));
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/diskstats")).split('\n');
    for (const QByteArray &line : lines) {
        const QList<QByteArray> fields = line.simplified().split(' ');
        if (fields.size() < 13) {
            continue;
        }
        const QString name = QString::fromLatin1(fields.at(2));
        if (!whole.match(name).hasMatch()) {
            continue;
        }
        const QString block = QStringLiteral("/sys/block/") + name;
        const qint64 size = readLine(block + QStringLiteral("/size")).toLongLong() * 512;
        if (size <= 0) {
            continue;
        }
        const quint64 read = fields.at(5).toULongLong() * 512;
        const quint64 written = fields.at(9).toULongLong() * 512;
        const quint64 ticks = fields.at(12).toULongLong();
        bytes.insert(name + QStringLiteral(":r"), read);
        bytes.insert(name + QStringLiteral(":w"), written);
        busy.insert(name, ticks);
        total += read + written;

        double readRate = 0;
        double writeRate = 0;
        double active = 0;
        if (m_primed && seconds > 0 && m_diskTicks.contains(name)) {
            readRate = double(read - qMin(read, m_diskBytes.value(name + QStringLiteral(":r")))) / seconds;
            writeRate = double(written - qMin(written, m_diskBytes.value(name + QStringLiteral(":w")))) / seconds;
            active = qMin(100.0, double(ticks - qMin(ticks, m_diskTicks.value(name))) / (seconds * 10.0));
        }

        QString model = readLine(block + QStringLiteral("/device/model"));
        if (model.isEmpty()) {
            model = readLine(block + QStringLiteral("/device/name"));
        }
        QVariantMap disk;
        disk.insert(QStringLiteral("name"), name);
        disk.insert(QStringLiteral("model"), model.simplified());
        disk.insert(QStringLiteral("size"), size);
        disk.insert(QStringLiteral("ssd"), readLine(block + QStringLiteral("/queue/rotational")) == QLatin1String("0"));
        disk.insert(QStringLiteral("removable"), readLine(block + QStringLiteral("/removable")) == QLatin1String("1"));
        disk.insert(QStringLiteral("read"), readRate);
        disk.insert(QStringLiteral("write"), writeRate);
        disk.insert(QStringLiteral("active"), active);
        result.append(disk);
    }
    m_diskBytes = bytes;
    m_diskTicks = busy;
    return result;
}

QVariantList Tasks::readNetworks(double seconds, quint64 &received, quint64 &sent)
{
    QHash<QString, QStringList> addresses;
    ifaddrs *list = nullptr;
    if (getifaddrs(&list) == 0) {
        for (ifaddrs *item = list; item; item = item->ifa_next) {
            if (!item->ifa_addr) {
                continue;
            }
            char text[INET6_ADDRSTRLEN] = {};
            if (item->ifa_addr->sa_family == AF_INET) {
                inet_ntop(AF_INET, &reinterpret_cast<sockaddr_in *>(item->ifa_addr)->sin_addr, text, sizeof(text));
            } else if (item->ifa_addr->sa_family == AF_INET6) {
                inet_ntop(AF_INET6, &reinterpret_cast<sockaddr_in6 *>(item->ifa_addr)->sin6_addr, text, sizeof(text));
            } else {
                continue;
            }
            addresses[QString::fromLocal8Bit(item->ifa_name)].append(QString::fromLatin1(text));
        }
        freeifaddrs(list);
    }

    QVariantList result;
    QHash<QString, quint64> receivedNow;
    QHash<QString, quint64> sentNow;
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/net/dev")).split('\n');
    for (const QByteArray &line : lines) {
        const int colon = line.indexOf(':');
        if (colon < 0) {
            continue;
        }
        const QString name = QString::fromLatin1(line.left(colon).trimmed());
        const QString base = QStringLiteral("/sys/class/net/") + name;
        if (name == QLatin1String("lo") || !QFileInfo::exists(base + QStringLiteral("/device"))) {
            continue;
        }
        const QList<QByteArray> fields = line.mid(colon + 1).simplified().split(' ');
        if (fields.size() < 9) {
            continue;
        }
        const quint64 in = fields.at(0).toULongLong();
        const quint64 out = fields.at(8).toULongLong();
        receivedNow.insert(name, in);
        sentNow.insert(name, out);
        received += in;
        sent += out;

        double inRate = 0;
        double outRate = 0;
        if (m_primed && seconds > 0 && m_netReceived.contains(name)) {
            inRate = double(in - qMin(in, m_netReceived.value(name))) / seconds;
            outRate = double(out - qMin(out, m_netSent.value(name))) / seconds;
        }

        QVariantMap network;
        network.insert(QStringLiteral("name"), name);
        network.insert(QStringLiteral("wireless"), QFileInfo::exists(base + QStringLiteral("/wireless")));
        network.insert(QStringLiteral("connected"), readLine(base + QStringLiteral("/operstate")) == QLatin1String("up"));
        network.insert(QStringLiteral("speed"), readLine(base + QStringLiteral("/speed")).toInt());
        network.insert(QStringLiteral("hardware"), readLine(base + QStringLiteral("/address")));
        network.insert(QStringLiteral("addresses"), addresses.value(name));
        network.insert(QStringLiteral("received"), inRate);
        network.insert(QStringLiteral("sent"), outRate);
        result.append(network);
    }
    m_netReceived = receivedNow;
    m_netSent = sentNow;
    return result;
}

double Tasks::readSpeed() const
{
    const QStringList cpus = QDir(QStringLiteral("/sys/devices/system/cpu")).entryList({QStringLiteral("cpu[0-9]*")}, QDir::Dirs);
    double sum = 0;
    int count = 0;
    for (const QString &cpu : cpus) {
        bool ok = false;
        const double khz = readLine(QStringLiteral("/sys/devices/system/cpu/%1/cpufreq/scaling_cur_freq").arg(cpu)).toDouble(&ok);
        if (ok && khz > 0) {
            sum += khz / 1000.0;
            ++count;
        }
    }
    if (count > 0) {
        return sum / count;
    }
    static const QRegularExpression mhz(QStringLiteral("^cpu MHz\\s*:\\s*([0-9.]+)"), QRegularExpression::MultilineOption);
    QRegularExpressionMatchIterator matches = mhz.globalMatch(QString::fromLatin1(readAll(QStringLiteral("/proc/cpuinfo"))));
    while (matches.hasNext()) {
        sum += matches.next().captured(1).toDouble();
        ++count;
    }
    return count > 0 ? sum / count : 0;
}

QVariantMap Tasks::hardware() const
{
    QSet<QString> cores;
    QSet<QString> sockets;
    int logical = 0;
    const QString root = QStringLiteral("/sys/devices/system/cpu/");
    const QStringList cpus = QDir(root).entryList({QStringLiteral("cpu[0-9]*")}, QDir::Dirs);
    for (const QString &cpu : cpus) {
        const QString topology = root + cpu + QStringLiteral("/topology/");
        const QString package = readLine(topology + QStringLiteral("physical_package_id"));
        if (package.isEmpty()) {
            continue;
        }
        ++logical;
        sockets.insert(package);
        cores.insert(package + QLatin1Char(':') + readLine(topology + QStringLiteral("core_id")));
    }
    const QString cpuinfo = QString::fromLatin1(readAll(QStringLiteral("/proc/cpuinfo")));
    static const QRegularExpression flags(QStringLiteral("^flags\\s*:.*\\b(vmx|svm)\\b"), QRegularExpression::MultilineOption);

    QVariantMap result;
    result.insert(QStringLiteral("logical"), logical > 0 ? logical : int(sysconf(_SC_NPROCESSORS_ONLN)));
    result.insert(QStringLiteral("cores"), cores.size());
    result.insert(QStringLiteral("sockets"), sockets.size());
    result.insert(QStringLiteral("maxSpeed"), readLine(root + QStringLiteral("cpu0/cpufreq/cpuinfo_max_freq")).toDouble() / 1000.0);
    const QString cache = readLine(root + QStringLiteral("cpu0/cache/index3/size"));
    const qint64 unit = cache.endsWith(QLatin1Char('M')) ? 1024 * 1024 : cache.endsWith(QLatin1Char('K')) ? 1024 : 1;
    result.insert(QStringLiteral("cache"), QStringView(cache).left(cache.size() - (unit > 1 ? 1 : 0)).toLongLong() * unit);
    result.insert(QStringLiteral("virtualization"), flags.match(cpuinfo).hasMatch());
    return result;
}

QVariantMap Tasks::details(int pid) const
{
    const QString base = QStringLiteral("/proc/") + QString::number(pid);
    QVariantMap result;
    result.insert(QStringLiteral("exe"), QFileInfo(base + QStringLiteral("/exe")).symLinkTarget());
    result.insert(QStringLiteral("cwd"), QFileInfo(base + QStringLiteral("/cwd")).symLinkTarget());

    const QByteArray stat = readAll(base + QStringLiteral("/stat"));
    const QList<QByteArray> fields = stat.mid(stat.lastIndexOf(')') + 2).split(' ');
    quint64 boot = 0;
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/stat")).split('\n');
    for (const QByteArray &line : lines) {
        if (line.startsWith("btime ")) {
            boot = line.mid(6).trimmed().toULongLong();
        }
    }
    if (fields.size() > 19 && boot > 0) {
        const double started = double(boot) + fields.at(19).toDouble() / double(sysconf(_SC_CLK_TCK));
        result.insert(QStringLiteral("started"), QDateTime::fromMSecsSinceEpoch(qint64(started * 1000)));
    }
    for (const QByteArray &line : readAll(base + QStringLiteral("/cgroup")).split('\n')) {
        if (line.startsWith("0::")) {
            result.insert(QStringLiteral("cgroup"), QString::fromUtf8(line.mid(3)).trimmed());
        }
    }
    return result;
}

QVariantMap Tasks::sample()
{
    const qint64 elapsedMs = m_clock.isValid() ? qMax<qint64>(1, m_clock.restart()) : 0;
    if (!m_clock.isValid()) {
        m_clock.start();
    }
    const double seconds = elapsedMs / 1000.0;
    const int threads = qMax(1, int(sysconf(_SC_NPROCESSORS_ONLN)));

    const QList<CpuTimes> cpu = readCpu();
    const auto percent = [this](const CpuTimes &now, const CpuTimes &before) {
        const quint64 total = now.total - qMin(now.total, before.total);
        const quint64 busy = now.busy - qMin(now.busy, before.busy);
        return m_primed && total > 0 ? qMin(100.0, 100.0 * double(busy) / double(total)) : 0.0;
    };
    const CpuTimes overall = cpu.value(0);
    const CpuTimes overallBefore = m_cpu.value(0);
    const double cpuPercent = percent(overall, overallBefore);
    QVariantList cores;
    for (int i = 1; i < cpu.size(); ++i) {
        cores.append(percent(cpu.at(i), m_cpu.value(i)));
    }

    int threadCount = 0;
    const quint64 totalDelta = overall.total - qMin(overall.total, overallBefore.total);
    QVariantList processes = readProcesses(totalDelta / quint64(threads), threads, seconds, threadCount);

    QHash<QByteArray, qint64> memory;
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/meminfo")).split('\n');
    for (const QByteArray &line : lines) {
        const QList<QByteArray> fields = line.simplified().split(' ');
        if (fields.size() >= 2) {
            memory.insert(fields.at(0), fields.at(1).toLongLong() * 1024);
        }
    }
    const qint64 memTotal = memory.value("MemTotal:");
    const qint64 memAvailable = memory.value("MemAvailable:");

    quint64 diskTotal = 0;
    quint64 received = 0;
    quint64 sent = 0;
    const QVariantList disks = readDisks(seconds, diskTotal);
    const QVariantList networks = readNetworks(seconds, received, sent);
    double diskRate = 0;
    double receivedRate = 0;
    double sentRate = 0;
    for (const QVariant &disk : disks) {
        diskRate += disk.toMap().value(QStringLiteral("read")).toDouble() + disk.toMap().value(QStringLiteral("write")).toDouble();
    }
    for (const QVariant &network : networks) {
        receivedRate += network.toMap().value(QStringLiteral("received")).toDouble();
        sentRate += network.toMap().value(QStringLiteral("sent")).toDouble();
    }
    const QVariantMap gpu = readGpu();

    QVariantMap result;
    result.insert(QStringLiteral("cpu"), cpuPercent);
    result.insert(QStringLiteral("cores"), cores);
    result.insert(QStringLiteral("speed"), readSpeed());
    result.insert(QStringLiteral("threads"), threads);
    result.insert(QStringLiteral("processCount"), processes.size());
    result.insert(QStringLiteral("threadCount"), threadCount);
    result.insert(QStringLiteral("uptime"), readLine(QStringLiteral("/proc/uptime")).section(QLatin1Char(' '), 0, 0).toDouble());
    result.insert(QStringLiteral("memoryTotal"), memTotal);
    result.insert(QStringLiteral("memoryUsed"), memTotal - memAvailable);
    result.insert(QStringLiteral("memoryAvailable"), memAvailable);
    result.insert(QStringLiteral("memoryCached"), memory.value("Cached:") + memory.value("Buffers:"));
    result.insert(QStringLiteral("committed"), memory.value("Committed_AS:"));
    result.insert(QStringLiteral("commitLimit"), memory.value("CommitLimit:"));
    result.insert(QStringLiteral("swapTotal"), memory.value("SwapTotal:"));
    result.insert(QStringLiteral("swapUsed"), memory.value("SwapTotal:") - memory.value("SwapFree:"));
    result.insert(QStringLiteral("gpu"), gpu.value(QStringLiteral("busy")));
    result.insert(QStringLiteral("gpuMemoryUsed"), gpu.value(QStringLiteral("memoryUsed")));
    result.insert(QStringLiteral("gpuMemoryTotal"), gpu.value(QStringLiteral("memoryTotal")));
    result.insert(QStringLiteral("disk"), diskRate);
    result.insert(QStringLiteral("disks"), disks);
    result.insert(QStringLiteral("received"), receivedRate);
    result.insert(QStringLiteral("sent"), sentRate);
    result.insert(QStringLiteral("networks"), networks);
    result.insert(QStringLiteral("processes"), processes);

    m_cpu = cpu;
    m_primed = true;
    return result;
}

bool Tasks::end(int pid, bool force)
{
    if (pid <= 1 || pid == getpid()) {
        return false;
    }
    return ::kill(pid, force ? SIGKILL : SIGTERM) == 0;
}

QVariantList Tasks::endAll(const QVariantList &pids, bool force)
{
    QVariantList refused;
    for (const QVariant &value : pids) {
        const int pid = value.toInt();
        if (pid <= 1 || pid == getpid()) {
            continue;
        }
        if (::kill(pid, force ? SIGKILL : SIGTERM) != 0 && errno == EPERM) {
            refused.append(pid);
        }
    }
    return refused;
}

QVariantList Tasks::setEfficiency(const QVariantList &pids, bool on)
{
    QVariantList refused;
    for (const QVariant &value : pids) {
        const int pid = value.toInt();
        if (pid <= 1) {
            continue;
        }
        const QStringList tasks = QDir(QStringLiteral("/proc/%1/task").arg(pid)).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &task : tasks) {
            const int tid = task.toInt();
            if (tid > 0 && setpriority(PRIO_PROCESS, id_t(tid), on ? 19 : 0) != 0 && (errno == EACCES || errno == EPERM)) {
                refused.append(tid);
            }
        }
    }
    return refused;
}
