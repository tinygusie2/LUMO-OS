/*
    SPDX-FileCopyrightText: 2026 Kernora Developers
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import calamares.slideshow 1.0
import org.kernora.m3
import org.kernora.ui

Presentation {
    id: presentation

    readonly property string language: Qt.locale().name.slice(0, 2)

    readonly property var texts: language === "ru" ? [
        ["Lumo устанавливается", "Это займёт несколько минут. Пока идёт установка, живой системой можно пользоваться как обычно."],
        ["Всё в одном месте", "«Настройки» собирают вместе Wi-Fi, звук, экраны, аккаунт и обновления — с поиском по любому параметру."],
        ["Приложения на каждый день", "«Файлы», «Фото», «Медиаплеер», «Текстовый редактор», «Календарь» и «Диспетчер задач» готовы с первого запуска."],
        ["Как в Windows", "Привычные сочетания клавиш, программы для Windows через Wine и перенос файлов с диска Windows."],
        ["На прочной основе", "Lumo собрана из закреплённого снимка Debian и KDE Plasma; обновления приходят через «Настройки»."]
    ] : language === "nl" ? [
        ["Lumo wordt geïnstalleerd", "Dit duurt een paar minuten. Je kunt het live-systeem gewoon blijven gebruiken."],
        ["Alles op één plek", "Instellingen brengt wifi, geluid, schermen, je account en updates samen, en je kunt naar elke optie zoeken."],
        ["Apps voor elke dag", "Bestanden, Foto's, Mediaspeler, Teksteditor, Agenda en Taakbeheer staan vanaf de eerste keer klaar."],
        ["Vertrouwd voor wie van Windows komt", "Dezelfde sneltoetsen, Windows-programma's via Wine, en je bestanden overzetten van een Windows-schijf."],
        ["Op een stevige basis", "Lumo is gebouwd op een vaste versie van Debian en KDE Plasma; updates komen via Instellingen."]
    ] : [
        ["Lumo is being installed", "This takes a few minutes. You can keep using the live system while it works."],
        ["Everything in one place", "Settings brings Wi-Fi, sound, displays, your account and updates together, with search for any option."],
        ["Apps for every day", "Files, Photos, Media Player, Text Editor, Calendar and Task Manager are ready from the first start."],
        ["At home if you come from Windows", "The same shortcuts, Windows programs through Wine, and your files brought over from a Windows drive."],
        ["On solid ground", "Lumo is built from a pinned Debian snapshot and KDE Plasma; updates arrive through Settings."]
    ]

    Rectangle {
        anchors.fill: parent
        color: M3.surface
    }

    Timer {
        interval: 12000
        repeat: true
        running: presentation.activatedInCalamares
        onTriggered: presentation.goToNextSlide()
    }

    Repeater {
        model: presentation.texts

        delegate: Slide {
            id: slide
            required property var modelData
            required property int index

            RoundedClip {
                id: card
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                height: parent.height * 0.58
                radius: 28

                Rectangle {
                    anchors.fill: parent
                    color: M3.surfaceContainerHigh
                }
                Loader {
                    id: scene
                    anchors.fill: parent
                    active: slide.visible
                    source: "file:///usr/share/plasma/wallpapers/org.kernora.shapes/contents/ui/Scene.qml"
                    property real phase: 0.15 + slide.index * 0.17
                    NumberAnimation on phase {
                        running: slide.visible
                        from: 0.15 + slide.index * 0.17
                        to: 0.25 + slide.index * 0.17
                        duration: 12000
                    }
                    onLoaded: {
                        item.intro = 1;
                        item.phase = Qt.binding(() => scene.phase % 1);
                    }
                }
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: card.bottom
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                anchors.topMargin: 24
                spacing: 8

                MText {
                    Layout.fillWidth: true
                    role: "headlineSmall"
                    text: slide.modelData[0]
                    wrapMode: Text.Wrap
                }
                MText {
                    Layout.fillWidth: true
                    role: "bodyLarge"
                    color: M3.surfaceVariantContent
                    text: slide.modelData[1]
                    wrapMode: Text.Wrap
                }
                Row {
                    Layout.topMargin: 12
                    spacing: 6
                    Repeater {
                        model: presentation.texts.length
                        delegate: Rectangle {
                            required property int index
                            width: index === slide.index ? 20 : 6
                            height: 6
                            radius: 3
                            color: index === slide.index ? M3.primary : M3.surfaceContainerHighest
                        }
                    }
                }
            }
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }
    function onLeave() {}
}
