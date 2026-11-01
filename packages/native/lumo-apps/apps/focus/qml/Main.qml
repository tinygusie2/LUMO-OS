/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.notification
import org.lumo.m3
import org.lumo.ui
import org.lumo.system

AppWindow {
    id: app

    width: 460
    height: 640
    minimumWidth: 380
    minimumHeight: 560
    visible: true
    title: active ? i18nc("@title:window remaining time and phase", "%1 · %2", clock(left), phaseName()) : i18n("Focus")

    readonly property string configFile: "lumofocusrc"
    readonly property var apps: String(appsEntry.value || "").split(",").filter(id => id.length > 0)
    readonly property int focusMinutes: Math.max(1, Number(focusEntry.value) || 25)
    readonly property int breakMinutes: Math.max(1, Number(breakEntry.value) || 5)
    readonly property int roundCount: Math.max(1, Number(roundsEntry.value) || 4)
    readonly property bool quietWhileFocused: String(dndEntry.value) !== "false"
    readonly property bool appsInBreaks: String(breakAppsEntry.value) === "true"

    property string phase: "idle"
    property int round: 1
    property int rounds: 4
    property real endsAt: 0
    property real phaseLength: 1
    property real pausedLeft: -1
    property real left: 0
    property int cookie: 0
    property bool inhibiting: false
    property var lastBlocked: ({})

    readonly property bool active: phase !== "idle"
    readonly property bool paused: pausedLeft >= 0
    readonly property bool blocking: phase === "focus" || (phase === "break" && !appsInBreaks)
    readonly property real progress: active ? Math.max(0, Math.min(1, 1 - left / phaseLength)) : 0

    function clock(ms: real): string {
        const total = Math.max(0, Math.ceil(ms / 1000));
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function phaseName(): string {
        if (phase === "break") {
            return i18n("Break");
        }
        return i18n("Focus");
    }

    function handleArguments(args: var): void {
        show();
        raise();
        requestActivate();
        if (args.indexOf("start") >= 0 && !active) {
            askToStart();
        }
    }

    function askToStart(): void {
        const open = Focus.running(apps);
        if (open.length > 0) {
            closeDialog.names = open.map(a => a.name);
            closeDialog.open();
            return;
        }
        start();
    }

    function beginPhase(name: string, minutes: int): void {
        phase = name;
        phaseLength = minutes * 60000;
        endsAt = Date.now() + phaseLength;
        pausedLeft = -1;
        left = phaseLength;
        updateQuiet();
    }

    function start(): void {
        rounds = roundCount;
        round = 1;
        lastBlocked = {};
        beginPhase("focus", focusMinutes);
    }

    function stop(): void {
        phase = "idle";
        pausedLeft = -1;
        left = 0;
        updateQuiet();
    }

    function finish(): void {
        stop();
        send("finished", i18n("Focus finished"), i18np("You stayed focused for %1 round. All apps are allowed again.", "You stayed focused for %1 rounds. All apps are allowed again.", rounds));
        show();
        raise();
        showMessage(i18n("Well done. Your desktop is back to normal."), "", null);
    }

    function advance(): void {
        if (phase === "focus") {
            if (round >= rounds) {
                finish();
                return;
            }
            beginPhase("break", breakMinutes);
            send("breakStarted", i18n("Time for a break"), i18np("Take %1 minute off.", "Take %1 minutes off.", breakMinutes));
        } else if (phase === "break") {
            round += 1;
            send("focusStarted", i18n("Back to focus"), i18n("Round %1 of %2 has started.", round, rounds));
            beginPhase("focus", focusMinutes);
        }
    }

    function togglePause(): void {
        if (paused) {
            endsAt = Date.now() + pausedLeft;
            pausedLeft = -1;
        } else {
            pausedLeft = Math.max(0, endsAt - Date.now());
        }
    }

    function tick(): void {
        if (!active || paused) {
            return;
        }
        left = Math.max(0, endsAt - Date.now());
        if (left <= 0) {
            advance();
        }
    }

    function enforce(): void {
        const ended = Focus.block(apps);
        if (ended.length === 0) {
            return;
        }
        const now = Date.now();
        const fresh = ended.filter(a => !lastBlocked[a.storageId] || now - lastBlocked[a.storageId] > 15000);
        const seen = Object.assign({}, lastBlocked);
        for (const a of ended) {
            seen[a.storageId] = now;
        }
        lastBlocked = seen;
        if (fresh.length === 0) {
            return;
        }
        if (visibility === Window.Minimized || !visible) {
            showNormal();
        }
        raise();
        requestActivate();
        showMessage(fresh.length === 1
            ? i18n("%1 is blocked until your focus time is over", fresh[0].name)
            : i18n("%1 are blocked until your focus time is over", fresh.map(a => a.name).join(", ")), "", null);
    }

    function updateQuiet(): void {
        const wanted = phase === "focus" && quietWhileFocused;
        if (wanted && cookie === 0 && !inhibiting) {
            inhibiting = true;
            DBus.call("session", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                      "org.freedesktop.Notifications", "Inhibit",
                      ["org.lumo.focus", i18n("Focus mode is on"), {}], (ok, result) => {
                app.inhibiting = false;
                if (!ok) {
                    return;
                }
                app.cookie = Number(result);
                app.updateQuiet();
            });
        } else if (!wanted && cookie !== 0) {
            const old = cookie;
            cookie = 0;
            DBus.call("session", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                      "org.freedesktop.Notifications", "UnInhibit", [{ type: "u", value: old }]);
        }
    }

    function send(event: string, title: string, text: string): void {
        const note = notificationComponent.createObject(app, { eventId: event, title: title, text: text });
        note.sendEvent();
    }

    onQuietWhileFocusedChanged: updateQuiet()
    onBlockingChanged: if (blocking) enforce()

    Component.onCompleted: {
        if (startArguments.indexOf("start") >= 0) {
            askToStart();
        }
    }

    onClosing: close => {
        if (app.active) {
            close.accepted = false;
            app.showMinimized();
        }
    }

    ConfigEntry { id: appsEntry; file: app.configFile; group: "General"; key: "Apps"; defaultValue: "" }
    ConfigEntry { id: focusEntry; file: app.configFile; group: "General"; key: "FocusMinutes"; defaultValue: 25 }
    ConfigEntry { id: breakEntry; file: app.configFile; group: "General"; key: "BreakMinutes"; defaultValue: 5 }
    ConfigEntry { id: roundsEntry; file: app.configFile; group: "General"; key: "Rounds"; defaultValue: 4 }
    ConfigEntry { id: dndEntry; file: app.configFile; group: "General"; key: "DoNotDisturb"; defaultValue: true }
    ConfigEntry { id: breakAppsEntry; file: app.configFile; group: "General"; key: "AppsInBreaks"; defaultValue: false }

    Timer {
        interval: 250
        running: app.active && !app.paused
        repeat: true
        onTriggered: app.tick()
    }

    Timer {
        interval: 2000
        running: app.active && app.blocking && app.apps.length > 0
        repeat: true
        onTriggered: app.enforce()
    }

    Component {
        id: notificationComponent
        Notification {
            componentName: "lumo-focus"
            iconName: "org.lumo.focus"
            autoDelete: true
        }
    }

    Dialog {
        id: closeDialog

        property var names: []

        icon: "lumo-timer"
        title: i18n("Close distracting apps?")
        text: i18np("%2 is open. It will be closed when focus starts, so save your work first.",
                    "%2 are open. They will be closed when focus starts, so save your work first.",
                    names.length, names.join(", "))
        acceptText: i18n("Start focus")
        onAccepted: app.start()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        MText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            role: "titleLarge"
            text: !app.active ? i18n("Ready to focus")
                : app.paused ? i18n("Paused")
                : app.phase === "break" ? i18n("Break") : i18n("Focus")
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 220

            Canvas {
                id: ring

                readonly property real size: Math.min(width, height)
                readonly property real progress: app.progress
                readonly property color track: M3.surfaceContainerHighest
                readonly property color fill: app.phase === "break" ? M3.tertiary : M3.primary

                anchors.fill: parent
                onProgressChanged: requestPaint()
                onTrackChanged: requestPaint()
                onFillChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const stroke = 14;
                    const radius = ring.size / 2 - stroke;
                    const cx = width / 2;
                    const cy = height / 2;
                    ctx.lineCap = "round";
                    ctx.lineWidth = stroke;
                    ctx.strokeStyle = ring.track;
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
                    ctx.stroke();
                    if (ring.progress > 0) {
                        ctx.strokeStyle = ring.fill;
                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ring.progress);
                        ctx.stroke();
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MText {
                    Layout.alignment: Qt.AlignHCenter
                    role: "displayMedium"
                    text: app.clock(app.active ? (app.paused ? app.pausedLeft : app.left) : app.focusMinutes * 60000)
                }
                MText {
                    Layout.alignment: Qt.AlignHCenter
                    role: "bodyMedium"
                    color: M3.surfaceVariantContent
                    text: app.active ? i18n("Round %1 of %2", app.round, app.rounds)
                        : i18np("%1 round", "%1 rounds", app.roundCount)
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    spacing: 6
                    Repeater {
                        model: app.active ? app.rounds : app.roundCount
                        delegate: Rectangle {
                            required property int index
                            width: 8
                            height: 8
                            radius: 4
                            color: app.active && (index < app.round - 1 || (index === app.round - 1 && app.phase === "break"))
                                ? M3.primary : M3.outlineVariant
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            MButton {
                visible: !app.active
                variant: "filled"
                icon: "media-playback-start"
                text: i18n("Start focus")
                onClicked: app.askToStart()
            }
            MButton {
                visible: app.active
                variant: "tonal"
                icon: app.paused ? "media-playback-start" : "media-playback-pause"
                text: app.paused ? i18n("Resume") : i18n("Pause")
                onClicked: app.togglePause()
            }
            MButton {
                visible: app.phase === "break"
                variant: "outlined"
                icon: "media-skip-forward"
                text: i18n("Skip break")
                onClicked: app.advance()
            }
            MButton {
                visible: app.active
                variant: "text"
                icon: "media-playback-stop"
                text: i18n("Stop")
                onClicked: app.stop()
            }
        }

        Group {
            Layout.fillWidth: true

            ListItem {
                title: i18n("Distracting apps")
                subtitle: app.apps.length === 0 ? i18n("None chosen yet")
                    : app.active && app.blocking ? i18np("%1 app is blocked right now", "%1 apps are blocked right now", app.apps.length)
                    : i18np("%1 app is blocked during focus", "%1 apps are blocked during focus", app.apps.length)
                icon: "view-app-grid"
                accent: 4
                chevron: true
                onClicked: Process.startDetached("lumo-settings", ["focus"])
            }
            ListItem {
                title: i18n("Timer")
                subtitle: i18n("%1 min focus, %2 min break", app.focusMinutes, app.breakMinutes)
                icon: "lumo-timer"
                accent: 0
                chevron: true
                onClicked: Process.startDetached("lumo-settings", ["focus"])
            }
        }
    }
}
