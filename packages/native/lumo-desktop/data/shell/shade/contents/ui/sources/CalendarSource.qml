/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: source

    property var events: []
    readonly property string command: 'cat "$HOME/.local/share/lumo/calendar/events.json" 2>/dev/null'

    function refresh(): void {
        reader.connectSource(command);
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function shift(start: date, repeat: string, count: int): date {
        const y = start.getFullYear(), m = start.getMonth(), d = start.getDate(), h = start.getHours(), mi = start.getMinutes();
        switch (repeat) {
        case "daily": return new Date(y, m, d + count, h, mi);
        case "weekly": return new Date(y, m, d + 7 * count, h, mi);
        case "monthly": return new Date(y, m + count, d, h, mi);
        case "yearly": return new Date(y + count, m, d, h, mi);
        }
        return start;
    }

    function onDay(day: date): var {
        const from = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const to = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
        const found = [];
        for (const event of events) {
            const start = new Date(event.start);
            const length = Math.max(0, new Date(event.end) - start);
            const repeating = event.repeat && event.repeat !== "none";
            let index = 0;
            if (repeating && (event.repeat === "daily" || event.repeat === "weekly") && start < from) {
                index = Math.max(0, Math.floor((from - start) / ((event.repeat === "daily" ? 1 : 7) * 86400000)) - 1);
            }
            for (let guard = 0; guard < (repeating ? 2000 : 1); guard++, index++) {
                const at = repeating ? shift(start, event.repeat, index) : start;
                if (at >= to) {
                    break;
                }
                const until = new Date(at.getTime() + length);
                if (until > from || (length === 0 && at >= from)) {
                    found.push({ title: event.title, allDay: event.allDay === true, start: at, end: until, location: event.location || "" });
                }
            }
        }
        return found.sort((a, b) => (b.allDay - a.allDay) || (a.start - b.start));
    }

    function hasEvents(day: date): bool {
        return onDay(day).length > 0;
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            try {
                const parsed = JSON.parse(data["stdout"] || "{}");
                source.events = Array.isArray(parsed.events) ? parsed.events : [];
            } catch (e) {
                source.events = [];
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: source.refresh()
    }
}
