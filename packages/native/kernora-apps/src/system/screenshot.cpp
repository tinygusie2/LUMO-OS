// SPDX-FileCopyrightText: 2026 Kernora Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "screenshot.h"

#include "dbus.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJSEngine>
#include <QLocale>
#include <QPainter>
#include <QPainterPath>
#include <QSocketNotifier>
#include <QStandardPaths>

#include <KLocalizedString>

#include <cerrno>
#include <functional>
#include <memory>

#include <fcntl.h>
#include <unistd.h>

namespace
{
class PipeReader : public QObject
{
public:
    PipeReader(int fd, std::function<void(QByteArray)> done, QObject *parent)
        : QObject(parent)
        , m_fd(fd)
        , m_done(std::move(done))
        , m_notifier(fd, QSocketNotifier::Read)
    {
        connect(&m_notifier, &QSocketNotifier::activated, this, [this]() {
            char buffer[65536];
            for (;;) {
                const ssize_t n = ::read(m_fd, buffer, sizeof(buffer));
                if (n > 0) {
                    m_data.append(buffer, n);
                    continue;
                }
                if (n < 0 && (errno == EAGAIN || errno == EINTR)) {
                    return;
                }
                m_notifier.setEnabled(false);
                ::close(m_fd);
                m_done(m_data);
                deleteLater();
                return;
            }
        });
    }

private:
    int m_fd;
    std::function<void(QByteArray)> m_done;
    QSocketNotifier m_notifier;
    QByteArray m_data;
};
}

Screenshot::Screenshot(QObject *parent)
    : QObject(parent)
{
}

QString Screenshot::temporaryFile() const
{
    const QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    return QStringLiteral("%1/kernora-screenshot-%2-%3.png").arg(runtime).arg(QCoreApplication::applicationPid()).arg(m_counter);
}

void Screenshot::deliver(const QJSValue &callback, bool ok, const QVariant &first, int width, int height)
{
    if (!callback.isCallable() || !qjsEngine(this)) {
        return;
    }
    QJSValue function = callback;
    if (ok) {
        function.call({QJSValue(true), qjsEngine(this)->toScriptValue(first), QJSValue(width), QJSValue(height)});
    } else {
        function.call({QJSValue(false), QJSValue(first.toString())});
    }
}

void Screenshot::capture(const QString &method, const QVariantList &arguments, const QJSValue &callback)
{
    int fds[2];
    if (pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
        deliver(callback, false, i18n("The screenshot could not be started."));
        return;
    }
    QVariantList all = arguments;
    all.append(QVariant::fromValue(QDBusUnixFileDescriptor(fds[1])));
    ::close(fds[1]);

    struct Result {
        QByteArray pixels;
        QVariantMap meta;
        bool havePixels = false;
        bool haveMeta = false;
        bool failed = false;
    };
    auto result = std::make_shared<Result>();
    const int counter = ++m_counter;
    auto finish = [this, result, callback, counter]() {
        if (result->failed || !result->havePixels || !result->haveMeta) {
            return;
        }
        const int width = result->meta.value(QStringLiteral("width")).toInt();
        const int height = result->meta.value(QStringLiteral("height")).toInt();
        const int stride = result->meta.value(QStringLiteral("stride")).toInt();
        const auto format = static_cast<QImage::Format>(result->meta.value(QStringLiteral("format")).toInt());
        if (width <= 0 || height <= 0 || result->pixels.size() < qsizetype(stride) * height) {
            deliver(callback, false, i18n("The screenshot came back empty."));
            return;
        }
        QImage image(reinterpret_cast<const uchar *>(result->pixels.constData()), width, height, stride, format);
        const QString path = QStringLiteral("%1/kernora-screenshot-%2-%3.png")
                                 .arg(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation))
                                 .arg(QCoreApplication::applicationPid())
                                 .arg(counter);
        image.save(path, "PNG", 80);
        deliver(callback, true, QUrl::fromLocalFile(path), width, height);
    };

    new PipeReader(fds[0], [result, finish](const QByteArray &data) {
        result->pixels = data;
        result->havePixels = true;
        finish();
    }, this);

    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                          QStringLiteral("org.kde.KWin.ScreenShot2"), method);
    message.setArguments(all);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 5 * 60 * 1000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, result, callback, finish](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusMessage reply = self->reply();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            result->failed = true;
            deliver(callback, false, reply.errorMessage());
            return;
        }
        result->meta = DBus::toJs(reply.arguments().value(0)).toMap();
        result->haveMeta = true;
        finish();
    });
}

static QVariantMap options(bool cursor)
{
    return {{QStringLiteral("include-cursor"), cursor},
            {QStringLiteral("include-decoration"), true},
            {QStringLiteral("include-shadow"), false},
            {QStringLiteral("native-resolution"), true}};
}

void Screenshot::captureWorkspace(bool cursor, const QJSValue &callback)
{
    capture(QStringLiteral("CaptureWorkspace"), {options(cursor)}, callback);
}

void Screenshot::captureActiveWindow(bool cursor, const QJSValue &callback)
{
    capture(QStringLiteral("CaptureActiveWindow"), {options(cursor)}, callback);
}

void Screenshot::captureActiveScreen(bool cursor, const QJSValue &callback)
{
    capture(QStringLiteral("CaptureActiveScreen"), {options(cursor)}, callback);
}

void Screenshot::captureScreen(const QString &name, bool cursor, const QJSValue &callback)
{
    capture(QStringLiteral("CaptureScreen"), {name, options(cursor)}, callback);
}

bool Screenshot::owned(const QString &path) const
{
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    const QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    return path.startsWith(pictures + QLatin1Char('/')) || path.startsWith(runtime + QStringLiteral("/kernora-screenshot-"));
}

bool Screenshot::discard(const QUrl &image)
{
    const QString path = image.toLocalFile();
    if (!owned(path)) {
        return false;
    }
    return QFile::remove(path);
}

void Screenshot::captureInteractive(int kind, bool cursor, const QJSValue &callback)
{
    capture(QStringLiteral("CaptureInteractive"), {static_cast<uint>(kind), options(cursor)}, callback);
}

QUrl Screenshot::crop(const QUrl &image, int x, int y, int width, int height)
{
    QImage source(image.toLocalFile());
    if (source.isNull() || width <= 0 || height <= 0) {
        return image;
    }
    const QImage cropped = source.copy(x, y, width, height);
    ++m_counter;
    const QString path = temporaryFile();
    cropped.save(path, "PNG", 80);
    return QUrl::fromLocalFile(path);
}

QUrl Screenshot::cropShape(const QUrl &image, const QVariantList &points)
{
    QImage source(image.toLocalFile());
    if (source.isNull() || points.size() < 6) {
        return image;
    }
    QPainterPath path;
    path.moveTo(points.at(0).toReal(), points.at(1).toReal());
    for (qsizetype i = 2; i + 1 < points.size(); i += 2) {
        path.lineTo(points.at(i).toReal(), points.at(i + 1).toReal());
    }
    path.closeSubpath();
    const QRect bounds = path.boundingRect().toAlignedRect().intersected(source.rect());
    if (bounds.width() < 2 || bounds.height() < 2) {
        return image;
    }
    QImage shaped(bounds.size(), QImage::Format_ARGB32_Premultiplied);
    shaped.fill(Qt::transparent);
    QPainter painter(&shaped);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.translate(-bounds.topLeft());
    painter.setClipPath(path);
    painter.drawImage(0, 0, source);
    painter.end();
    ++m_counter;
    const QString file = temporaryFile();
    shaped.save(file, "PNG", 80);
    return QUrl::fromLocalFile(file);
}

bool Screenshot::annotate(const QUrl &source, const QUrl &target, const QVariantList &strokes)
{
    QImage image(source.toLocalFile());
    const QString path = target.toLocalFile();
    if (image.isNull() || !owned(path)) {
        return false;
    }
    image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    for (const QVariant &entry : strokes) {
        const QVariantMap stroke = entry.toMap();
        const QVariantList points = stroke.value(QStringLiteral("points")).toList();
        if (points.size() < 2) {
            continue;
        }
        const bool highlighter = stroke.value(QStringLiteral("highlighter")).toBool();
        QColor color(stroke.value(QStringLiteral("color")).toString());
        if (highlighter) {
            color.setAlphaF(0.4);
        }
        QPen pen(color, stroke.value(QStringLiteral("width")).toReal(), Qt::SolidLine, highlighter ? Qt::SquareCap : Qt::RoundCap, Qt::RoundJoin);
        painter.setPen(pen);
        painter.setBrush(Qt::NoBrush);
        QPainterPath line;
        line.moveTo(points.at(0).toReal(), points.at(1).toReal());
        if (points.size() < 4) {
            line.lineTo(points.at(0).toReal() + 0.01, points.at(1).toReal());
        }
        for (qsizetype i = 2; i + 1 < points.size(); i += 2) {
            line.lineTo(points.at(i).toReal(), points.at(i + 1).toReal());
        }
        painter.drawPath(line);
    }
    painter.end();
    return image.save(path, "PNG");
}

QUrl Screenshot::save(const QUrl &image)
{
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/")
        + i18nc("folder name for screenshots", "Screenshots");
    QDir().mkpath(folder);
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss"));
    QString path = QStringLiteral("%1/%2_%3.png").arg(folder, i18nc("file name prefix", "Screenshot"), stamp);
    for (int i = 2; QFile::exists(path); ++i) {
        path = QStringLiteral("%1/%2_%3 (%4).png").arg(folder, i18nc("file name prefix", "Screenshot"), stamp).arg(i);
    }
    if (!QFile::copy(image.toLocalFile(), path)) {
        return QUrl();
    }
    return QUrl::fromLocalFile(path);
}

void Screenshot::copyToClipboard(const QUrl &image)
{
    QGuiApplication::clipboard()->setImage(QImage(image.toLocalFile()));
}
