// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

.pragma library

const DAY = 86400000;

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days, date.getHours(), date.getMinutes());
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function pad(value) {
    return String(value).padStart(2, "0");
}

function dateKey(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
}

function timeKey(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes());
}

function parseDate(text, time) {
    const d = String(text).trim().match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
    if (!d) {
        return null;
    }
    const t = String(time || "00:00").trim().match(/^(\d{1,2}):(\d{2})$/);
    if (!t || Number(t[1]) > 23 || Number(t[2]) > 59) {
        return null;
    }
    const result = new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3]), Number(t[1]), Number(t[2]));
    return result.getMonth() === Number(d[2]) - 1 ? result : null;
}

function step(date, repeat, count) {
    switch (repeat) {
    case "daily":
        return addDays(date, count);
    case "weekly":
        return addDays(date, 7 * count);
    case "monthly":
        return new Date(date.getFullYear(), date.getMonth() + count, date.getDate(), date.getHours(), date.getMinutes());
    case "yearly":
        return new Date(date.getFullYear() + count, date.getMonth(), date.getDate(), date.getHours(), date.getMinutes());
    }
    return date;
}

function occurrences(events, from, to) {
    const result = [];
    for (const event of events) {
        const start = new Date(event.start);
        const end = new Date(event.end);
        const length = Math.max(0, end - start);
        if (!event.repeat || event.repeat === "none") {
            if (start < to && (end > from || (length === 0 && start >= from))) {
                result.push({ event: event, start: start, end: end });
            }
            continue;
        }
        let index = 0;
        if (event.repeat === "daily" && start < from) {
            index = Math.max(0, Math.floor((from - start) / DAY) - 1);
        } else if (event.repeat === "weekly" && start < from) {
            index = Math.max(0, Math.floor((from - start) / (7 * DAY)) - 1);
        }
        for (let guard = 0; guard < 2000; guard++, index++) {
            const at = step(start, event.repeat, index);
            if (at >= to) {
                break;
            }
            const until = new Date(at.getTime() + length);
            if (until > from || (length === 0 && at >= from)) {
                result.push({ event: event, start: at, end: until });
            }
        }
    }
    return result.sort((a, b) => (b.event.allDay - a.event.allDay) || (a.start - b.start));
}

function onDay(events, day) {
    const from = startOfDay(day);
    return occurrences(events, from, addDays(from, 1));
}

function newId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function unfold(text) {
    return text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n");
}

function icsDate(value, params) {
    const m = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/);
    if (!m) {
        return null;
    }
    if (!m[4]) {
        return { date: new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])), allDay: true };
    }
    const parts = [Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6] || 0)];
    const date = m[7] ? new Date(Date.UTC(...parts)) : new Date(...parts);
    return { date: date, allDay: false };
}

function unescapeText(value) {
    return value.replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1");
}

function parseIcs(text) {
    const events = [];
    let current = null;
    let inAlarm = false;
    for (const line of unfold(text)) {
        if (line === "BEGIN:VEVENT") {
            current = { id: newId(), title: "", start: null, end: null, allDay: false, repeat: "none", remind: -1, location: "", notes: "" };
            continue;
        }
        if (!current) {
            continue;
        }
        if (line === "BEGIN:VALARM") {
            inAlarm = true;
            continue;
        }
        if (line === "END:VALARM") {
            inAlarm = false;
            continue;
        }
        if (line === "END:VEVENT") {
            if (current.start) {
                if (!current.end) {
                    current.end = current.allDay ? addDays(current.start, 1) : new Date(current.start.getTime() + 3600000);
                }
                current.start = current.start.toISOString();
                current.end = current.end.toISOString();
                events.push(current);
            }
            current = null;
            continue;
        }
        const colon = line.indexOf(":");
        if (colon < 0) {
            continue;
        }
        const head = line.slice(0, colon).split(";");
        const name = head[0].toUpperCase();
        const value = line.slice(colon + 1);
        if (inAlarm) {
            if (name === "TRIGGER") {
                const t = value.match(/^-?P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?/);
                if (t) {
                    current.remind = (Number(t[1] || 0) * 1440) + (Number(t[2] || 0) * 60) + Number(t[3] || 0);
                }
            }
            continue;
        }
        if (name === "SUMMARY") {
            current.title = unescapeText(value);
        } else if (name === "LOCATION") {
            current.location = unescapeText(value);
        } else if (name === "DESCRIPTION") {
            current.notes = unescapeText(value);
        } else if (name === "DTSTART" || name === "DTEND") {
            const parsed = icsDate(value, head.slice(1));
            if (parsed) {
                if (name === "DTSTART") {
                    current.start = parsed.date;
                    current.allDay = parsed.allDay;
                } else {
                    current.end = parsed.date;
                }
            }
        } else if (name === "RRULE") {
            const freq = (value.match(/FREQ=(\w+)/) || [])[1];
            current.repeat = { DAILY: "daily", WEEKLY: "weekly", MONTHLY: "monthly", YEARLY: "yearly" }[freq] || "none";
        }
    }
    return events;
}

function icsStamp(date, allDay) {
    if (allDay) {
        return date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate());
    }
    return date.getUTCFullYear() + pad(date.getUTCMonth() + 1) + pad(date.getUTCDate()) + "T"
        + pad(date.getUTCHours()) + pad(date.getUTCMinutes()) + pad(date.getUTCSeconds()) + "Z";
}

function escapeText(value) {
    return String(value || "").replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/([,;])/g, "\\$1");
}

function toIcs(events) {
    const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Lumo//Calendar//EN"];
    for (const event of events) {
        const start = new Date(event.start);
        const end = new Date(event.end);
        lines.push("BEGIN:VEVENT", "UID:" + event.id + "@lumo", "DTSTAMP:" + icsStamp(new Date(), false));
        lines.push((event.allDay ? "DTSTART;VALUE=DATE:" : "DTSTART:") + icsStamp(start, event.allDay));
        lines.push((event.allDay ? "DTEND;VALUE=DATE:" : "DTEND:") + icsStamp(end, event.allDay));
        lines.push("SUMMARY:" + escapeText(event.title));
        if (event.location) {
            lines.push("LOCATION:" + escapeText(event.location));
        }
        if (event.notes) {
            lines.push("DESCRIPTION:" + escapeText(event.notes));
        }
        if (event.repeat && event.repeat !== "none") {
            lines.push("RRULE:FREQ=" + event.repeat.toUpperCase());
        }
        if (event.remind >= 0) {
            lines.push("BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + escapeText(event.title), "TRIGGER:-PT" + event.remind + "M", "END:VALARM");
        }
        lines.push("END:VEVENT");
    }
    lines.push("END:VCALENDAR");
    return lines.join("\r\n") + "\r\n";
}
