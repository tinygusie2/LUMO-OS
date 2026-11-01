/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "m3"

Rectangle {
    id: card

    required property QtObject backend
    property bool expanded: false
    property int monthOffset: 0
    property date selected: backend.now

    signal requestClose()

    readonly property var calendar: backend.calendar
    readonly property date shown: new Date(backend.now.getFullYear(), backend.now.getMonth() + monthOffset, 1)
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property int lead: (shown.getDay() - firstDay + 7) % 7
    readonly property var items: { calendar ? calendar.events : null; return calendar ? calendar.onDay(selected) : []; }
    readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat).replace(/[.:]?s+/g, "")

    visible: expanded || items.length > 0
    implicitHeight: column.implicitHeight + 24
    radius: M3.classic ? M3.cornerCard : 24
    color: M3.surfaceContainerHigh

    onExpandedChanged: {
        if (expanded) {
            monthOffset = 0;
            selected = backend.now;
            calendar?.refresh();
        }
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            visible: card.expanded
            spacing: 0
            MText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                role: "titleMedium"
                text: {
                    const month = Qt.locale().standaloneMonthName(card.shown.getMonth(), Locale.LongFormat);
                    return month.charAt(0).toUpperCase() + month.slice(1) + " " + card.shown.getFullYear();
                }
            }
            MIconButton {
                icon: "go-previous"
                text: i18n("Previous month")
                onClicked: card.monthOffset -= 1
            }
            MIconButton {
                icon: "go-next"
                text: i18n("Next month")
                onClicked: card.monthOffset += 1
            }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            visible: card.expanded
            columns: 7
            readonly property real cell: width / 7

            Repeater {
                model: 7
                delegate: Item {
                    required property int index
                    width: grid.cell
                    height: 24
                    MText {
                        anchors.centerIn: parent
                        role: "labelMedium"
                        color: M3.surfaceVariantContent
                        text: Qt.locale().dayName((card.firstDay + index) % 7, Locale.NarrowFormat).toUpperCase()
                    }
                }
            }
            Repeater {
                model: 42
                delegate: Item {
                    id: day
                    required property int index
                    readonly property date when: new Date(card.shown.getFullYear(), card.shown.getMonth(), 1 - card.lead + index)
                    readonly property bool inMonth: when.getMonth() === card.shown.getMonth()
                    readonly property bool today: card.sameDay(when, card.backend.now)
                    readonly property bool chosen: card.sameDay(when, card.selected)
                    readonly property bool busy: { card.calendar ? card.calendar.events : null; return card.calendar ? card.calendar.hasEvents(when) : false; }
                    width: grid.cell
                    height: 36

                    Rectangle {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        radius: 16
                        color: day.today ? M3.primary : day.chosen ? M3.secondaryContainer : "transparent"
                    }
                    MText {
                        anchors.centerIn: parent
                        role: "bodyMedium"
                        text: day.when.getDate()
                        color: day.today ? M3.primaryContent : M3.surfaceContent
                        opacity: day.inMonth ? 1 : 0.35
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        width: 4
                        height: 4
                        radius: 2
                        visible: day.busy
                        color: day.today ? M3.primary : M3.surfaceVariantContent
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: card.selected = day.when
                    }
                }
            }
        }

        MText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: card.expanded ? 6 : 0
            role: "labelLarge"
            color: M3.surfaceVariantContent
            text: card.sameDay(card.selected, card.backend.now) ? i18n("Today")
                : card.selected.toLocaleDateString(Qt.locale(), "dddd d MMMM")
        }

        Repeater {
            model: card.expanded ? card.items : card.items.slice(0, 2)
            delegate: Rectangle {
                id: entry
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: entryColumn.implicitHeight + 16
                radius: 14
                color: M3.primaryContainer
                ColumnLayout {
                    id: entryColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 0
                    MText {
                        Layout.fillWidth: true
                        role: "labelLarge"
                        color: M3.primaryContainerContent
                        text: entry.modelData.title || i18n("Event")
                    }
                    MText {
                        Layout.fillWidth: true
                        role: "labelMedium"
                        color: M3.primaryContainerContent
                        opacity: 0.8
                        text: (entry.modelData.allDay ? i18n("All day")
                            : Qt.formatTime(entry.modelData.start, card.timeFormat) + " – " + Qt.formatTime(entry.modelData.end, card.timeFormat))
                            + (entry.modelData.location.length > 0 ? " · " + entry.modelData.location : "")
                    }
                }
            }
        }

        MText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            visible: card.expanded && card.items.length === 0
            role: "bodyMedium"
            color: M3.surfaceVariantContent
            text: i18n("Nothing planned")
        }

        MButton {
            Layout.alignment: Qt.AlignRight
            visible: card.expanded
            text: i18n("Open Calendar")
            onClicked: {
                card.backend.openCalendar();
                card.requestClose();
            }
        }
    }
}
