/*
    SPDX-FileCopyrightText: 2026 Lumo contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.lumo.m3
import org.lumo.ui
import org.lumo.system

AppWindow {
    id: app

    width: 1100
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: i18n("Task Manager")

    readonly property bool narrow: width < 900
    readonly property int samples: 60
    readonly property var speeds: ({ high: 500, normal: 1000, low: 4000, paused: 0 })
    readonly property int interval: speeds[String(speedEntry.value)] !== undefined ? speeds[String(speedEntry.value)] : 1000

    property string view: String(viewEntry.value)
    property var snapshot: ({ cpu: 0, cores: [], memoryTotal: 0, memoryUsed: 0, gpu: -1, disk: 0, disks: [], received: 0, sent: 0, networks: [], processes: [] })
    readonly property var hardware: Tasks.hardware()
    property string sortKey: "cpu"
    property bool sortAscending: false
    property string detailSortKey: "name"
    property bool detailSortAscending: true
    property string serviceSortKey: "name"
    property bool serviceSortAscending: true
    property string selectedKey: ""
    property var expanded: ({})
    property var closedSections: ({})
    property string resource: "cpu"
    property bool logicalProcessors: false
    property var cpuHistory: []
    property var coreHistory: []
    property var memoryHistory: []
    property var gpuHistory: []
    property var diskHistory: ({})
    property var networkHistory: ({})
    property int startupRevision: 0
    property var services: []
    property bool servicesLoading: false
    property bool primed: false

    readonly property string query: search.text.trim().toLowerCase()
    readonly property var processModel: buildModel()
    readonly property var selectedTarget: processModel.targets[selectedKey] || null

    ConfigEntry { id: speedEntry; file: "lumo-tasksrc"; group: "General"; key: "UpdateSpeed"; defaultValue: "normal" }
    ConfigEntry { id: viewEntry; file: "lumo-tasksrc"; group: "General"; key: "View"; defaultValue: "processes" }

    function handleArguments(args: var): void {}

    function show(page: string): void {
        view = page;
        viewEntry.value = page;
        if (page === "services") {
            loadServices();
        }
    }

    function push(list: var, value: real): var {
        const next = list.concat([value]);
        return next.length > samples ? next.slice(next.length - samples) : next;
    }

    function refresh(): void {
        const data = Tasks.sample();
        snapshot = data;
        if (!primed) {
            primed = true;
            return;
        }
        cpuHistory = push(cpuHistory, data.cpu);
        coreHistory = data.cores.map((value, index) => push(coreHistory[index] || [], value));
        memoryHistory = push(memoryHistory, data.memoryTotal > 0 ? 100 * data.memoryUsed / data.memoryTotal : 0);
        gpuHistory = push(gpuHistory, Math.max(0, data.gpu));
        const disks = {};
        for (const disk of data.disks) {
            const before = diskHistory[disk.name] || { active: [], read: [], write: [] };
            disks[disk.name] = { active: push(before.active, disk.active), read: push(before.read, disk.read), write: push(before.write, disk.write) };
        }
        diskHistory = disks;
        const networks = {};
        for (const network of data.networks) {
            const before = networkHistory[network.name] || { received: [], sent: [] };
            networks[network.name] = { received: push(before.received, network.received), sent: push(before.sent, network.sent) };
        }
        networkHistory = networks;
    }

    function bytes(value: real): string {
        const units = [i18n("B"), i18n("KB"), i18n("MB"), i18n("GB"), i18n("TB")];
        let size = value;
        let unit = 0;
        while (size >= 1024 && unit < units.length - 1) {
            size /= 1024;
            unit += 1;
        }
        return (unit === 0 ? Math.round(size) : size.toFixed(size < 10 ? 1 : 0)) + " " + units[unit];
    }

    function rate(value: real): string {
        return i18n("%1/s", bytes(value));
    }

    function bits(value: real): string {
        const units = [i18n("bit/s"), i18n("kbit/s"), i18n("Mbit/s"), i18n("Gbit/s")];
        let size = value * 8;
        let unit = 0;
        while (size >= 1000 && unit < units.length - 1) {
            size /= 1000;
            unit += 1;
        }
        return (unit === 0 ? Math.round(size) : size.toFixed(size < 10 ? 1 : 0)) + " " + units[unit];
    }

    function percent(value: real): string {
        return i18n("%1%", Math.round(value));
    }

    function duration(seconds: real): string {
        const total = Math.floor(seconds);
        const pad = value => String(value).padStart(2, "0");
        return Math.floor(total / 86400) + ":" + pad(Math.floor(total / 3600) % 24) + ":" + pad(Math.floor(total / 60) % 60) + ":" + pad(total % 60);
    }

    function speed(mhz: real): string {
        return mhz > 0 ? i18n("%1 GHz", (mhz / 1000).toFixed(2)) : i18n("Not reported");
    }

    function stateText(state: string): string {
        switch (state) {
        case "R": return i18n("Running");
        case "S": return i18n("Sleeping");
        case "D": return i18n("Waiting for disk");
        case "T": case "t": return i18n("Suspended");
        case "Z": return i18n("Ended");
        case "I": return i18n("Idle");
        default: return state;
        }
    }

    function priorityText(nice: int): string {
        if (nice <= -10) return i18n("High");
        if (nice < 0) return i18n("Above normal");
        if (nice === 0) return i18n("Normal");
        if (nice < 10) return i18n("Below normal");
        return i18n("Low");
    }

    function compare(key: string, ascending: bool): var {
        return (a, b) => {
            const left = a[key];
            const right = b[key];
            const order = typeof left === "string" ? left.localeCompare(right) : left - right;
            return (ascending ? order : -order) || a.name.localeCompare(b.name);
        };
    }

    function sortBy(key: string): void {
        if (sortKey === key) {
            sortAscending = !sortAscending;
        } else {
            sortKey = key;
            sortAscending = key === "name" || key === "status";
        }
    }

    function matches(process: var): bool {
        return query.length === 0 || process.name.toLowerCase().includes(query)
            || process.appName.toLowerCase().includes(query)
            || process.command.toLowerCase().includes(query)
            || String(process.pid) === query;
    }

    function summarize(key: string, name: string, icon: string, processes: var, depth: int): var {
        let cpu = 0;
        let memory = 0;
        let disk = -1;
        for (const process of processes) {
            cpu += process.cpu;
            memory += process.memory;
            if (process.disk >= 0) {
                disk = Math.max(0, disk) + process.disk;
            }
        }
        const efficient = processes.every(p => p.nice >= 19);
        const suspended = processes.every(p => p.state === "T" || p.state === "t");
        return {
            key: key,
            name: name,
            icon: icon,
            depth: depth,
            count: processes.length,
            cpu: cpu,
            memory: memory,
            disk: disk,
            efficient: efficient,
            status: suspended ? i18n("Suspended") : efficient ? i18n("Efficiency mode") : "",
            mine: processes.every(p => p.mine),
            pids: processes.map(p => p.pid),
            main: processes.reduce((a, b) => a.pid < b.pid ? a : b)
        };
    }

    function buildModel(): var {
        const targets = {};
        const groups = { apps: {}, background: {}, system: {} };
        for (const process of snapshot.processes) {
            targets["proc:" + process.pid] = summarize("proc:" + process.pid, process.name, process.appIcon || process.name, [process], 1);
            const section = !process.mine ? "system" : process.app.length > 0 && !process.autostarted ? "apps" : "background";
            const id = process.app.length > 0 ? "app:" + process.app
                : process.unit.endsWith(".service") ? "unit:" + process.unit : "pid:" + process.pid;
            const key = section + "/" + id;
            if (!groups[section][key]) {
                groups[section][key] = { name: process.appName, icon: process.appIcon, processes: [] };
            }
            groups[section][key].processes.push(process);
        }

        const titles = { apps: i18n("Apps"), background: i18n("Background processes"), system: i18n("System processes") };
        const rows = [];
        for (const section of ["apps", "background", "system"]) {
            const list = [];
            for (const key in groups[section]) {
                const group = groups[section][key];
                const main = group.processes.reduce((a, b) => a.pid < b.pid ? a : b);
                const summary = summarize(key, group.name || main.name, group.icon || main.name, group.processes, 0);
                targets[key] = summary;
                const visible = group.processes.filter(p => matches(p));
                if (visible.length === 0 && !(query.length > 0 && summary.name.toLowerCase().includes(query))) {
                    continue;
                }
                summary.children = (query.length > 0 && visible.length > 0 ? visible : group.processes)
                    .map(p => targets["proc:" + p.pid]);
                summary.open = expanded[key] === true || (query.length > 0 && visible.length < group.processes.length && visible.length > 0);
                list.push(summary);
            }
            if (list.length === 0) {
                continue;
            }
            const open = closedSections[section] !== true;
            rows.push({ kind: "section", key: "section/" + section, section: section, name: titles[section], count: list.length, open: open });
            if (!open) {
                continue;
            }
            const order = compare(sortKey, sortAscending);
            list.sort(order);
            for (const group of list) {
                rows.push(Object.assign({ kind: "row" }, group));
                if (group.count > 1 && group.open) {
                    for (const child of group.children.slice().sort(order)) {
                        rows.push(Object.assign({ kind: "row" }, child));
                    }
                }
            }
        }
        return { rows: rows, targets: targets };
    }

    readonly property var detailRows: {
        const rows = snapshot.processes.filter(p => matches(p)).map(p => ({
            key: "proc:" + p.pid,
            name: p.name,
            pid: p.pid,
            status: stateText(p.state),
            user: p.user,
            cpu: p.cpu,
            memory: p.memory,
            threads: p.threads,
            nice: p.nice,
            command: p.command
        }));
        return rows.sort(compare(detailSortKey, detailSortAscending));
    }

    readonly property var serviceRows: services
        .filter(s => query.length === 0 || s.name.toLowerCase().includes(query) || s.description.toLowerCase().includes(query))
        .sort(compare(serviceSortKey, serviceSortAscending))

    function toggle(key: string): void {
        const next = Object.assign({}, expanded);
        next[key] = !(expanded[key] === true);
        expanded = next;
    }

    function toggleSection(section: string): void {
        const next = Object.assign({}, closedSections);
        next[section] = !(closedSections[section] === true);
        closedSections = next;
    }

    function endTask(target: var, force: bool): void {
        if (!target) {
            return;
        }
        const refused = Tasks.endAll(target.pids, force);
        if (refused.length === 0) {
            showMessage(i18n("Ended %1", target.name), "", null);
            if (selectedKey === target.key) {
                selectedKey = "";
            }
            refresh();
            return;
        }
        Process.run("pkexec", ["kill", "-s", force ? "KILL" : "TERM"].concat(refused.map(String)), code => {
            showMessage(code === 0 ? i18n("Ended %1", target.name) : i18n("Couldn't end %1", target.name), "", null);
            refresh();
        });
    }

    function setEfficiency(target: var, on: bool): void {
        if (!target) {
            return;
        }
        const refused = Tasks.setEfficiency(target.pids, on);
        const done = () => {
            showMessage(on ? i18n("%1 runs in efficiency mode", target.name) : i18n("%1 runs at normal priority", target.name), "", null);
            refresh();
        };
        if (refused.length === 0) {
            done();
            return;
        }
        Process.run("pkexec", ["renice", "-n", on ? "19" : "0", "-p"].concat(refused.map(String)), code => {
            if (code === 0) {
                done();
            } else {
                showMessage(i18n("Couldn't change the priority of %1", target.name), "", null);
            }
        });
    }

    function openLocation(target: var): void {
        const exe = Tasks.details(target.main.pid).exe;
        if (!exe || exe.length === 0) {
            showMessage(i18n("Couldn't find where %1 is stored", target.name), "", null);
            return;
        }
        Process.openUrl("file://" + exe.substring(0, exe.lastIndexOf("/")));
    }

    function searchOnline(target: var): void {
        Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(target.main.name + " linux"));
    }

    function goToDetails(target: var): void {
        selectedKey = "proc:" + target.main.pid;
        search.text = "";
        show("details");
    }

    function showProperties(target: var): void {
        properties.target = target;
        properties.info = Tasks.details(target.main.pid);
        properties.open();
    }

    function openMenu(target: var): void {
        selectedKey = target.key;
        processMenu.target = target;
        processMenu.popup();
    }

    function runTask(text: string): void {
        const command = text.trim();
        if (command.length === 0) {
            return;
        }
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(command)) {
            Process.openUrl(command);
            return;
        }
        const words = (command.match(/"[^"]*"|'[^']*'|\S+/g) || []).map(w => w.replace(/^["']|["']$/g, ""));
        const program = words[0].startsWith("/") ? words[0] : Process.findExecutable(words[0]);
        if (program.length > 0 && Process.startDetached(program, words.slice(1))) {
            return;
        }
        if (words.length === 1 && words[0].startsWith("/")) {
            Process.openUrl("file://" + words[0]);
            return;
        }
        showMessage(i18n("Couldn't find %1", words[0]), "", null);
    }

    function loadServices(): void {
        if (servicesLoading) {
            return;
        }
        servicesLoading = true;
        const result = [];
        const parse = (output, user) => {
            try {
                for (const unit of JSON.parse(output)) {
                    result.push({
                        unit: unit.unit,
                        name: unit.unit.replace(/\.service$/, ""),
                        description: unit.description || "",
                        active: unit.active,
                        sub: unit.sub,
                        status: serviceStatus(unit.active, unit.sub),
                        user: user,
                        type: user ? i18n("Yours") : i18n("System")
                    });
                }
            } catch (error) {
            }
        };
        const listing = ["list-units", "--type=service", "--all", "--output=json", "--no-pager"];
        Process.run("systemctl", listing, (code, output) => {
            parse(output, false);
            Process.run("systemctl", ["--user"].concat(listing), (userCode, userOutput) => {
                parse(userOutput, true);
                services = result;
                servicesLoading = false;
            });
        });
    }

    function serviceStatus(active: string, sub: string): string {
        if (active === "active") return sub === "running" ? i18n("Running") : i18n("Active");
        if (active === "failed") return i18n("Failed");
        if (active === "activating") return i18n("Starting");
        if (active === "deactivating") return i18n("Stopping");
        return i18n("Stopped");
    }

    function serviceAction(service: var, action: string): void {
        const done = {
            start: i18n("Started %1", service.name),
            stop: i18n("Stopped %1", service.name),
            restart: i18n("Restarted %1", service.name)
        };
        const failed = {
            start: i18n("Couldn't start %1", service.name),
            stop: i18n("Couldn't stop %1", service.name),
            restart: i18n("Couldn't restart %1", service.name)
        };
        Process.run("systemctl", (service.user ? ["--user"] : []).concat([action, service.unit]), code => {
            showMessage(code === 0 ? done[action] : failed[action], "", null);
            loadServices();
        });
    }

    Component.onCompleted: {
        refresh();
        if (view === "services") {
            loadServices();
        }
    }

    Timer {
        id: refreshTimer
        interval: Math.max(250, app.interval)
        running: app.interval > 0
        repeat: true
        onTriggered: app.refresh()
    }

    Timer {
        interval: 5000
        running: app.view === "services" && app.interval > 0
        repeat: true
        onTriggered: app.loadServices()
    }

    Shortcut {
        sequence: "Delete"
        enabled: app.selectedTarget !== null && (app.view === "processes" || app.view === "details")
        onActivated: app.endTask(app.selectedTarget, false)
    }
    Shortcut {
        sequence: "Shift+Delete"
        enabled: app.selectedTarget !== null && (app.view === "processes" || app.view === "details")
        onActivated: app.endTask(app.selectedTarget, true)
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: { if (app.view === "performance" || app.view === "startup") app.show("processes"); search.forceActiveFocus(); } }
    Shortcut { sequence: "F5"; onActivated: { app.refresh(); if (app.view === "services") app.loadServices(); } }
    Shortcut { sequence: "Ctrl+N"; onActivated: runDialog.open() }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.show("processes") }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.show("performance") }
    Shortcut { sequence: "Ctrl+3"; onActivated: app.show("startup") }
    Shortcut { sequence: "Ctrl+4"; onActivated: app.show("details") }
    Shortcut { sequence: "Ctrl+5"; onActivated: app.show("services") }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        ColumnLayout {
            Layout.preferredWidth: app.narrow ? 64 : 220
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 2

            Repeater {
                model: [
                    { value: "processes", label: i18n("Processes"), icon: "view-app-grid" },
                    { value: "performance", label: i18n("Performance"), icon: "lumo-speed" },
                    { value: "startup", label: i18n("Startup apps"), icon: "system-run" },
                    { value: "details", label: i18n("Details"), icon: "view-list-details" },
                    { value: "services", label: i18n("Services"), icon: "preferences-system-session-services" }
                ]
                delegate: NavigationItem {
                    id: navigation
                    required property var modelData
                    Layout.fillWidth: true
                    title: app.narrow ? "" : modelData.label
                    icon: modelData.icon
                    current: app.view === modelData.value
                    Accessible.name: modelData.label
                    QQC2.ToolTip.text: modelData.label
                    QQC2.ToolTip.visible: app.narrow && hoverTip.hovered
                    QQC2.ToolTip.delay: 600
                    HoverHandler { id: hoverTip }
                    onClicked: app.show(modelData.value)
                }
            }

            Item { Layout.fillHeight: true }

            NavigationItem {
                Layout.fillWidth: true
                title: app.narrow ? "" : i18n("Run new task")
                icon: "window-new"
                Accessible.name: i18n("Run new task")
                onClicked: runDialog.open()
            }
            NavigationItem {
                Layout.fillWidth: true
                title: app.narrow ? "" : i18n("Update speed")
                subtitle: app.narrow ? "" : app.speedLabel(String(speedEntry.value))
                icon: app.interval > 0 ? "view-refresh" : "media-playback-pause"
                Accessible.name: i18n("Update speed")
                onClicked: speedMenu.popup()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MText {
                    role: "titleLarge"
                    text: ({ processes: i18n("Processes"), performance: i18n("Performance"), startup: i18n("Startup apps"), details: i18n("Details"), services: i18n("Services") })[app.view] || ""
                }
                Item { Layout.fillWidth: true }
                SearchField {
                    id: search
                    Layout.preferredWidth: app.narrow ? 220 : 320
                    visible: app.view === "processes" || app.view === "details" || app.view === "services"
                    placeholderText: app.view === "services" ? i18n("Search services") : i18n("Search by name or PID")
                }
                QQC2.Button {
                    visible: app.view === "processes" || app.view === "details"
                    text: i18n("End task")
                    icon.name: "process-stop"
                    enabled: app.selectedTarget !== null
                    onClicked: app.endTask(app.selectedTarget, false)
                }
                QQC2.Button {
                    visible: app.view === "processes" || app.view === "details"
                    text: i18n("Efficiency mode")
                    icon.name: "power-profile-power-saver"
                    flat: true
                    checked: app.selectedTarget !== null && app.selectedTarget.efficient
                    enabled: app.selectedTarget !== null
                    onClicked: app.setEfficiency(app.selectedTarget, !app.selectedTarget.efficient)
                }
                IconButton {
                    visible: app.view === "services"
                    iconName: "view-refresh"
                    text: i18n("Refresh")
                    onClicked: app.loadServices()
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: ["processes", "performance", "startup", "details", "services"].indexOf(app.view)

                Table {
                    id: processTable
                    indent: 52
                    columns: [
                        { key: "name", label: i18n("Name"), fill: true },
                        { key: "status", label: i18n("Status"), width: 130, hidden: app.narrow },
                        { key: "cpu", label: i18n("CPU"), total: app.percent(app.snapshot.cpu), width: 80, right: true },
                        { key: "memory", label: i18n("Memory"), total: app.percent(app.snapshot.memoryTotal > 0 ? 100 * app.snapshot.memoryUsed / app.snapshot.memoryTotal : 0), width: 100, right: true },
                        { key: "disk", label: i18n("Disk"), total: app.percent(Math.max(0, ...app.snapshot.disks.map(d => d.active))), width: 100, right: true }
                    ]
                    sortKey: app.sortKey
                    sortAscending: app.sortAscending
                    onSort: key => app.sortBy(key)
                    rows: app.processModel.rows
                    emptyText: app.query.length > 0 ? i18n("No processes match your search") : ""

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool isSection: modelData.kind === "section"
                        width: ListView.view.width
                        height: isSection ? 40 : 44
                        color: isSection ? "transparent"
                            : app.selectedKey === modelData.key ? M3.secondaryContainer
                            : rowHover.hovered ? M3.withAlpha(M3.surfaceContent, 0.06) : "transparent"

                        HoverHandler { id: rowHover }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: {
                                if (row.isSection) {
                                    app.toggleSection(row.modelData.section);
                                } else {
                                    app.selectedKey = row.modelData.key;
                                }
                            }
                            onDoubleTapped: {
                                if (!row.isSection && row.modelData.count > 1) {
                                    app.toggle(row.modelData.key);
                                }
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            enabled: !row.isSection
                            onTapped: app.openMenu(row.modelData)
                        }
                        TapHandler {
                            acceptedDevices: PointerDevice.TouchScreen
                            enabled: !row.isSection
                            onLongPressed: app.openMenu(row.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 20
                            spacing: 12
                            visible: row.isSection

                            MIcon {
                                size: 20
                                source: row.modelData.open ? "arrow-down" : "arrow-right"
                                color: M3.surfaceVariantContent
                            }
                            MText {
                                Layout.fillWidth: true
                                role: "titleSmall"
                                color: M3.primary
                                text: i18n("%1 (%2)", row.modelData.name, row.modelData.count)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12 + (row.modelData.depth || 0) * 32
                            anchors.rightMargin: 20
                            spacing: 12
                            visible: !row.isSection

                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                IconButton {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    visible: !row.isSection && row.modelData.count > 1
                                    iconName: row.modelData.open ? "arrow-down" : "arrow-right"
                                    text: row.modelData.open ? i18n("Collapse") : i18n("Expand")
                                    onClicked: app.toggle(row.modelData.key)
                                }
                            }
                            AppIcon {
                                size: 24
                                name: row.isSection ? "" : row.modelData.icon
                            }
                            MText {
                                Layout.fillWidth: true
                                role: "bodyLarge"
                                text: row.isSection ? "" : row.modelData.count > 1 ? i18n("%1 (%2)", row.modelData.name, row.modelData.count) : row.modelData.name
                            }
                            MText {
                                Layout.preferredWidth: 130
                                visible: !app.narrow
                                role: "bodyMedium"
                                color: row.modelData.efficient ? M3.tertiary : M3.surfaceVariantContent
                                text: row.modelData.status || ""
                            }
                            HeatCell {
                                Layout.preferredWidth: 80
                                level: (row.modelData.cpu || 0) / 100
                                text: (row.modelData.cpu || 0).toFixed(1) + "%"
                            }
                            HeatCell {
                                Layout.preferredWidth: 100
                                level: app.snapshot.memoryTotal > 0 ? 4 * (row.modelData.memory || 0) / app.snapshot.memoryTotal : 0
                                text: app.bytes(row.modelData.memory || 0)
                            }
                            HeatCell {
                                Layout.preferredWidth: 100
                                level: (row.modelData.disk || 0) / (50 * 1024 * 1024)
                                text: row.modelData.disk >= 0 ? i18n("%1/s", app.bytes(row.modelData.disk)) : "—"
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: 12

                    QQC2.ScrollView {
                        Layout.preferredWidth: app.narrow ? 200 : 260
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                        Column {
                            width: parent.width
                            spacing: 4

                            ResourceTile {
                                key: "cpu"
                                title: i18n("CPU")
                                value: i18n("%1  %2", app.percent(app.snapshot.cpu), app.speed(app.snapshot.speed))
                                series: [{ points: app.cpuHistory, color: M3.primary }]
                            }
                            ResourceTile {
                                key: "memory"
                                title: i18n("Memory")
                                value: i18n("%1 / %2 (%3)", app.bytes(app.snapshot.memoryUsed), app.bytes(app.snapshot.memoryTotal), app.percent(app.memoryHistory[app.memoryHistory.length - 1] || 0))
                                series: [{ points: app.memoryHistory, color: M3.tertiary }]
                            }
                            Repeater {
                                model: app.snapshot.disks
                                delegate: ResourceTile {
                                    required property var modelData
                                    required property int index
                                    key: "disk:" + modelData.name
                                    title: i18n("Disk %1 (%2)", index, modelData.name)
                                    value: i18n("%1  %2", app.diskKind(modelData), app.percent(modelData.active))
                                    series: [{ points: (app.diskHistory[modelData.name] || {}).active || [], color: M3.secondary }]
                                }
                            }
                            Repeater {
                                model: app.snapshot.networks
                                delegate: ResourceTile {
                                    required property var modelData
                                    key: "net:" + modelData.name
                                    title: modelData.wireless ? i18n("Wi-Fi") : i18n("Ethernet")
                                    value: modelData.connected ? i18n("Send %1  Receive %2", app.bits(modelData.sent), app.bits(modelData.received)) : i18n("Not connected")
                                    series: [
                                        { points: (app.networkHistory[modelData.name] || {}).received || [], color: M3.primary },
                                        { points: (app.networkHistory[modelData.name] || {}).sent || [], color: M3.tertiary, dashed: true }
                                    ]
                                    maximum: Math.max(16 * 1024, ...((app.networkHistory[modelData.name] || {}).received || []), ...((app.networkHistory[modelData.name] || {}).sent || []))
                                }
                            }
                            ResourceTile {
                                key: "gpu"
                                title: i18n("GPU")
                                value: app.snapshot.gpu >= 0 ? app.percent(app.snapshot.gpu) : i18n("Not reported")
                                series: [{ points: app.gpuHistory, color: M3.secondary }]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: M3.classic ? M3.cornerCard : 24
                        color: M3.surfaceContainer

                        Loader {
                            anchors.fill: parent
                            anchors.margins: 20
                            sourceComponent: app.resource === "memory" ? memoryPane
                                : app.resource.startsWith("disk:") ? diskPane
                                : app.resource.startsWith("net:") ? networkPane
                                : app.resource === "gpu" ? gpuPane : cpuPane
                        }
                    }
                }

                QQC2.ScrollView {
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width
                        spacing: 12

                        MText {
                            Layout.fillWidth: true
                            role: "bodyMedium"
                            color: M3.surfaceVariantContent
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                            text: i18n("These apps start when you log in. Turning one off makes logging in faster.")
                        }

                        Group {
                            Layout.fillWidth: true
                            Repeater {
                                model: { app.startupRevision; return Autostart.entries(); }
                                delegate: ListItem {
                                    id: startupRow
                                    required property var modelData
                                    title: modelData.name
                                    subtitle: modelData.comment || ""
                                    leading: Component {
                                        AppIcon {
                                            name: startupRow.modelData.icon || ""
                                        }
                                    }
                                    checkable: true
                                    checked: modelData.enabled
                                    onToggled: on => {
                                        Autostart.setEnabled(modelData.id, on);
                                        app.startupRevision += 1;
                                    }
                                }
                            }
                        }
                    }
                }

                Table {
                    columns: [
                        { key: "name", label: i18n("Name"), fill: true },
                        { key: "pid", label: i18n("PID"), width: 60, right: true },
                        { key: "status", label: i18n("Status"), width: 110, hidden: app.narrow },
                        { key: "user", label: i18n("User"), width: 90 },
                        { key: "cpu", label: i18n("CPU"), width: 50, right: true },
                        { key: "memory", label: i18n("Memory"), width: 80, right: true },
                        { key: "threads", label: i18n("Threads"), width: 60, right: true, hidden: app.narrow },
                        { key: "nice", label: i18n("Priority"), width: 90, hidden: app.narrow }
                    ]
                    sortKey: app.detailSortKey
                    sortAscending: app.detailSortAscending
                    onSort: key => {
                        if (app.detailSortKey === key) {
                            app.detailSortAscending = !app.detailSortAscending;
                        } else {
                            app.detailSortKey = key;
                            app.detailSortAscending = key === "name" || key === "user" || key === "status" || key === "pid";
                        }
                    }
                    rows: app.detailRows
                    emptyText: app.query.length > 0 ? i18n("No processes match your search") : ""

                    delegate: Rectangle {
                        id: detailRow
                        required property var modelData
                        width: ListView.view.width
                        height: 36
                        color: app.selectedKey === modelData.key ? M3.secondaryContainer
                            : detailHover.hovered ? M3.withAlpha(M3.surfaceContent, 0.06) : "transparent"

                        HoverHandler { id: detailHover }
                        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: app.selectedKey = detailRow.modelData.key }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                const target = app.processModel.targets[detailRow.modelData.key];
                                if (target) {
                                    app.openMenu(target);
                                }
                            }
                        }

                        QQC2.ToolTip.text: modelData.command
                        QQC2.ToolTip.visible: detailHover.hovered && modelData.command.length > 0
                        QQC2.ToolTip.delay: 1000

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 12
                            MText { Layout.fillWidth: true; role: "bodyMedium"; text: detailRow.modelData.name }
                            MText { Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; role: "bodyMedium"; text: detailRow.modelData.pid }
                            MText { Layout.preferredWidth: 110; visible: !app.narrow; role: "bodyMedium"; color: M3.surfaceVariantContent; text: detailRow.modelData.status }
                            MText { Layout.preferredWidth: 90; role: "bodyMedium"; color: M3.surfaceVariantContent; text: detailRow.modelData.user }
                            MText { Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight; role: "bodyMedium"; text: Math.round(detailRow.modelData.cpu) }
                            MText { Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; role: "bodyMedium"; text: app.bytes(detailRow.modelData.memory) }
                            MText { Layout.preferredWidth: 60; visible: !app.narrow; horizontalAlignment: Text.AlignRight; role: "bodyMedium"; text: detailRow.modelData.threads }
                            MText { Layout.preferredWidth: 90; visible: !app.narrow; role: "bodyMedium"; color: M3.surfaceVariantContent; text: app.priorityText(detailRow.modelData.nice) }
                        }
                    }
                }

                Table {
                    columns: [
                        { key: "name", label: i18n("Name"), width: 220 },
                        { key: "description", label: i18n("Description"), fill: true },
                        { key: "status", label: i18n("Status"), width: 100 },
                        { key: "type", label: i18n("Type"), width: 80, hidden: app.narrow },
                        { key: "actions", label: "", width: 40 }
                    ]
                    sortKey: app.serviceSortKey
                    sortAscending: app.serviceSortAscending
                    onSort: key => {
                        if (app.serviceSortKey === key) {
                            app.serviceSortAscending = !app.serviceSortAscending;
                        } else {
                            app.serviceSortKey = key;
                            app.serviceSortAscending = true;
                        }
                    }
                    rows: app.serviceRows
                    emptyText: app.servicesLoading ? i18n("Loading services…") : app.query.length > 0 ? i18n("No services match your search") : i18n("No services found")

                    delegate: Rectangle {
                        id: serviceRow
                        required property var modelData
                        width: ListView.view.width
                        height: 40
                        color: serviceHover.hovered ? M3.withAlpha(M3.surfaceContent, 0.06) : "transparent"

                        HoverHandler { id: serviceHover }
                        TapHandler {
                            acceptedButtons: Qt.RightButton | Qt.LeftButton
                            onTapped: (point, button) => {
                                if (button === Qt.RightButton) {
                                    serviceMenu.service = serviceRow.modelData;
                                    serviceMenu.popup();
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 12
                            MText { Layout.preferredWidth: 220; role: "bodyMedium"; text: serviceRow.modelData.name }
                            MText { Layout.fillWidth: true; role: "bodyMedium"; color: M3.surfaceVariantContent; text: serviceRow.modelData.description }
                            MText {
                                Layout.preferredWidth: 100
                                role: "bodyMedium"
                                color: serviceRow.modelData.active === "failed" ? M3.error
                                    : serviceRow.modelData.active === "active" ? M3.primary : M3.surfaceVariantContent
                                text: serviceRow.modelData.status
                            }
                            MText { Layout.preferredWidth: 80; visible: !app.narrow; role: "bodyMedium"; color: M3.surfaceVariantContent; text: serviceRow.modelData.type }
                            IconButton {
                                iconName: "overflow-menu"
                                text: i18n("More")
                                onClicked: {
                                    serviceMenu.service = serviceRow.modelData;
                                    serviceMenu.popup();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function speedLabel(value: string): string {
        return ({ high: i18n("High"), normal: i18n("Normal"), low: i18n("Low"), paused: i18n("Paused") })[value] || i18n("Normal");
    }

    function diskKind(disk: var): string {
        return disk.removable ? i18n("Removable") : disk.ssd ? i18n("SSD") : i18n("HDD");
    }

    readonly property var currentDisk: app.snapshot.disks.find(d => "disk:" + d.name === app.resource) || null
    readonly property var currentNetwork: app.snapshot.networks.find(n => "net:" + n.name === app.resource) || null

    QQC2.ButtonGroup { id: speedGroup }

    QQC2.Menu {
        id: speedMenu
        QQC2.MenuItem { text: app.speedLabel("high"); checkable: true; QQC2.ButtonGroup.group: speedGroup; checked: String(speedEntry.value) === "high"; onTriggered: speedEntry.value = "high" }
        QQC2.MenuItem { text: app.speedLabel("normal"); checkable: true; QQC2.ButtonGroup.group: speedGroup; checked: String(speedEntry.value) === "normal"; onTriggered: speedEntry.value = "normal" }
        QQC2.MenuItem { text: app.speedLabel("low"); checkable: true; QQC2.ButtonGroup.group: speedGroup; checked: String(speedEntry.value) === "low"; onTriggered: speedEntry.value = "low" }
        QQC2.MenuItem { text: app.speedLabel("paused"); checkable: true; QQC2.ButtonGroup.group: speedGroup; checked: String(speedEntry.value) === "paused"; onTriggered: speedEntry.value = "paused" }
    }

    QQC2.Menu {
        id: processMenu
        property var target: null

        QQC2.MenuItem {
            text: i18n("End task")
            icon.name: "process-stop"
            onTriggered: app.endTask(processMenu.target, false)
        }
        QQC2.MenuItem {
            text: i18n("Force end")
            icon.name: "process-stop"
            onTriggered: app.endTask(processMenu.target, true)
        }
        QQC2.MenuItem {
            text: processMenu.target !== null && processMenu.target.efficient ? i18n("Turn off efficiency mode") : i18n("Efficiency mode")
            icon.name: "power-profile-power-saver"
            onTriggered: app.setEfficiency(processMenu.target, !processMenu.target.efficient)
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: i18n("Go to details")
            icon.name: "view-list-details"
            visible: app.view !== "details"
            height: visible ? implicitHeight : 0
            onTriggered: app.goToDetails(processMenu.target)
        }
        QQC2.MenuItem {
            text: i18n("Open file location")
            icon.name: "folder-open"
            onTriggered: app.openLocation(processMenu.target)
        }
        QQC2.MenuItem {
            text: i18n("Search online")
            icon.name: "preferences-web-browser-shortcuts"
            onTriggered: app.searchOnline(processMenu.target)
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: i18n("Properties")
            icon.name: "help-about"
            onTriggered: app.showProperties(processMenu.target)
        }
    }

    QQC2.Menu {
        id: serviceMenu
        property var service: null

        QQC2.MenuItem {
            text: i18n("Start")
            icon.name: "media-playback-start"
            enabled: serviceMenu.service !== null && serviceMenu.service.active !== "active"
            onTriggered: app.serviceAction(serviceMenu.service, "start")
        }
        QQC2.MenuItem {
            text: i18n("Stop")
            icon.name: "media-playback-stop"
            enabled: serviceMenu.service !== null && serviceMenu.service.active === "active"
            onTriggered: app.serviceAction(serviceMenu.service, "stop")
        }
        QQC2.MenuItem {
            text: i18n("Restart")
            icon.name: "system-reboot"
            onTriggered: app.serviceAction(serviceMenu.service, "restart")
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: i18n("Search online")
            icon.name: "preferences-web-browser-shortcuts"
            onTriggered: Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(serviceMenu.service.unit + " linux"))
        }
    }

    Dialog {
        id: properties
        property var target: null
        property var info: ({})
        readonly property var process: target ? target.main : null
        icon: "help-about"
        title: target ? target.name : ""
        showReject: false
        preferredWidth: 520

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 16
            rowSpacing: 6

            Repeater {
                model: properties.process ? [
                    [i18n("Process ID"), String(properties.process.pid)],
                    [i18n("Parent process ID"), String(properties.process.ppid)],
                    [i18n("User"), properties.process.user],
                    [i18n("Status"), app.stateText(properties.process.state)],
                    [i18n("Priority"), app.priorityText(properties.process.nice)],
                    [i18n("Threads"), String(properties.process.threads)],
                    [i18n("Started"), properties.info.started ? Qt.formatDateTime(properties.info.started, Qt.locale().dateTimeFormat(Locale.ShortFormat)) : "—"],
                    [i18n("Program"), properties.info.exe || "—"],
                    [i18n("Working folder"), properties.info.cwd || "—"],
                    [i18n("Command line"), properties.process.command || "—"],
                    [i18n("Started by"), properties.process.unit || "—"]
                ] : []
                delegate: Item {
                    id: pair
                    required property var modelData
                    required property int index
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    implicitHeight: pairRow.implicitHeight
                    RowLayout {
                        id: pairRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 16
                        MText {
                            Layout.preferredWidth: 150
                            Layout.alignment: Qt.AlignTop
                            role: "bodyMedium"
                            color: M3.surfaceVariantContent
                            text: pair.modelData[0]
                        }
                        QQC2.TextArea {
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            wrapMode: Text.WrapAnywhere
                            background: null
                            padding: 0
                            color: M3.surfaceContent
                            font: M3.bodyMedium
                            text: pair.modelData[1]
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: runDialog
        icon: "window-new"
        title: i18n("Run new task")
        text: i18n("Type the name of a program, folder or internet address.")
        acceptText: i18n("Run")
        acceptEnabled: runField.text.trim().length > 0
        onAccepted: app.runTask(runField.text)
        onOpened: {
            runField.text = "";
            runField.forceActiveFocus();
        }

        QQC2.TextField {
            id: runField
            Layout.fillWidth: true
            placeholderText: i18n("For example: librewolf")
            onAccepted: {
                if (runDialog.acceptEnabled) {
                    runDialog.accept();
                }
            }
        }
    }

    Component {
        id: cpuPane
        ColumnLayout {
            spacing: 12
            PaneHeader { title: i18n("CPU"); device: SystemInfo.cpu }
            RowLayout {
                Layout.fillWidth: true
                MText {
                    Layout.fillWidth: true
                    role: "bodySmall"
                    color: M3.surfaceVariantContent
                    text: app.logicalProcessors ? i18n("Utilisation of each logical processor over %1 seconds", app.historySeconds()) : i18n("Utilisation over %1 seconds", app.historySeconds())
                }
                QQC2.Switch {
                    text: i18n("Logical processors")
                    checked: app.logicalProcessors
                    onToggled: app.logicalProcessors = checked
                }
            }
            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !app.logicalProcessors
                series: [{ points: app.cpuHistory, color: M3.primary }]
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: app.logicalProcessors
                columns: Math.ceil(Math.sqrt(app.coreHistory.length * 2))
                rowSpacing: 6
                columnSpacing: 6
                Repeater {
                    model: app.coreHistory.length
                    delegate: Graph {
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        grid: false
                        series: [{ points: app.coreHistory[index] || [], color: M3.primary }]
                    }
                }
            }
            Stats {
                items: [
                    [i18n("Utilisation"), app.percent(app.snapshot.cpu), true],
                    [i18n("Speed"), app.speed(app.snapshot.speed), true],
                    [i18n("Processes"), String(app.snapshot.processCount || 0), true],
                    [i18n("Threads"), String(app.snapshot.threadCount || 0), true],
                    [i18n("Up time"), app.duration(app.snapshot.uptime || 0), true],
                    [i18n("Maximum speed"), app.speed(app.hardware.maxSpeed), false],
                    [i18n("Sockets"), String(app.hardware.sockets), false],
                    [i18n("Cores"), String(app.hardware.cores), false],
                    [i18n("Logical processors"), String(app.hardware.logical), false],
                    [i18n("Virtualisation"), app.hardware.virtualization ? i18n("Supported") : i18n("Not supported"), false],
                    [i18n("L3 cache"), app.hardware.cache > 0 ? app.bytes(app.hardware.cache) : "—", false]
                ]
            }
        }
    }

    Component {
        id: memoryPane
        ColumnLayout {
            spacing: 12
            PaneHeader { title: i18n("Memory"); device: i18n("%1 in total", app.bytes(app.snapshot.memoryTotal)) }
            MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: i18n("Memory usage over %1 seconds", app.historySeconds()) }
            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                series: [{ points: app.memoryHistory, color: M3.tertiary }]
            }
            MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: i18n("Memory composition") }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: M3.outlineVariant
                clip: true
                Row {
                    anchors.fill: parent
                    anchors.margins: 1
                    Rectangle {
                        width: parent.width * (app.snapshot.memoryTotal > 0 ? app.snapshot.memoryUsed / app.snapshot.memoryTotal : 0)
                        height: parent.height
                        color: M3.withAlpha(M3.tertiary, 0.55)
                    }
                    Rectangle {
                        width: parent.width * (app.snapshot.memoryTotal > 0 ? Math.min(app.snapshot.memoryCached, app.snapshot.memoryAvailable) / app.snapshot.memoryTotal : 0)
                        height: parent.height
                        color: M3.withAlpha(M3.tertiary, 0.2)
                    }
                }
            }
            Stats {
                items: [
                    [i18n("In use"), app.bytes(app.snapshot.memoryUsed), true],
                    [i18n("Available"), app.bytes(app.snapshot.memoryAvailable), true],
                    [i18n("Committed"), i18n("%1 / %2", app.bytes(app.snapshot.committed), app.bytes(app.snapshot.commitLimit)), true],
                    [i18n("Cached"), app.bytes(app.snapshot.memoryCached), true],
                    [i18n("Swap in use"), app.snapshot.swapTotal > 0 ? i18n("%1 / %2", app.bytes(app.snapshot.swapUsed), app.bytes(app.snapshot.swapTotal)) : i18n("No swap"), true]
                ]
            }
        }
    }

    Component {
        id: diskPane
        ColumnLayout {
            readonly property var disk: app.currentDisk || { name: "", model: "", size: 0, active: 0, read: 0, write: 0 }
            readonly property var history: app.diskHistory[disk.name] || { active: [], read: [], write: [] }
            spacing: 12
            PaneHeader { title: i18n("Disk (%1)", parent.disk.name); device: parent.disk.model }
            MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: i18n("Active time over %1 seconds", app.historySeconds()) }
            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                series: [{ points: parent.history.active, color: M3.secondary }]
            }
            MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: i18n("Transfer rate: read (solid) and write (dashed)") }
            Graph {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                maximum: Math.max(1024 * 1024, ...parent.history.read, ...parent.history.write)
                series: [{ points: parent.history.read, color: M3.secondary }, { points: parent.history.write, color: M3.secondary, dashed: true }]
            }
            Stats {
                items: [
                    [i18n("Active time"), app.percent(parent.disk.active), true],
                    [i18n("Read speed"), app.rate(parent.disk.read), true],
                    [i18n("Write speed"), app.rate(parent.disk.write), true],
                    [i18n("Capacity"), app.bytes(parent.disk.size), false],
                    [i18n("Type"), app.diskKind(parent.disk), false]
                ]
            }
        }
    }

    Component {
        id: networkPane
        ColumnLayout {
            readonly property var network: app.currentNetwork || { name: "", wireless: false, connected: false, received: 0, sent: 0, addresses: [], speed: 0, hardware: "" }
            readonly property var history: app.networkHistory[network.name] || { received: [], sent: [] }
            spacing: 12
            PaneHeader { title: parent.network.wireless ? i18n("Wi-Fi") : i18n("Ethernet"); device: parent.network.name }
            MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: i18n("Throughput over %1 seconds: receive (solid) and send (dashed)", app.historySeconds()) }
            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                maximum: Math.max(16 * 1024, ...parent.history.received, ...parent.history.sent)
                series: [{ points: parent.history.received, color: M3.primary }, { points: parent.history.sent, color: M3.tertiary, dashed: true }]
            }
            Stats {
                items: [
                    [i18n("Send"), app.bits(parent.network.sent), true],
                    [i18n("Receive"), app.bits(parent.network.received), true],
                    [i18n("Adapter name"), parent.network.name, false],
                    [i18n("Connection type"), parent.network.wireless ? i18n("Wi-Fi") : i18n("Ethernet"), false],
                    [i18n("Link speed"), parent.network.speed > 0 ? i18n("%1 Mbit/s", parent.network.speed) : "—", false],
                    [i18n("IPv4 address"), parent.network.addresses.filter(a => !a.includes(":")).join(", ") || "—", false],
                    [i18n("IPv6 address"), parent.network.addresses.filter(a => a.includes(":")).join(", ") || "—", false],
                    [i18n("Hardware address"), parent.network.hardware || "—", false]
                ]
            }
        }
    }

    Component {
        id: gpuPane
        ColumnLayout {
            spacing: 12
            PaneHeader { title: i18n("GPU"); device: SystemInfo.graphics }
            MText {
                Layout.fillWidth: true
                role: "bodySmall"
                color: M3.surfaceVariantContent
                wrapMode: Text.Wrap
                text: app.snapshot.gpu >= 0 ? i18n("Utilisation over %1 seconds", app.historySeconds()) : i18n("This graphics driver doesn't report how busy it is.")
            }
            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                series: [{ points: app.gpuHistory, color: M3.secondary }]
            }
            Stats {
                items: [
                    [i18n("Utilisation"), app.snapshot.gpu >= 0 ? app.percent(app.snapshot.gpu) : i18n("Not reported"), true],
                    [i18n("Dedicated memory"), app.snapshot.gpuMemoryTotal > 0 ? i18n("%1 / %2", app.bytes(app.snapshot.gpuMemoryUsed), app.bytes(app.snapshot.gpuMemoryTotal)) : i18n("Not reported"), true]
                ]
            }
        }
    }

    function historySeconds(): int {
        return Math.round(samples * (interval > 0 ? interval : 1000) / 1000);
    }

    component Table: Rectangle {
        id: table
        property var columns: []
        property var rows: []
        property string sortKey
        property bool sortAscending
        property string emptyText
        property int indent: 0
        property Component delegate
        signal sort(string key)

        radius: M3.classic ? M3.cornerCard : 20
        color: M3.surfaceContainer
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 10
                Layout.bottomMargin: 6
                spacing: 12

                Item {
                    visible: table.indent > 0
                    Layout.preferredWidth: table.indent
                }

                Repeater {
                    model: table.columns
                    delegate: ColumnLayout {
                        id: header
                        required property var modelData
                        readonly property bool sorted: table.sortKey === modelData.key
                        visible: !modelData.hidden
                        Layout.alignment: Qt.AlignBottom
                        Layout.fillWidth: modelData.fill === true
                        Layout.preferredWidth: modelData.fill === true ? -1 : modelData.width
                        spacing: 0

                        MText {
                            Layout.fillWidth: true
                            visible: header.modelData.total !== undefined
                            horizontalAlignment: header.modelData.right ? Text.AlignRight : Text.AlignLeft
                            role: "titleMedium"
                            text: header.modelData.total || ""
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            layoutDirection: header.modelData.right ? Qt.RightToLeft : Qt.LeftToRight
                            MText {
                                role: "labelLarge"
                                color: header.sorted ? M3.primary : M3.surfaceVariantContent
                                text: header.modelData.label
                            }
                            MIcon {
                                visible: header.sorted
                                size: 16
                                color: M3.primary
                                source: table.sortAscending ? "arrow-up" : "arrow-down"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        TapHandler { enabled: header.modelData.label.length > 0; onTapped: table.sort(header.modelData.key) }
                        HoverHandler { enabled: header.modelData.label.length > 0; cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.ColumnHeader
                        Accessible.name: header.modelData.label
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: M3.outlineVariant
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: table.rows
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: table.delegate
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                MText {
                    anchors.centerIn: parent
                    visible: list.count === 0 && table.emptyText.length > 0
                    role: "bodyMedium"
                    color: M3.surfaceVariantContent
                    text: table.emptyText
                }
            }
        }
    }

    component HeatCell: Rectangle {
        id: cell
        property real level: 0
        property alias text: label.text
        Layout.fillHeight: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        radius: 6
        color: M3.withAlpha(M3.primary, 0.03 + 0.32 * Math.max(0, Math.min(1, level)))
        MText {
            id: label
            anchors.fill: parent
            anchors.rightMargin: 8
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            role: "bodyMedium"
            color: cell.level >= 0.5 ? M3.error : M3.surfaceContent
        }
    }

    component ResourceTile: Rectangle {
        id: tile
        property string key
        property string title
        property string value
        property var series: []
        property real maximum: 100
        readonly property bool current: app.resource === key

        width: parent ? parent.width : 240
        height: 76
        radius: M3.classic ? M3.cornerCard : 16
        color: current ? M3.secondaryContainer : tileHover.hovered ? M3.withAlpha(M3.surfaceContent, 0.06) : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.PageTab
        Accessible.name: title
        Accessible.description: value
        Keys.onSpacePressed: app.resource = key
        Keys.onReturnPressed: app.resource = key

        HoverHandler { id: tileHover }
        TapHandler { onTapped: app.resource = tile.key }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12
            Graph {
                Layout.preferredWidth: 72
                Layout.fillHeight: true
                grid: false
                maximum: tile.maximum
                series: tile.series
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                MText {
                    Layout.fillWidth: true
                    role: "titleSmall"
                    color: tile.current ? M3.secondaryContainerContent : M3.surfaceContent
                    text: tile.title
                }
                MText {
                    Layout.fillWidth: true
                    role: "bodySmall"
                    color: tile.current ? M3.secondaryContainerContent : M3.surfaceVariantContent
                    text: tile.value
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
            }
        }
    }

    component PaneHeader: RowLayout {
        property alias title: heading.text
        property alias device: name.text
        Layout.fillWidth: true
        spacing: 12
        MText { id: heading; role: "headlineSmall" }
        MText {
            id: name
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            role: "titleMedium"
            color: M3.surfaceVariantContent
        }
    }

    component Stats: Flow {
        id: stats
        property var items: []
        Layout.fillWidth: true
        spacing: 24
        Repeater {
            model: stats.items
            delegate: ColumnLayout {
                required property var modelData
                spacing: 0
                width: modelData[2] ? implicitWidth : Math.max(implicitWidth, 150)
                MText { role: "bodySmall"; color: M3.surfaceVariantContent; text: parent.modelData[0] }
                MText { role: parent.modelData[2] ? "titleLarge" : "bodyLarge"; text: parent.modelData[1] }
            }
        }
    }

    component Graph: Rectangle {
        id: graph
        property var series: []
        property real maximum: 100
        property bool grid: true

        color: M3.withAlpha(M3.primary, 0.03)
        border.width: 1
        border.color: M3.outlineVariant
        radius: grid ? 8 : 4

        onSeriesChanged: canvas.requestPaint()
        onMaximumChanged: canvas.requestPaint()

        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.margins: 1
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.reset();
                if (graph.grid) {
                    context.strokeStyle = M3.withAlpha(M3.outlineVariant, 0.6);
                    context.lineWidth = 1;
                    context.beginPath();
                    for (let i = 1; i < 10; i++) {
                        const y = Math.round(height * i / 10) + 0.5;
                        context.moveTo(0, y);
                        context.lineTo(width, y);
                    }
                    for (let i = 1; i < 6; i++) {
                        const x = Math.round(width * i / 6) + 0.5;
                        context.moveTo(x, 0);
                        context.lineTo(x, height);
                    }
                    context.stroke();
                }
                if (graph.maximum <= 0) {
                    return;
                }
                const step = width / (app.samples - 1);
                for (const line of graph.series) {
                    const points = line.points || [];
                    if (points.length < 2) {
                        continue;
                    }
                    const start = width - (points.length - 1) * step;
                    const y = value => height - Math.min(1, value / graph.maximum) * (height - 2) - 1;
                    if (!line.dashed) {
                        context.beginPath();
                        context.moveTo(start, height);
                        for (let i = 0; i < points.length; i++) {
                            context.lineTo(start + i * step, y(points[i]));
                        }
                        context.lineTo(width, height);
                        context.closePath();
                        context.fillStyle = Qt.rgba(line.color.r, line.color.g, line.color.b, 0.18);
                        context.fill();
                    }
                    context.beginPath();
                    for (let i = 0; i < points.length; i++) {
                        if (i === 0) {
                            context.moveTo(start, y(points[0]));
                        } else {
                            context.lineTo(start + i * step, y(points[i]));
                        }
                    }
                    context.setLineDash(line.dashed ? [4, 3] : []);
                    context.strokeStyle = line.color;
                    context.lineWidth = graph.grid ? 2 : 1.5;
                    context.stroke();
                }
            }
        }
    }
}
