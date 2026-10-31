/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.notification
import org.lumo.m3
import org.lumo.ui
import org.lumo.system
import "calendar.js" as Cal

AppWindow {
    id: app

    width: 980
    height: 700
    minimumWidth: 560
    minimumHeight: 480
    title: i18n("Calendar")
    visible: !app.remindersOnly

    readonly property bool remindersOnly: startArguments.indexOf("reminders") >= 0
    readonly property string folder: decodeURIComponent(Files.standardFolder("home").toString().replace(/^file:\/\//, "")) + "/.local/share/lumo/calendar"
    readonly property url file: Qt.url("file://" + folder + "/events.json")

    property var events: []
    property string view: "month"
    property date cursor: new Date()
    property date today: new Date()
    property date lastCheck: new Date()

    readonly property date monthStart: new Date(cursor.getFullYear(), cursor.getMonth(), 1)
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property date gridStart: Cal.addDays(monthStart, -((monthStart.getDay() - firstDay + 7) % 7))
    readonly property date weekStart: Cal.addDays(Cal.startOfDay(cursor), -((cursor.getDay() - firstDay + 7) % 7))

    function handleArguments(args: var): void {
        const files = args.filter(a => String(a).startsWith("file:") && String(a).toLowerCase().endsWith(".ics"));
        for (const f of files) {
            importFile(Qt.url(f));
        }
        if (args.indexOf("reminders") < 0) {
            show();
            raise();
            requestActivate();
        }
    }

    function load(): void {
        const result = Files.readText(file);
        if (!result.ok) {
            events = [];
            return;
        }
        try {
            const data = JSON.parse(result.text);
            events = Array.isArray(data.events) ? data.events : [];
        } catch (e) {
            events = [];
        }
    }

    function save(): void {
        Process.run("mkdir", ["-p", folder], () => {
            Files.writeText(app.file, JSON.stringify({ version: 1, events: app.events }, null, 1));
        });
    }

    function upsert(event: var): void {
        const others = events.filter(e => e.id !== event.id);
        events = others.concat([event]);
        save();
    }

    function remove(id: string): void {
        events = events.filter(e => e.id !== id);
        save();
    }

    function importFile(url: url): void {
        const result = Files.readText(url);
        if (!result.ok) {
            showMessage(i18n("This file could not be read"), "", null);
            return;
        }
        const found = Cal.parseIcs(result.text);
        events = events.concat(found);
        save();
        showMessage(i18np("%1 event imported", "%1 events imported", found.length), "", null);
    }

    function exportFile(): void {
        const documents = decodeURIComponent(Files.standardFolder("documents").toString().replace(/^file:\/\//, ""));
        const target = Qt.url("file://" + documents + "/" + i18n("Lumo calendar") + ".ics");
        if (Files.writeText(target, Cal.toIcs(events))) {
            showMessage(i18n("Saved in Documents"), i18n("Show"), () => Process.openUrl(target));
        } else {
            showMessage(i18n("The calendar could not be saved"), "", null);
        }
    }

    function move(direction: int): void {
        if (view === "month") {
            cursor = new Date(cursor.getFullYear(), cursor.getMonth() + direction, 1);
        } else if (view === "week") {
            cursor = Cal.addDays(cursor, 7 * direction);
        } else {
            cursor = Cal.addDays(cursor, direction);
        }
    }

    function heading(): string {
        if (view === "month") {
            const month = Qt.locale().standaloneMonthName(cursor.getMonth(), Locale.LongFormat);
            return month.charAt(0).toUpperCase() + month.slice(1) + " " + cursor.getFullYear();
        }
        if (view === "week") {
            const end = Cal.addDays(weekStart, 6);
            return weekStart.toLocaleDateString(Qt.locale(), "d MMM") + " – " + end.toLocaleDateString(Qt.locale(), "d MMM yyyy");
        }
        return cursor.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy");
    }

    function timeRange(occurrence: var): string {
        if (occurrence.event.allDay) {
            return i18n("All day");
        }
        return Qt.formatTime(occurrence.start, Qt.locale().timeFormat(Locale.ShortFormat))
            + " – " + Qt.formatTime(occurrence.end, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function openEditor(event: var, day: var): void {
        editor.edit(event, day || cursor);
    }

    function checkReminders(): void {
        const now = new Date();
        today = now;
        const upcoming = Cal.occurrences(events, Cal.addDays(lastCheck, -1), Cal.addDays(now, 2));
        for (const o of upcoming) {
            if (o.event.remind === undefined || o.event.remind < 0) {
                continue;
            }
            const at = new Date(o.start.getTime() - o.event.remind * 60000);
            if (at > lastCheck && at <= now) {
                const note = reminderComponent.createObject(app, {
                    title: o.event.title || i18n("Event"),
                    text: (o.event.allDay ? i18n("Today") : app.timeRange(o)) + (o.event.location ? " · " + o.event.location : "")
                });
                note.sendEvent();
            }
        }
        lastCheck = now;
    }

    Component.onCompleted: {
        load();
        lastCheck = new Date();
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            app.load();
            app.checkReminders();
        }
    }

    Component {
        id: reminderComponent
        Notification {
            componentName: "lumo-calendar"
            eventId: "reminder"
            iconName: "org.lumo.calendar"
            autoDelete: true
        }
    }

    onClosing: close => {
        close.accepted = false;
        app.hide();
    }

    Shortcut { sequence: "Ctrl+N"; onActivated: app.openEditor(null, app.cursor) }
    Shortcut { sequence: "Ctrl+T"; onActivated: app.cursor = new Date() }
    Shortcut { sequences: ["PgUp", "Alt+Left"]; onActivated: app.move(-1) }
    Shortcut { sequences: ["PgDown", "Alt+Right"]; onActivated: app.move(1) }

    FileDialog {
        id: importDialog
        title: i18n("Import a calendar")
        nameFilters: [i18n("Calendars (*.ics)"), i18n("All files (*)")]
        onAccepted: app.importFile(selectedFile)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            QQC2.Button {
                text: i18n("New event")
                icon.name: "list-add"
                highlighted: true
                onClicked: app.openEditor(null, app.cursor)
            }
            QQC2.Button {
                text: i18n("Today")
                flat: true
                onClicked: app.cursor = new Date()
            }
            IconButton {
                iconName: "go-previous"
                text: i18n("Previous")
                onClicked: app.move(-1)
            }
            IconButton {
                iconName: "go-next"
                text: i18n("Next")
                onClicked: app.move(1)
            }
            MText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                role: "titleLarge"
                text: app.heading()
            }
            SegmentedButtons {
                Layout.preferredWidth: 300
                options: [
                    { value: "day", label: i18n("Day") },
                    { value: "week", label: i18n("Week") },
                    { value: "month", label: i18n("Month") }
                ]
                currentValue: app.view
                onSelected: value => app.view = value
            }
            IconButton {
                iconName: "overflow-menu"
                text: i18n("More")
                onClicked: moreMenu.popup()
                QQC2.Menu {
                    id: moreMenu
                    QQC2.MenuItem { text: i18n("Import .ics file…"); onTriggered: importDialog.open() }
                    QQC2.MenuItem { text: i18n("Export to Documents"); onTriggered: app.exportFile() }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: M3.classic ? M3.cornerCard : 24
            color: M3.surfaceContainer
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 0
                visible: app.view === "month"

                Row {
                    Layout.fillWidth: true
                    Repeater {
                        model: 7
                        delegate: MText {
                            required property int index
                            width: parent.parent.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            role: "labelMedium"
                            color: M3.surfaceVariantContent
                            text: Qt.locale().dayName((app.firstDay + index) % 7, Locale.ShortFormat)
                        }
                    }
                }
                Grid {
                    id: monthGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    Repeater {
                        model: 42
                        delegate: Rectangle {
                            id: cell
                            required property int index
                            readonly property date day: Cal.addDays(app.gridStart, index)
                            readonly property bool inMonth: day.getMonth() === app.monthStart.getMonth()
                            readonly property bool isToday: Cal.sameDay(day, app.today)
                            readonly property var items: { app.events; return Cal.onDay(app.events, day); }
                            width: monthGrid.width / 7
                            height: monthGrid.height / 6
                            color: cellHover.hovered ? M3.withAlpha(M3.surfaceContent, 0.05) : "transparent"
                            border.width: 0.5
                            border.color: M3.outlineVariant

                            HoverHandler { id: cellHover }
                            TapHandler {
                                onTapped: app.cursor = cell.day
                                onDoubleTapped: app.openEditor(null, cell.day)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 2
                                Rectangle {
                                    Layout.alignment: Qt.AlignLeft
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    color: cell.isToday ? M3.primary : Cal.sameDay(cell.day, app.cursor) ? M3.secondaryContainer : "transparent"
                                    MText {
                                        anchors.centerIn: parent
                                        role: "labelLarge"
                                        text: cell.day.getDate()
                                        color: cell.isToday ? M3.primaryContent : M3.surfaceContent
                                        opacity: cell.inMonth ? 1 : 0.4
                                    }
                                }
                                Repeater {
                                    model: cell.items.slice(0, Math.max(0, Math.floor((cell.height - 40) / 20)))
                                    delegate: Rectangle {
                                        id: chip
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 18
                                        radius: 6
                                        color: M3.primaryContainer
                                        MText {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 4
                                            role: "labelSmall"
                                            color: M3.primaryContainerContent
                                            text: (chip.modelData.event.allDay ? "" : Cal.timeKey(chip.modelData.start) + " ") + (chip.modelData.event.title || i18n("Event"))
                                        }
                                        TapHandler { onTapped: app.openEditor(chip.modelData.event, cell.day) }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 0
                visible: app.view === "week"

                Repeater {
                    model: 7
                    delegate: ColumnLayout {
                        id: weekDay
                        required property int index
                        readonly property date day: Cal.addDays(app.weekStart, index)
                        readonly property var items: { app.events; return Cal.onDay(app.events, day); }
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.margins: 4
                            implicitHeight: 56
                            radius: 16
                            color: Cal.sameDay(weekDay.day, app.today) ? M3.primary : "transparent"
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                MText {
                                    Layout.alignment: Qt.AlignHCenter
                                    role: "labelMedium"
                                    color: Cal.sameDay(weekDay.day, app.today) ? M3.primaryContent : M3.surfaceVariantContent
                                    text: Qt.locale().dayName(weekDay.day.getDay(), Locale.ShortFormat)
                                }
                                MText {
                                    Layout.alignment: Qt.AlignHCenter
                                    role: "titleLarge"
                                    color: Cal.sameDay(weekDay.day, app.today) ? M3.primaryContent : M3.surfaceContent
                                    text: weekDay.day.getDate()
                                }
                            }
                            TapHandler { onTapped: { app.cursor = weekDay.day; app.view = "day"; } }
                        }
                        Repeater {
                            model: weekDay.items
                            delegate: EventCard {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                compact: true
                                day: weekDay.day
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TapHandler { onDoubleTapped: app.openEditor(null, weekDay.day) }
                        }
                    }
                }
            }

            QQC2.ScrollView {
                anchors.fill: parent
                anchors.margins: 16
                visible: app.view === "day"
                contentWidth: availableWidth

                ColumnLayout {
                    id: dayColumn
                    readonly property var items: { app.events; return Cal.onDay(app.events, app.cursor); }
                    width: parent.width
                    spacing: 8

                    EmptyState {
                        Layout.fillWidth: true
                        visible: dayColumn.items.length === 0
                        icon: "org.lumo.calendar"
                        title: i18n("Nothing planned")
                        text: i18n("Double-click a day or press Ctrl+N to add an event.")
                    }
                    Repeater {
                        model: dayColumn.items
                        delegate: EventCard {
                            Layout.fillWidth: true
                            day: app.cursor
                        }
                    }
                }
            }
        }
    }

    component EventCard: Rectangle {
        id: card
        required property var modelData
        property bool compact: false
        property date day: new Date()
        implicitHeight: body.implicitHeight + (compact ? 12 : 24)
        radius: compact ? 10 : 16
        color: M3.primaryContainer

        TapHandler { onTapped: app.openEditor(card.modelData.event, card.day) }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: card.compact ? 8 : 16
            spacing: 2
            MText {
                Layout.fillWidth: true
                role: card.compact ? "labelLarge" : "titleMedium"
                color: M3.primaryContainerContent
                text: card.modelData.event.title || i18n("Event")
                wrapMode: card.compact ? Text.NoWrap : Text.Wrap
            }
            MText {
                Layout.fillWidth: true
                role: card.compact ? "labelSmall" : "bodyMedium"
                color: M3.primaryContainerContent
                opacity: 0.8
                text: app.timeRange(card.modelData) + (card.modelData.event.location ? " · " + card.modelData.event.location : "")
            }
            MText {
                Layout.fillWidth: true
                visible: !card.compact && (card.modelData.event.notes || "").length > 0
                role: "bodyMedium"
                color: M3.primaryContainerContent
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: card.modelData.event.notes || ""
            }
        }
    }

    Dialog {
        id: editor

        property var editing: null
        property bool allDay: false
        property string repeat: "none"
        property int remind: 15

        title: editing ? i18n("Edit event") : i18n("New event")
        acceptText: i18n("Save")
        preferredWidth: 480
        acceptEnabled: titleField.text.trim().length > 0 && startValid && endValid

        readonly property var startDate: Cal.parseDate(dateField.text, allDay ? "00:00" : startField.text)
        readonly property var endDate: allDay ? Cal.addDays(Cal.parseDate(endDateField.text, "00:00") || new Date(0), 1)
            : Cal.parseDate(endDateField.text, endField.text)
        readonly property bool startValid: startDate !== null
        readonly property bool endValid: endDate !== null && startDate !== null && endDate >= startDate

        function edit(event: var, day: var): void {
            editing = event;
            const start = event ? new Date(event.start) : new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.min(23, new Date().getHours() + 1), 0);
            const end = event ? new Date(event.end) : new Date(start.getTime() + 3600000);
            allDay = event ? event.allDay === true : false;
            repeat = event ? (event.repeat || "none") : "none";
            remind = event ? (event.remind === undefined ? -1 : event.remind) : 15;
            titleField.text = event ? event.title : "";
            locationField.text = event ? (event.location || "") : "";
            notesField.text = event ? (event.notes || "") : "";
            dateField.text = Cal.dateKey(start);
            startField.text = Cal.timeKey(start);
            endDateField.text = Cal.dateKey(allDay ? Cal.addDays(end, -1) : end);
            endField.text = Cal.timeKey(end);
            visible = true;
            titleField.forceActiveFocus();
        }

        onAccepted: {
            app.upsert({
                id: editing ? editing.id : Cal.newId(),
                title: titleField.text.trim(),
                start: startDate.toISOString(),
                end: endDate.toISOString(),
                allDay: allDay,
                repeat: repeat,
                remind: remind,
                location: locationField.text.trim(),
                notes: notesField.text.trim()
            });
        }

        InputField { id: titleField; Layout.fillWidth: true; label: i18n("Title") }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            InputField {
                id: dateField
                Layout.fillWidth: true
                label: i18n("Starts (YYYY-MM-DD)")
                errorText: editor.startValid ? "" : i18n("Not a date")
            }
            InputField {
                id: startField
                Layout.preferredWidth: 110
                visible: !editor.allDay
                label: i18n("Time")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            InputField {
                id: endDateField
                Layout.fillWidth: true
                label: i18n("Ends (YYYY-MM-DD)")
                errorText: editor.endValid ? "" : i18n("Ends before it starts")
            }
            InputField {
                id: endField
                Layout.preferredWidth: 110
                visible: !editor.allDay
                label: i18n("Time")
            }
        }
        QQC2.Switch {
            text: i18n("All day")
            checked: editor.allDay
            onToggled: editor.allDay = checked
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MText { role: "bodyMedium"; text: i18n("Repeat") }
            QQC2.ComboBox {
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "value"
                model: [
                    { value: "none", label: i18n("Never") },
                    { value: "daily", label: i18n("Every day") },
                    { value: "weekly", label: i18n("Every week") },
                    { value: "monthly", label: i18n("Every month") },
                    { value: "yearly", label: i18n("Every year") }
                ]
                currentIndex: Math.max(0, ["none", "daily", "weekly", "monthly", "yearly"].indexOf(editor.repeat))
                onActivated: editor.repeat = currentValue
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MText { role: "bodyMedium"; text: i18n("Remind me") }
            QQC2.ComboBox {
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "value"
                readonly property var choices: [-1, 0, 5, 15, 30, 60, 1440]
                model: [
                    { value: -1, label: i18n("No reminder") },
                    { value: 0, label: i18n("When it starts") },
                    { value: 5, label: i18n("5 minutes before") },
                    { value: 15, label: i18n("15 minutes before") },
                    { value: 30, label: i18n("30 minutes before") },
                    { value: 60, label: i18n("1 hour before") },
                    { value: 1440, label: i18n("1 day before") }
                ]
                currentIndex: Math.max(0, choices.indexOf(editor.remind))
                onActivated: editor.remind = currentValue
            }
        }
        InputField { id: locationField; Layout.fillWidth: true; label: i18n("Location") }
        InputField { id: notesField; Layout.fillWidth: true; label: i18n("Notes") }
        QQC2.Button {
            visible: editor.editing !== null
            text: i18n("Delete event")
            flat: true
            onClicked: {
                app.remove(editor.editing.id);
                editor.close();
            }
        }
    }
}
