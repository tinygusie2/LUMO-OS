var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.lumo.shapes";
}

var panel = new Panel;
panel.location = "bottom";
panel.height = 56;
panel.floating = true;
panel.lengthMode = "fill";
panel.hiding = "none";
panel.opacity = "translucent";

var launcher = panel.addWidget("org.lumo.launcher");
launcher.globalShortcut = "Alt+Space";

panel.addWidget("org.kde.plasma.panelspacer");
panel.addWidget("org.kde.plasma.icontasks");
panel.addWidget("org.kde.plasma.panelspacer");

var tray = panel.addWidget("org.kde.plasma.systemtray");
var trayContainmentId = tray.readConfig("SystrayContainmentId");
if (trayContainmentId) {
    var trayContainment = desktopById(trayContainmentId);
    trayContainment.currentConfigGroup = ["General"];
    trayContainment.writeConfig("knownItems", [
        "org.kde.plasma.battery",
        "org.kde.plasma.bluetooth",
        "org.kde.plasma.brightness",
        "org.kde.plasma.cameraindicator",
        "org.kde.plasma.clipboard",
        "org.kde.plasma.devicenotifier",
        "org.kde.plasma.keyboardlayout",
        "org.kde.plasma.manage-inputmethod",
        "org.kde.plasma.mediacontroller",
        "org.kde.plasma.networkmanagement",
        "org.kde.plasma.notifications",
        "org.kde.plasma.printmanager",
        "org.kde.plasma.vault",
        "org.kde.plasma.volume",
        "org.kde.kscreen",
        "org.kde.kdeconnect"
    ]);
    trayContainment.writeConfig("extraItems", []);
    trayContainment.writeConfig("scaleIconsToFit", false);
}

var notifications = panel.addWidget("org.kde.plasma.notifications");
notifications.globalShortcut = "Meta+N";

var quickSettings = panel.addWidget("org.lumo.quicksettings");
quickSettings.globalShortcut = "Meta+A";

var clipboard = panel.addWidget("org.lumo.clipboard");
clipboard.globalShortcut = "Meta+V";
var emoji = panel.addWidget("org.lumo.clipboard");
emoji.currentConfigGroup = ["General"];
emoji.writeConfig("startPage", "emoji");
emoji.globalShortcut = "Meta+.";
