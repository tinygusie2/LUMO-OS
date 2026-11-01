// SPDX-FileCopyrightText: 2026 Lumo Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#include "terminalview.h"

#include <QClipboard>
#include <QCursor>
#include <QFileInfo>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QPainter>
#include <QPalette>
#include <QDir>
#include <QSocketNotifier>
#include <QStandardPaths>
#include <QUrl>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <pwd.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace
{
constexpr int HistoryLimit = 10000;

VTermScreenCell blankCell()
{
    VTermScreenCell cell;
    std::memset(&cell, 0, sizeof(cell));
    cell.width = 1;
    cell.fg.type = VTERM_COLOR_DEFAULT_FG;
    cell.bg.type = VTERM_COLOR_DEFAULT_BG;
    return cell;
}

bool isWordCharacter(uint32_t c)
{
    if (c == 0) {
        return false;
    }
    const QChar character = c < 0x10000 ? QChar(char16_t(c)) : QChar(u'a');
    return character.isLetterOrNumber() || QStringLiteral("-_./~:@%+").contains(character);
}
}

TerminalView::TerminalView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setFlag(ItemAcceptsInputMethod, true);
    setFlag(ItemIsFocusScope, false);
    setActiveFocusOnTab(true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setCursor(QCursor(Qt::IBeamCursor));
    setAntialiasing(true);

    m_font.setFamilies({QStringLiteral("Hack"), QStringLiteral("DejaVu Sans Mono"), QStringLiteral("monospace")});
    m_font.setStyleHint(QFont::Monospace);
    m_font.setPointSizeF(11);
    m_font.setKerning(false);

    m_background = QGuiApplication::palette().color(QPalette::Base);
    m_foreground = QGuiApplication::palette().color(QPalette::Text);
    m_cursorColour = m_foreground;
    m_cursorText = m_background;
    m_selection = m_foreground;
    m_selectionText = m_background;
    for (QColor &colour : m_palette) {
        colour = m_foreground;
    }

    m_vterm = vterm_new(m_rows, m_columns);
    vterm_set_utf8(m_vterm, 1);
    vterm_output_set_callback(m_vterm, &TerminalView::onOutput, this);
    m_state = vterm_obtain_state(m_vterm);
    m_screen = vterm_obtain_screen(m_vterm);

    static VTermScreenCallbacks callbacks = [] {
        VTermScreenCallbacks c;
        std::memset(&c, 0, sizeof(c));
        c.damage = &TerminalView::onDamage;
        c.moverect = &TerminalView::onMoveRect;
        c.movecursor = &TerminalView::onMoveCursor;
        c.settermprop = &TerminalView::onTermProp;
        c.bell = &TerminalView::onBell;
        c.sb_pushline = &TerminalView::onPushLine;
        c.sb_popline = &TerminalView::onPopLine;
        c.sb_clear = &TerminalView::onClearHistory;
        return c;
    }();
    static VTermStateFallbacks fallbacks = [] {
        VTermStateFallbacks f;
        std::memset(&f, 0, sizeof(f));
        f.osc = &TerminalView::onOsc;
        return f;
    }();
    vterm_screen_set_callbacks(m_screen, &callbacks, this);
    vterm_screen_set_unrecognised_fallbacks(m_screen, &fallbacks, this);
    vterm_screen_set_damage_merge(m_screen, VTERM_DAMAGE_SCROLL);
    vterm_screen_enable_altscreen(m_screen, 1);
    vterm_screen_reset(m_screen, 1);
    m_cursorShape = VTERM_PROP_CURSORSHAPE_BAR_LEFT;

    m_blink.setInterval(530);
    connect(&m_blink, &QTimer::timeout, this, [this] {
        m_blinkOn = !m_blinkOn;
        update();
    });

    updateMetrics();
}

TerminalView::~TerminalView()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
    }
    if (m_pid > 0) {
        ::kill(m_pid, SIGHUP);
        ::waitpid(m_pid, nullptr, WNOHANG);
    }
    if (m_master >= 0) {
        ::close(m_master);
    }
    vterm_free(m_vterm);
}

QString TerminalView::fontFamily() const
{
    return m_font.family();
}

void TerminalView::setFontFamily(const QString &family)
{
    if (family.isEmpty() || m_font.family() == family) {
        return;
    }
    QStringList families = m_font.families();
    families.removeAll(family);
    families.prepend(family);
    m_font.setFamilies(families);
    updateMetrics();
    Q_EMIT fontChanged();
}

qreal TerminalView::fontSize() const
{
    return m_font.pointSizeF();
}

void TerminalView::setFontSize(qreal size)
{
    size = qBound<qreal>(6, size, 48);
    if (qFuzzyCompare(m_font.pointSizeF(), size)) {
        return;
    }
    m_font.setPointSizeF(size);
    updateMetrics();
    Q_EMIT fontChanged();
}

QVariantMap TerminalView::colours() const
{
    return m_colourMap;
}

void TerminalView::setColours(const QVariantMap &colours)
{
    m_colourMap = colours;
    auto take = [&colours](const char *key, const QColor &fallback) {
        const QColor colour = colours.value(QString::fromLatin1(key)).value<QColor>();
        return colour.isValid() ? colour : fallback;
    };
    m_background = take("background", m_background);
    m_foreground = take("foreground", m_foreground);
    m_cursorColour = take("cursor", m_foreground);
    m_cursorText = take("cursorText", m_background);
    m_selection = take("selection", m_foreground);
    m_selectionText = take("selectionText", m_background);
    const QVariantList palette = colours.value(QStringLiteral("palette")).toList();
    for (int i = 0; i < 16 && i < palette.size(); ++i) {
        const QColor colour = palette.at(i).value<QColor>();
        if (colour.isValid()) {
            m_palette[i] = colour;
        }
    }
    Q_EMIT coloursChanged();
    update();
}

QString TerminalView::title() const
{
    return m_title;
}

QString TerminalView::workingDirectory() const
{
    return m_workingDirectory;
}

bool TerminalView::running() const
{
    return m_pid > 0;
}

bool TerminalView::hasSelection() const
{
    return m_hasSelection;
}

int TerminalView::columns() const
{
    return m_columns;
}

int TerminalView::rows() const
{
    return m_rows;
}

int TerminalView::historySize() const
{
    return int(m_history.size());
}

int TerminalView::scrollOffset() const
{
    return m_scrollOffset;
}

void TerminalView::setScrollOffset(int offset)
{
    offset = qBound(0, offset, int(m_history.size()));
    if (offset == m_scrollOffset) {
        return;
    }
    m_scrollOffset = offset;
    Q_EMIT historyChanged();
    update();
}

bool TerminalView::start(const QString &directory, const QStringList &command)
{
    if (m_pid > 0) {
        return false;
    }

    QString folder = directory;
    if (folder.startsWith(QLatin1String("file:"))) {
        folder = QUrl(folder).toLocalFile();
    }
    if (folder.isEmpty()) {
        folder = QDir::currentPath();
        if (folder == QLatin1String("/")) {
            folder.clear();
        }
    }
    if (folder.isEmpty() || !QFileInfo(folder).isDir()) {
        folder = QDir::homePath();
    }

    QStringList program = command;
    if (program.isEmpty()) {
        const passwd *entry = ::getpwuid(::getuid());
        QString shell = entry && entry->pw_shell && *entry->pw_shell ? QString::fromLocal8Bit(entry->pw_shell) : QStringLiteral("/bin/bash");
        if (!QFileInfo(shell).isExecutable()) {
            shell = QStringLiteral("/bin/bash");
        }
        program << shell;
        const QString rc = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("lumo/terminal/lumo.bashrc"));
        if (QFileInfo(shell).fileName() == QLatin1String("bash") && !rc.isEmpty()) {
            program << QStringLiteral("--rcfile") << rc;
        }
        program << QStringLiteral("-i");
    }

    std::vector<QByteArray> storage;
    for (const QString &argument : std::as_const(program)) {
        storage.push_back(argument.toLocal8Bit());
    }
    std::vector<char *> arguments;
    for (QByteArray &argument : storage) {
        arguments.push_back(argument.data());
    }
    arguments.push_back(nullptr);
    const QByteArray folderBytes = folder.toLocal8Bit();

    winsize size{};
    size.ws_row = m_rows;
    size.ws_col = m_columns;
    size.ws_xpixel = m_columns * m_cellWidth;
    size.ws_ypixel = m_rows * m_cellHeight;

    int master = -1;
    const pid_t pid = ::forkpty(&master, nullptr, nullptr, &size);
    if (pid < 0) {
        return false;
    }
    if (pid == 0) {
        ::setenv("TERM", "xterm-256color", 1);
        ::setenv("COLORTERM", "truecolor", 1);
        ::setenv("TERM_PROGRAM", "lumo-terminal", 1);
        ::unsetenv("COLUMNS");
        ::unsetenv("LINES");
        if (::chdir(folderBytes.constData()) != 0) {
            [[maybe_unused]] int ignored = ::chdir("/");
        }
        ::signal(SIGPIPE, SIG_DFL);
        ::execvp(arguments[0], arguments.data());
        ::_exit(127);
    }

    m_master = master;
    m_pid = pid;
    ::fcntl(m_master, F_SETFL, ::fcntl(m_master, F_GETFL) | O_NONBLOCK);
    ::fcntl(m_master, F_SETFD, FD_CLOEXEC);
    m_notifier = new QSocketNotifier(m_master, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &TerminalView::readOutput);
    m_workingDirectory = folder;
    Q_EMIT workingDirectoryChanged();
    Q_EMIT runningChanged();
    restartBlink();
    return true;
}

void TerminalView::readOutput()
{
    char buffer[65536];
    for (int round = 0; round < 16; ++round) {
        const ssize_t count = ::read(m_master, buffer, sizeof(buffer));
        if (count > 0) {
            vterm_input_write(m_vterm, buffer, size_t(count));
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EINTR)) {
            break;
        }
        vterm_screen_flush_damage(m_screen);
        childFinished();
        return;
    }
    vterm_screen_flush_damage(m_screen);
}

void TerminalView::childFinished()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    int status = 0;
    int code = 0;
    if (m_pid > 0 && ::waitpid(m_pid, &status, 0) == m_pid) {
        code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
    m_pid = -1;
    if (m_master >= 0) {
        ::close(m_master);
        m_master = -1;
    }
    m_blink.stop();
    Q_EMIT runningChanged();
    Q_EMIT finished(code);
    update();
}

void TerminalView::writeBytes(const char *bytes, size_t length)
{
    if (m_master < 0) {
        return;
    }
    size_t written = 0;
    while (written < length) {
        const ssize_t count = ::write(m_master, bytes + written, length - written);
        if (count > 0) {
            written += size_t(count);
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && errno == EAGAIN) {
            pollfd descriptor{m_master, POLLOUT, 0};
            if (::poll(&descriptor, 1, 1000) > 0) {
                continue;
            }
        }
        break;
    }
}

void TerminalView::onOutput(const char *bytes, size_t length, void *user)
{
    static_cast<TerminalView *>(user)->writeBytes(bytes, length);
}

void TerminalView::scheduleUpdate()
{
    if (m_updatePending) {
        return;
    }
    m_updatePending = true;
    QTimer::singleShot(0, this, [this] {
        m_updatePending = false;
        update();
    });
}

int TerminalView::onDamage(VTermRect, void *user)
{
    static_cast<TerminalView *>(user)->scheduleUpdate();
    return 1;
}

int TerminalView::onMoveRect(VTermRect, VTermRect, void *user)
{
    static_cast<TerminalView *>(user)->scheduleUpdate();
    return 1;
}

int TerminalView::onMoveCursor(VTermPos pos, VTermPos, int visible, void *user)
{
    auto *self = static_cast<TerminalView *>(user);
    self->m_cursor = pos;
    self->m_cursorVisible = visible;
    self->scheduleUpdate();
    return 1;
}

int TerminalView::onTermProp(VTermProp prop, VTermValue *value, void *user)
{
    auto *self = static_cast<TerminalView *>(user);
    switch (prop) {
    case VTERM_PROP_TITLE:
        if (value->string.initial) {
            self->m_titleBuffer.clear();
        }
        self->m_titleBuffer.append(value->string.str, value->string.len);
        if (value->string.final) {
            const QString title = QString::fromUtf8(self->m_titleBuffer);
            if (title != self->m_title) {
                self->m_title = title;
                Q_EMIT self->titleChanged();
            }
        }
        break;
    case VTERM_PROP_CURSORVISIBLE:
        self->m_cursorVisible = value->boolean;
        break;
    case VTERM_PROP_CURSORBLINK:
        self->m_cursorBlinks = value->boolean;
        self->restartBlink();
        break;
    case VTERM_PROP_CURSORSHAPE:
        self->m_cursorShape = value->number;
        break;
    case VTERM_PROP_ALTSCREEN:
        self->m_altScreen = value->boolean;
        self->m_scrollOffset = 0;
        Q_EMIT self->historyChanged();
        break;
    case VTERM_PROP_MOUSE:
        self->m_mouseMode = value->number;
        break;
    default:
        break;
    }
    self->scheduleUpdate();
    return 1;
}

int TerminalView::onBell(void *user)
{
    Q_EMIT static_cast<TerminalView *>(user)->bell();
    return 1;
}

int TerminalView::onPushLine(int cols, const VTermScreenCell *cells, void *user)
{
    auto *self = static_cast<TerminalView *>(user);
    self->m_history.emplace_back(cells, cells + cols);
    ++self->m_pushed;
    if (int(self->m_history.size()) > HistoryLimit) {
        self->m_history.pop_front();
    }
    if (self->m_scrollOffset > 0) {
        self->m_scrollOffset = qMin(self->m_scrollOffset + 1, int(self->m_history.size()));
    }
    Q_EMIT self->historyChanged();
    return 1;
}

int TerminalView::onPopLine(int cols, VTermScreenCell *cells, void *user)
{
    auto *self = static_cast<TerminalView *>(user);
    if (self->m_history.empty()) {
        return 0;
    }
    const std::vector<VTermScreenCell> &line = self->m_history.back();
    const VTermScreenCell blank = blankCell();
    for (int i = 0; i < cols; ++i) {
        cells[i] = i < int(line.size()) ? line[i] : blank;
    }
    self->m_history.pop_back();
    --self->m_pushed;
    self->m_scrollOffset = qMin(self->m_scrollOffset, int(self->m_history.size()));
    Q_EMIT self->historyChanged();
    return 1;
}

int TerminalView::onClearHistory(void *user)
{
    static_cast<TerminalView *>(user)->clearHistory();
    return 1;
}

int TerminalView::onOsc(int command, VTermStringFragment fragment, void *user)
{
    if (command != 7) {
        return 0;
    }
    auto *self = static_cast<TerminalView *>(user);
    if (fragment.initial) {
        self->m_oscBuffer.clear();
    }
    self->m_oscBuffer.append(fragment.str, fragment.len);
    if (fragment.final) {
        const QUrl url(QString::fromUtf8(self->m_oscBuffer));
        const QString folder = url.scheme() == QLatin1String("file") ? url.path() : QString();
        if (!folder.isEmpty() && folder != self->m_workingDirectory) {
            self->m_workingDirectory = folder;
            Q_EMIT self->workingDirectoryChanged();
        }
    }
    return 1;
}

void TerminalView::clearHistory()
{
    m_history.clear();
    m_scrollOffset = 0;
    Q_EMIT historyChanged();
    update();
}

void TerminalView::updateMetrics()
{
    const QFontMetricsF metrics(m_font);
    m_cellWidth = qMax<qreal>(1, metrics.horizontalAdvance(QLatin1Char('M')));
    m_cellHeight = qMax<qreal>(1, std::ceil(metrics.height() * 1.15));
    m_ascent = metrics.ascent() + (m_cellHeight - metrics.height()) / 2;
    updateGrid();
    update();
}

void TerminalView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        updateGrid();
    }
}

void TerminalView::updateGrid()
{
    if (width() <= 0 || height() <= 0) {
        return;
    }
    const int columns = qMax(2, int(width() / m_cellWidth));
    const int rows = qMax(1, int(height() / m_cellHeight));
    if (columns == m_columns && rows == m_rows) {
        return;
    }
    m_columns = columns;
    m_rows = rows;
    vterm_set_size(m_vterm, m_rows, m_columns);
    vterm_screen_flush_damage(m_screen);
    if (m_master >= 0) {
        winsize size{};
        size.ws_row = m_rows;
        size.ws_col = m_columns;
        size.ws_xpixel = m_columns * m_cellWidth;
        size.ws_ypixel = m_rows * m_cellHeight;
        ::ioctl(m_master, TIOCSWINSZ, &size);
    }
    Q_EMIT gridChanged();
    update();
}

long long TerminalView::firstLine() const
{
    return m_pushed - (long long)m_history.size();
}

long long TerminalView::visibleLine(int row) const
{
    return m_pushed - m_scrollOffset + row;
}

bool TerminalView::cellAt(long long line, int column, VTermScreenCell &cell) const
{
    if (column < 0 || column >= m_columns) {
        return false;
    }
    if (line >= m_pushed) {
        const int row = int(line - m_pushed);
        if (row >= m_rows) {
            return false;
        }
        return vterm_screen_get_cell(m_screen, VTermPos{row, column}, &cell);
    }
    const long long index = line - firstLine();
    if (index < 0) {
        return false;
    }
    const std::vector<VTermScreenCell> &stored = m_history[size_t(index)];
    cell = column < int(stored.size()) ? stored[size_t(column)] : blankCell();
    return true;
}

QColor TerminalView::resolve(const VTermColor &colour, bool foreground) const
{
    if (foreground && VTERM_COLOR_IS_DEFAULT_FG(&colour)) {
        return m_foreground;
    }
    if (!foreground && VTERM_COLOR_IS_DEFAULT_BG(&colour)) {
        return m_background;
    }
    if (VTERM_COLOR_IS_INDEXED(&colour)) {
        if (colour.indexed.idx < 16) {
            return m_palette[colour.indexed.idx];
        }
        VTermColor converted = colour;
        vterm_screen_convert_color_to_rgb(m_screen, &converted);
        return QColor(converted.rgb.red, converted.rgb.green, converted.rgb.blue);
    }
    if (VTERM_COLOR_IS_RGB(&colour)) {
        return QColor(colour.rgb.red, colour.rgb.green, colour.rgb.blue);
    }
    return foreground ? m_foreground : m_background;
}

bool TerminalView::isSelected(long long line, int column) const
{
    if (!m_hasSelection) {
        return false;
    }
    QPoint from = m_anchor;
    QPoint to = m_head;
    if (to.y() < from.y() || (to.y() == from.y() && to.x() < from.x())) {
        std::swap(from, to);
    }
    const long long base = firstLine();
    const long long start = base + from.y();
    const long long end = base + to.y();
    if (line < start || line > end) {
        return false;
    }
    if (line == start && column < from.x()) {
        return false;
    }
    if (line == end && column > to.x()) {
        return false;
    }
    return true;
}

void TerminalView::paint(QPainter *painter)
{
    painter->fillRect(boundingRect(), m_background);
    painter->setFont(m_font);

    QFont bold = m_font;
    bold.setBold(true);
    QFont italic = m_font;
    italic.setItalic(true);
    QFont boldItalic = bold;
    boldItalic.setItalic(true);

    for (int row = 0; row < m_rows; ++row) {
        const long long line = visibleLine(row);
        const qreal y = row * m_cellHeight;
        int column = 0;
        while (column < m_columns) {
            VTermScreenCell cell;
            if (!cellAt(line, column, cell)) {
                break;
            }
            if (cell.chars[0] == uint32_t(-1)) {
                ++column;
                continue;
            }
            const int span = qMax(1, int(cell.width));
            QColor foreground = resolve(cell.fg, true);
            QColor background = resolve(cell.bg, false);
            if (cell.attrs.bold && VTERM_COLOR_IS_INDEXED(&cell.fg) && cell.fg.indexed.idx < 8) {
                foreground = m_palette[cell.fg.indexed.idx + 8];
            }
            if (cell.attrs.reverse) {
                std::swap(foreground, background);
            }
            if (isSelected(line, column)) {
                foreground = m_selectionText;
                background = m_selection;
            }
            const QRectF rect(column * m_cellWidth, y, span * m_cellWidth, m_cellHeight);
            if (background != m_background) {
                painter->fillRect(rect, background);
            }
            if (cell.chars[0] != 0 && cell.chars[0] != ' ' && !cell.attrs.conceal) {
                QString text;
                for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; ++i) {
                    const char32_t character = cell.chars[i];
                    text.append(QString::fromUcs4(&character, 1));
                }
                painter->setFont(cell.attrs.bold ? (cell.attrs.italic ? boldItalic : bold) : (cell.attrs.italic ? italic : m_font));
                painter->setPen(foreground);
                painter->drawText(QPointF(rect.x(), y + m_ascent), text);
            }
            if (cell.attrs.underline) {
                painter->fillRect(QRectF(rect.x(), y + m_ascent + 2, rect.width(), 1), foreground);
            }
            if (cell.attrs.strike) {
                painter->fillRect(QRectF(rect.x(), y + m_cellHeight / 2, rect.width(), 1), foreground);
            }
            column += span;
        }
    }

    const bool showCursor = m_cursorVisible && m_scrollOffset == 0 && m_pid > 0;
    if (!showCursor) {
        return;
    }
    const QRectF cell(m_cursor.col * m_cellWidth, m_cursor.row * m_cellHeight, m_cellWidth, m_cellHeight);
    if (!hasActiveFocus()) {
        painter->setPen(QPen(m_cursorColour, 1));
        painter->setBrush(Qt::NoBrush);
        painter->drawRect(cell.adjusted(0.5, 0.5, -0.5, -0.5));
        return;
    }
    if (!m_blinkOn) {
        return;
    }
    if (m_cursorShape == VTERM_PROP_CURSORSHAPE_BLOCK) {
        painter->fillRect(cell, m_cursorColour);
        VTermScreenCell under;
        if (vterm_screen_get_cell(m_screen, m_cursor, &under) && under.chars[0] && under.chars[0] != ' ') {
            const char32_t character = under.chars[0];
            painter->setFont(m_font);
            painter->setPen(m_cursorText);
            painter->drawText(QPointF(cell.x(), cell.y() + m_ascent), QString::fromUcs4(&character, 1));
        }
    } else if (m_cursorShape == VTERM_PROP_CURSORSHAPE_UNDERLINE) {
        painter->fillRect(QRectF(cell.x(), cell.bottom() - 2, cell.width(), 2), m_cursorColour);
    } else {
        painter->fillRect(QRectF(cell.x(), cell.y() + 1, 2, cell.height() - 2), m_cursorColour);
    }
}

void TerminalView::restartBlink()
{
    m_blinkOn = true;
    if (m_cursorBlinks && hasActiveFocus() && m_pid > 0) {
        m_blink.start();
    } else {
        m_blink.stop();
    }
    update();
}

VTermModifier TerminalView::modifiers(Qt::KeyboardModifiers modifiers) const
{
    int result = VTERM_MOD_NONE;
    if (modifiers & Qt::ShiftModifier) {
        result |= VTERM_MOD_SHIFT;
    }
    if (modifiers & Qt::AltModifier) {
        result |= VTERM_MOD_ALT;
    }
    if (modifiers & Qt::ControlModifier) {
        result |= VTERM_MOD_CTRL;
    }
    return VTermModifier(result);
}

bool TerminalView::event(QEvent *event)
{
    if (event->type() == QEvent::ShortcutOverride) {
        auto *key = static_cast<QKeyEvent *>(event);
        const Qt::KeyboardModifiers mods = key->modifiers() & ~Qt::KeypadModifier;
        const bool shiftCtrl = mods == (Qt::ControlModifier | Qt::ShiftModifier);
        if (!shiftCtrl && key->key() != Qt::Key_Tab && key->key() != Qt::Key_Backtab
            && !(mods == Qt::ControlModifier && (key->key() == Qt::Key_Plus || key->key() == Qt::Key_Equal || key->key() == Qt::Key_Minus || key->key() == Qt::Key_0))) {
            event->accept();
            return true;
        }
    }
    if (event->type() == QEvent::KeyPress) {
        auto *key = static_cast<QKeyEvent *>(event);
        if (key->key() == Qt::Key_Tab || key->key() == Qt::Key_Backtab) {
            if (!(key->modifiers() & Qt::ControlModifier)) {
                keyPressEvent(key);
                return true;
            }
        }
    }
    return QQuickPaintedItem::event(event);
}

void TerminalView::keyPressEvent(QKeyEvent *event)
{
    const Qt::KeyboardModifiers mods = event->modifiers() & ~Qt::KeypadModifier;
    const bool ctrl = mods & Qt::ControlModifier;
    const bool shift = mods & Qt::ShiftModifier;
    const int key = event->key();

    if ((ctrl && shift && key == Qt::Key_C) || (ctrl && !shift && key == Qt::Key_C && m_hasSelection) || (ctrl && key == Qt::Key_Insert)) {
        copy();
        clearSelection();
        return;
    }
    if ((ctrl && key == Qt::Key_V) || (shift && key == Qt::Key_Insert)) {
        paste();
        return;
    }
    if (shift && !ctrl && (key == Qt::Key_PageUp || key == Qt::Key_PageDown)) {
        setScrollOffset(m_scrollOffset + (key == Qt::Key_PageUp ? 1 : -1) * qMax(1, m_rows - 1));
        return;
    }
    if (ctrl && shift && (key == Qt::Key_Home || key == Qt::Key_End)) {
        setScrollOffset(key == Qt::Key_Home ? int(m_history.size()) : 0);
        return;
    }
    if (ctrl && shift && key == Qt::Key_A) {
        selectAll();
        return;
    }

    const VTermModifier modifier = modifiers(mods);
    VTermKey special = VTERM_KEY_NONE;
    switch (key) {
    case Qt::Key_Return:
    case Qt::Key_Enter:
        special = VTERM_KEY_ENTER;
        break;
    case Qt::Key_Tab:
    case Qt::Key_Backtab:
        special = VTERM_KEY_TAB;
        break;
    case Qt::Key_Backspace:
        special = VTERM_KEY_BACKSPACE;
        break;
    case Qt::Key_Escape:
        special = VTERM_KEY_ESCAPE;
        break;
    case Qt::Key_Up:
        special = VTERM_KEY_UP;
        break;
    case Qt::Key_Down:
        special = VTERM_KEY_DOWN;
        break;
    case Qt::Key_Left:
        special = VTERM_KEY_LEFT;
        break;
    case Qt::Key_Right:
        special = VTERM_KEY_RIGHT;
        break;
    case Qt::Key_Insert:
        special = VTERM_KEY_INS;
        break;
    case Qt::Key_Delete:
        special = VTERM_KEY_DEL;
        break;
    case Qt::Key_Home:
        special = VTERM_KEY_HOME;
        break;
    case Qt::Key_End:
        special = VTERM_KEY_END;
        break;
    case Qt::Key_PageUp:
        special = VTERM_KEY_PAGEUP;
        break;
    case Qt::Key_PageDown:
        special = VTERM_KEY_PAGEDOWN;
        break;
    default:
        if (key >= Qt::Key_F1 && key <= Qt::Key_F12) {
            special = VTermKey(VTERM_KEY_FUNCTION(key - Qt::Key_F1 + 1));
        }
        break;
    }

    if (special != VTERM_KEY_NONE) {
        VTermModifier keyModifier = modifier;
        if (key == Qt::Key_Backtab) {
            keyModifier = VTermModifier(keyModifier | VTERM_MOD_SHIFT);
        }
        vterm_keyboard_key(m_vterm, special, keyModifier);
    } else if (ctrl && key >= Qt::Key_A && key <= Qt::Key_Z) {
        vterm_keyboard_unichar(m_vterm, uint32_t('a' + (key - Qt::Key_A)), VTermModifier(modifier & ~VTERM_MOD_SHIFT));
    } else if (ctrl && (key == Qt::Key_Space || key == Qt::Key_At)) {
        writeBytes("\0", 1);
    } else if (!event->text().isEmpty()) {
        const QList<uint> characters = event->text().toUcs4();
        for (uint character : characters) {
            if (character < 0x20 || character == 0x7f) {
                const char byte = char(character);
                writeBytes(&byte, 1);
            } else {
                vterm_keyboard_unichar(m_vterm, character, VTermModifier(modifier & ~(VTERM_MOD_SHIFT | VTERM_MOD_CTRL)));
            }
        }
    } else {
        QQuickPaintedItem::keyPressEvent(event);
        return;
    }

    if (m_hasSelection) {
        clearSelection();
    }
    setScrollOffset(0);
    restartBlink();
    event->accept();
}

void TerminalView::inputMethodEvent(QInputMethodEvent *event)
{
    if (!event->commitString().isEmpty()) {
        sendText(event->commitString());
        setScrollOffset(0);
    }
    event->accept();
}

QVariant TerminalView::inputMethodQuery(Qt::InputMethodQuery query) const
{
    switch (query) {
    case Qt::ImEnabled:
        return true;
    case Qt::ImCursorRectangle:
        return QRectF(m_cursor.col * m_cellWidth, m_cursor.row * m_cellHeight, m_cellWidth, m_cellHeight);
    case Qt::ImFont:
        return m_font;
    case Qt::ImHints:
        return int(Qt::ImhNoPredictiveText | Qt::ImhNoAutoUppercase);
    default:
        return QQuickPaintedItem::inputMethodQuery(query);
    }
}

void TerminalView::sendText(const QString &text)
{
    const QList<uint> characters = text.toUcs4();
    for (uint character : characters) {
        if (character == '\n') {
            vterm_keyboard_key(m_vterm, VTERM_KEY_ENTER, VTERM_MOD_NONE);
        } else if (character < 0x20) {
            const char byte = char(character);
            writeBytes(&byte, 1);
        } else {
            vterm_keyboard_unichar(m_vterm, character, VTERM_MOD_NONE);
        }
    }
}

QPoint TerminalView::gridPosition(const QPointF &point) const
{
    const int column = qBound(0, int(point.x() / m_cellWidth), m_columns - 1);
    const int row = qBound(0, int(point.y() / m_cellHeight), m_rows - 1);
    return QPoint(column, int(visibleLine(row) - firstLine()));
}

bool TerminalView::mouseReporting(const QMouseEvent *event) const
{
    return m_mouseMode != VTERM_PROP_MOUSE_NONE && !(event->modifiers() & Qt::ShiftModifier) && m_scrollOffset == 0;
}

static int vtermButton(Qt::MouseButton button)
{
    switch (button) {
    case Qt::LeftButton:
        return 1;
    case Qt::MiddleButton:
        return 2;
    case Qt::RightButton:
        return 3;
    default:
        return 0;
    }
}

void TerminalView::mousePressEvent(QMouseEvent *event)
{
    forceActiveFocus(Qt::MouseFocusReason);
    if (mouseReporting(event)) {
        const int row = qBound(0, int(event->position().y() / m_cellHeight), m_rows - 1);
        const int column = qBound(0, int(event->position().x() / m_cellWidth), m_columns - 1);
        vterm_mouse_move(m_vterm, row, column, modifiers(event->modifiers()));
        vterm_mouse_button(m_vterm, vtermButton(event->button()), true, modifiers(event->modifiers()));
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton) {
        Q_EMIT contextMenuRequested(event->position().x(), event->position().y());
        event->accept();
        return;
    }
    if (event->button() == Qt::MiddleButton) {
        const QString text = QGuiApplication::clipboard()->text(QClipboard::Selection);
        if (!text.isEmpty()) {
            vterm_keyboard_start_paste(m_vterm);
            sendText(text);
            vterm_keyboard_end_paste(m_vterm);
        }
        event->accept();
        return;
    }
    if (event->button() == Qt::LeftButton) {
        if (event->modifiers() & Qt::ShiftModifier && m_hasSelection) {
            m_head = gridPosition(event->position());
        } else {
            m_anchor = gridPosition(event->position());
            m_head = m_anchor;
            if (m_hasSelection) {
                m_hasSelection = false;
                Q_EMIT selectionChanged();
            }
        }
        m_pressPosition = event->position().toPoint();
        m_selecting = true;
        update();
    }
    event->accept();
}

void TerminalView::mouseMoveEvent(QMouseEvent *event)
{
    if (mouseReporting(event)) {
        const int row = qBound(0, int(event->position().y() / m_cellHeight), m_rows - 1);
        const int column = qBound(0, int(event->position().x() / m_cellWidth), m_columns - 1);
        vterm_mouse_move(m_vterm, row, column, modifiers(event->modifiers()));
        return;
    }
    if (!m_selecting) {
        return;
    }
    if (event->position().y() < 0) {
        setScrollOffset(m_scrollOffset + 1);
    } else if (event->position().y() > height()) {
        setScrollOffset(m_scrollOffset - 1);
    }
    m_head = gridPosition(event->position());
    const bool selection = m_head != m_anchor || (event->position().toPoint() - m_pressPosition).manhattanLength() > m_cellWidth / 2;
    if (selection != m_hasSelection) {
        m_hasSelection = selection;
        Q_EMIT selectionChanged();
    }
    update();
}

void TerminalView::mouseReleaseEvent(QMouseEvent *event)
{
    if (mouseReporting(event)) {
        vterm_mouse_button(m_vterm, vtermButton(event->button()), false, modifiers(event->modifiers()));
        return;
    }
    m_selecting = false;
    if (m_hasSelection) {
        QGuiApplication::clipboard()->setText(selectedText(), QClipboard::Selection);
    }
}

void TerminalView::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (mouseReporting(event) || event->button() != Qt::LeftButton) {
        mousePressEvent(event);
        return;
    }
    selectWord(gridPosition(event->position()));
    m_selecting = false;
}

void TerminalView::selectWord(const QPoint &position)
{
    const long long line = firstLine() + position.y();
    auto character = [this, line](int column) -> uint32_t {
        VTermScreenCell cell;
        return cellAt(line, column, cell) ? cell.chars[0] : 0;
    };
    if (!isWordCharacter(character(position.x()))) {
        return;
    }
    int from = position.x();
    int to = position.x();
    while (from > 0 && isWordCharacter(character(from - 1))) {
        --from;
    }
    while (to < m_columns - 1 && isWordCharacter(character(to + 1))) {
        ++to;
    }
    m_anchor = QPoint(from, position.y());
    m_head = QPoint(to, position.y());
    m_hasSelection = true;
    Q_EMIT selectionChanged();
    QGuiApplication::clipboard()->setText(selectedText(), QClipboard::Selection);
    update();
}

void TerminalView::wheelEvent(QWheelEvent *event)
{
    const qreal steps = event->angleDelta().y() / 40.0 + m_wheelRemainder;
    const int lines = int(steps);
    m_wheelRemainder = steps - lines;
    if (lines == 0) {
        event->accept();
        return;
    }
    if (m_mouseMode != VTERM_PROP_MOUSE_NONE && !(event->modifiers() & Qt::ShiftModifier)) {
        const int row = qBound(0, int(event->position().y() / m_cellHeight), m_rows - 1);
        const int column = qBound(0, int(event->position().x() / m_cellWidth), m_columns - 1);
        vterm_mouse_move(m_vterm, row, column, VTERM_MOD_NONE);
        for (int i = 0; i < std::abs(lines); ++i) {
            vterm_mouse_button(m_vterm, lines > 0 ? 4 : 5, true, VTERM_MOD_NONE);
        }
    } else if (m_altScreen) {
        for (int i = 0; i < std::abs(lines); ++i) {
            vterm_keyboard_key(m_vterm, lines > 0 ? VTERM_KEY_UP : VTERM_KEY_DOWN, VTERM_MOD_NONE);
        }
    } else {
        setScrollOffset(m_scrollOffset + lines);
    }
    event->accept();
}

void TerminalView::focusInEvent(QFocusEvent *event)
{
    QQuickPaintedItem::focusInEvent(event);
    vterm_state_focus_in(m_state);
    restartBlink();
}

void TerminalView::focusOutEvent(QFocusEvent *event)
{
    QQuickPaintedItem::focusOutEvent(event);
    vterm_state_focus_out(m_state);
    restartBlink();
}

QString TerminalView::lineText(long long line, int from, int to) const
{
    QString text;
    for (int column = from; column <= to && column < m_columns; ++column) {
        VTermScreenCell cell;
        if (!cellAt(line, column, cell)) {
            break;
        }
        if (cell.chars[0] == uint32_t(-1)) {
            continue;
        }
        if (cell.chars[0] == 0) {
            text.append(QLatin1Char(' '));
            continue;
        }
        for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; ++i) {
            const char32_t character = cell.chars[i];
            text.append(QString::fromUcs4(&character, 1));
        }
    }
    while (text.endsWith(QLatin1Char(' '))) {
        text.chop(1);
    }
    return text;
}

QString TerminalView::selectedText() const
{
    if (!m_hasSelection) {
        return {};
    }
    QPoint from = m_anchor;
    QPoint to = m_head;
    if (to.y() < from.y() || (to.y() == from.y() && to.x() < from.x())) {
        std::swap(from, to);
    }
    QStringList lines;
    const long long base = firstLine();
    for (int y = from.y(); y <= to.y(); ++y) {
        lines.append(lineText(base + y, y == from.y() ? from.x() : 0, y == to.y() ? to.x() : m_columns - 1));
    }
    return lines.join(QLatin1Char('\n'));
}

QString TerminalView::screenText() const
{
    QStringList lines;
    for (int row = 0; row < m_rows; ++row) {
        lines.append(lineText(m_pushed + row, 0, m_columns - 1));
    }
    while (!lines.isEmpty() && lines.last().isEmpty()) {
        lines.removeLast();
    }
    return lines.join(QLatin1Char('\n'));
}

void TerminalView::copy()
{
    if (m_hasSelection) {
        QGuiApplication::clipboard()->setText(selectedText());
    }
}

void TerminalView::paste()
{
    QString text = QGuiApplication::clipboard()->text();
    if (text.isEmpty()) {
        return;
    }
    text.replace(QLatin1String("\r\n"), QLatin1String("\r"));
    text.replace(QLatin1Char('\n'), QLatin1Char('\r'));
    vterm_keyboard_start_paste(m_vterm);
    const QByteArray bytes = text.toUtf8();
    writeBytes(bytes.constData(), size_t(bytes.size()));
    vterm_keyboard_end_paste(m_vterm);
    setScrollOffset(0);
}

void TerminalView::selectAll()
{
    m_anchor = QPoint(0, 0);
    m_head = QPoint(m_columns - 1, int(m_pushed - firstLine()) + m_rows - 1);
    m_hasSelection = true;
    Q_EMIT selectionChanged();
    update();
}

void TerminalView::clearSelection()
{
    if (!m_hasSelection) {
        return;
    }
    m_hasSelection = false;
    Q_EMIT selectionChanged();
    update();
}
