// SPDX-FileCopyrightText: 2026 Lumo Developers
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QColor>
#include <QFont>
#include <QPoint>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <deque>
#include <vector>

extern "C" {
#include <vterm.h>
}

class QSocketNotifier;

class TerminalView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontChanged)
    Q_PROPERTY(qreal fontSize READ fontSize WRITE setFontSize NOTIFY fontChanged)
    Q_PROPERTY(QVariantMap colours READ colours WRITE setColours NOTIFY coloursChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString workingDirectory READ workingDirectory NOTIFY workingDirectoryChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(int columns READ columns NOTIFY gridChanged)
    Q_PROPERTY(int rows READ rows NOTIFY gridChanged)
    Q_PROPERTY(int historySize READ historySize NOTIFY historyChanged)
    Q_PROPERTY(int scrollOffset READ scrollOffset WRITE setScrollOffset NOTIFY historyChanged)

public:
    explicit TerminalView(QQuickItem *parent = nullptr);
    ~TerminalView() override;

    QString fontFamily() const;
    void setFontFamily(const QString &family);
    qreal fontSize() const;
    void setFontSize(qreal size);
    QVariantMap colours() const;
    void setColours(const QVariantMap &colours);
    QString title() const;
    QString workingDirectory() const;
    bool running() const;
    bool hasSelection() const;
    int columns() const;
    int rows() const;
    int historySize() const;
    int scrollOffset() const;
    void setScrollOffset(int offset);

    Q_INVOKABLE bool start(const QString &directory, const QStringList &command = {});
    Q_INVOKABLE void copy();
    Q_INVOKABLE void paste();
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void sendText(const QString &text);
    Q_INVOKABLE QString selectedText() const;
    Q_INVOKABLE QString screenText() const;

    void paint(QPainter *painter) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;

Q_SIGNALS:
    void fontChanged();
    void coloursChanged();
    void titleChanged();
    void workingDirectoryChanged();
    void runningChanged();
    void selectionChanged();
    void gridChanged();
    void historyChanged();
    void finished(int exitCode);
    void bell();
    void contextMenuRequested(qreal x, qreal y);

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    bool event(QEvent *event) override;

private:
    static int onDamage(VTermRect rect, void *user);
    static int onMoveRect(VTermRect dest, VTermRect src, void *user);
    static int onMoveCursor(VTermPos pos, VTermPos oldpos, int visible, void *user);
    static int onTermProp(VTermProp prop, VTermValue *value, void *user);
    static int onBell(void *user);
    static int onPushLine(int cols, const VTermScreenCell *cells, void *user);
    static int onPopLine(int cols, VTermScreenCell *cells, void *user);
    static int onClearHistory(void *user);
    static int onOsc(int command, VTermStringFragment fragment, void *user);
    static void onOutput(const char *bytes, size_t length, void *user);

    void updateMetrics();
    void updateGrid();
    void readOutput();
    void writeBytes(const char *bytes, size_t length);
    void childFinished();
    void scheduleUpdate();
    void restartBlink();

    bool cellAt(long long line, int column, VTermScreenCell &cell) const;
    QColor resolve(const VTermColor &colour, bool foreground) const;
    QPoint gridPosition(const QPointF &point) const;
    bool isSelected(long long line, int column) const;
    void selectWord(const QPoint &position);
    QString lineText(long long line, int from, int to) const;
    long long firstLine() const;
    long long visibleLine(int row) const;
    bool mouseReporting(const QMouseEvent *event) const;
    VTermModifier modifiers(Qt::KeyboardModifiers modifiers) const;

    VTerm *m_vterm = nullptr;
    VTermScreen *m_screen = nullptr;
    VTermState *m_state = nullptr;
    int m_master = -1;
    int m_pid = -1;
    QSocketNotifier *m_notifier = nullptr;

    QFont m_font;
    qreal m_cellWidth = 8;
    qreal m_cellHeight = 16;
    qreal m_ascent = 12;
    int m_rows = 24;
    int m_columns = 80;

    QVariantMap m_colourMap;
    QColor m_background;
    QColor m_foreground;
    QColor m_cursorColour;
    QColor m_cursorText;
    QColor m_selection;
    QColor m_selectionText;
    QColor m_palette[16];

    QString m_title;
    QByteArray m_titleBuffer;
    QByteArray m_oscBuffer;
    QString m_workingDirectory;

    VTermPos m_cursor{0, 0};
    bool m_cursorVisible = true;
    bool m_cursorBlinks = true;
    bool m_blinkOn = true;
    int m_cursorShape = VTERM_PROP_CURSORSHAPE_BAR_LEFT;
    int m_mouseMode = VTERM_PROP_MOUSE_NONE;
    bool m_altScreen = false;
    QTimer m_blink;
    bool m_updatePending = false;

    std::deque<std::vector<VTermScreenCell>> m_history;
    long long m_pushed = 0;
    int m_scrollOffset = 0;
    qreal m_wheelRemainder = 0;

    bool m_selecting = false;
    bool m_hasSelection = false;
    QPoint m_anchor;
    QPoint m_head;
    QPoint m_pressPosition;
};
