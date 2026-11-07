#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-apps"

fail() {
  printf 'lumo-apps source test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-parsechangelog grep; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done

version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
[[ "$version" == "1.1.86" ]] || fail "unexpected source version"
[[ "$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Distribution)" == "UNRELEASED" ]] \
  || fail "development package must remain UNRELEASED"
[[ "$(<"$package_root/debian/source/format")" == "3.0 (native)" ]] || fail "wrong source format"
[[ -x "$package_root/debian/rules" ]] || fail "debian/rules is not executable"
grep -Fxq 'Package: lumo-apps' "$package_root/debian/control" || fail "binary stanza is missing"

for app in settings files welcome editor photos player calculator screenshot store share; do
  [[ -s "$package_root/apps/$app/qml/Main.qml" ]] || fail "$app has no interface"
  desktop="$package_root/apps/$app/org.lumo.$app.desktop"
  [[ -s "$desktop" ]] || fail "$app has no desktop entry"
  grep -Eq "^Exec=(/usr/bin/)?lumo-$app( |$)" "$desktop" \
    || fail "$app desktop entry does not start lumo-$app"
  grep -q '^Name\[ru\]=' "$desktop" || fail "$app desktop entry has no Russian name"
  grep -q '^Categories=.*KDE' "$desktop" && fail "$app is filed as a KDE application"
  [[ -s "$package_root/src/apps/$app.cpp" ]] || fail "$app has no host"
done
grep -Fq 'key: "receive"' "$package_root/apps/share/qml/Main.qml" \
  && grep -Fq 'key: "send"' "$package_root/apps/share/qml/Main.qml" \
  || fail "Quick Share has no Receive and Send"
grep -Fq '"org.lumo.quickshare", true}' "$package_root/src/apps/share.cpp" \
  || fail "Quick Share does not reuse its window"
grep -q '^NoDisplay=' "$package_root/apps/share/org.lumo.share.desktop" \
  && fail "Quick Share is hidden from the app menu"
grep -Fxq 'X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2' \
  "$package_root/apps/screenshot/org.lumo.screenshot.desktop" \
  || fail "Screenshot is not allowed to ask KWin for screenshots"

[[ -s "$package_root/apps/terminal/qml/Main.qml" ]] || fail "Terminal has no interface"
[[ -s "$package_root/src/apps/terminal.cpp" ]] || fail "Terminal has no host"
for file in terminalview.cpp terminalview.h terminalcolours.cpp terminalcolours.h CMakeLists.txt; do
  [[ -s "$package_root/src/terminal/$file" ]] || fail "Terminal lacks src/terminal/$file"
done
grep -Eq '^ libvterm-dev[, ]*$' "$package_root/debian/control" || fail "missing Terminal build dependency: libvterm-dev"
grep -Fq 'lumo/terminal/lumo.bashrc' "$package_root/src/terminal/terminalview.cpp" \
  && grep -Fq 'data/terminal/lumo.bashrc' "$package_root/CMakeLists.txt" \
  || fail "Terminal does not start bash with the Lumo start-up file"
bash -n "$package_root/data/terminal/lumo.bashrc" || fail "the Terminal start-up file does not parse"
for command in cls dir copy move ren del md rd type ipconfig tasklist where; do
  grep -Eq "^alias $command=" "$package_root/data/terminal/lumo.bashrc" || fail "Terminal does not know the Windows command $command"
done
grep -Eq '^(taskkill|ver|help)\(\)' "$package_root/data/terminal/lumo.bashrc" || fail "Terminal lacks taskkill, ver or help"
grep -Fq 'Process.startDetached("lumo-terminal", [app.folderPath])' "$package_root/apps/files/qml/Main.qml" \
  || fail "Files does not open the Lumo Terminal"
grep -rq alacritty "$package_root/apps" && fail "an app still starts Alacritty"
for language in nl ru; do
  [[ -s "$package_root/po/$language/lumo-terminal.po" ]] || fail "Terminal has no $language translation"
done

if grep -rEn 'M3\.on[A-Z]' "$package_root/apps" >/dev/null; then
  fail "QML uses an M3.on* role; use the *Content spelling"
fi

grep -Fq 'void Appearance::apply(' "$package_root/src/system/appearance.cpp" \
  && grep -Fq 'lumorc' "$package_root/src/system/appearance.cpp" \
  || fail "Appearance cannot switch the Material generation"
grep -Fq 'page.setGeneration(value)' "$package_root/apps/settings/qml/pages/AppearancePage.qml" \
  && grep -Fq 'Appearance.setGeneration(modelData.value' "$package_root/apps/welcome/qml/Main.qml" \
  || fail "Settings and Welcome do not offer the Material generations"
grep -Fq 'Files.liveWallpapers()' "$package_root/apps/settings/qml/pages/AppearancePage.qml" \
  && grep -Fq 'Files.liveWallpapers()' "$package_root/apps/welcome/qml/Main.qml" \
  || fail "Settings and Welcome do not list the live wallpapers"
grep -Fq '!SystemInfo.live && Updates.available' "$package_root/apps/settings/qml/pages/UpdatesPage.qml" \
  && grep -Fq 'org.lumo.installer.desktop' "$package_root/apps/settings/qml/pages/UpdatesPage.qml" \
  || fail "Settings downloads updates in the live session"
[[ "$(grep -c 'Default Applications' "$package_root/src/system/defaultapps.cpp")" -ge 2 ]] \
  || fail "Settings shows a stale default app after choosing one"
[[ ! -e "$package_root/apps/settings/qml/pages/DriversPage.qml" ]] \
  && grep -Fq 'Process.launchApplication("org.lumo.drivers.desktop")' "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  && grep -Fq '"org.lumo.drivers.desktop"' "$package_root/apps/settings/qml/components/Catalog.qml" \
  || fail "Settings does not open the Drivers app"
for page in Main DriversPage DevicesPage DevicePage NvidiaPage UpdatesPage JobBar; do
  [[ -s "$package_root/apps/drivers/qml/$page.qml" ]] || fail "Drivers has no $page"
done
[[ -s "$package_root/src/apps/drivers.cpp" && -s "$package_root/po/ru/lumo-drivers.po" ]] \
  && grep -Fq 'Icon=org.lumo.drivers' "$package_root/apps/drivers/org.lumo.drivers.desktop" \
  && grep -Eq 'set\(LUMO_APPS .* drivers ' "$package_root/CMakeLists.txt" \
  && grep -Fq 'lumo-desktop (>= 1.4.74)' "$package_root/debian/control" \
  || fail "the Drivers app is not packaged"
python3 - "$package_root" <<'PY' || fail "a Drivers string has no translation"
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
po = (root / "po/ru/lumo-drivers.po").read_text()
known = set(re.findall(r'^msgid "(.*)"$', po, re.MULTILINE))
strings = set()
for page in (root / "apps/drivers/qml").glob("*.qml"):
    text = page.read_text()
    strings.update(re.findall(r'\bi18np?\(\s*"((?:[^"\\]|\\.)*)"', text))
    strings.update(re.findall(r'\bi18nc\(\s*"(?:[^"\\]|\\.)*",\s*"((?:[^"\\]|\\.)*)"', text))
missing = sorted(strings - known)
if missing:
    sys.exit(f"untranslated: {missing}")
PY
[[ -s "$package_root/apps/settings/qml/pages/RestorePage.qml" ]] \
  && grep -Fq 'page.open("RestorePage.qml"' "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  || fail "Settings has no Restore points page"
for name in Firewall Locations; do
  [[ -s "$package_root/apps/settings/qml/pages/${name}Page.qml" ]] \
    && grep -Fq "${name}Page.qml" "$package_root/apps/settings/qml/components/Catalog.qml" \
    || fail "Settings has no $name page"
done
grep -Fq 'driverReady' "$package_root/src/updatenotifier/main.cpp" \
  && grep -Fxq '[Event/driverReady]' "$package_root/data/knotifications/lumo-updates.notifyrc" \
  || fail "nobody is told to restart after a driver install"
grep -Fxq ' pkexec,' "$package_root/debian/control" \
  || fail "Settings cannot ask for the driver actions without pkexec"
grep -Fq 'model: Qt.application.screens' "$package_root/apps/screenshot/qml/Main.qml" \
  && grep -Fq 'Screenshot.captureScreen(overlay.screen.name' "$package_root/apps/screenshot/qml/Main.qml" \
  && grep -Fq 'void Screenshot::captureScreen' "$package_root/src/system/screenshot.cpp" \
  && grep -Fq 'LayerShell.Window.screenConfiguration: LayerShell.Window.ScreenFromQWindow' "$package_root/apps/screenshot/qml/Main.qml" \
  && grep -Fxq ' qml6-module-org-kde-layershell,' "$package_root/debian/control" \
  || fail "Screenshot shows one monitor's picture on another"
grep -Fq 'new PlasmaQuick::ConfigView(applet)' "$package_root/src/shell/appletsettings.cpp" \
  && grep -Fq 'add_subdirectory(src/shell)' "$package_root/CMakeLists.txt" \
  && grep -Fxq ' libplasma-dev,' "$package_root/debian/control" \
  || fail "a widget's settings cannot open without ending edit mode"


for dependency in libappstreamqt-dev libflatpak-dev; do
  grep -Eq "^ $dependency[, ]*$" "$package_root/debian/control" || fail "missing Store build dependency: $dependency"
done
for dependency in appstream flatpak; do
  grep -Eq "^ $dependency[, ]*$" "$package_root/debian/control" || fail "missing Store runtime dependency: $dependency"
done
python3 - "$package_root" <<'PY'
import datetime, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
featured = json.loads((p / 'data/store/featured.json').read_text())
assert all(isinstance(ids, list) and ids and len(ids) == len(set(ids)) for ids in featured.values())
notes = json.loads((p / 'data/whatsnew.json').read_text())
assert any('Store' in i['title']['en'] for r in notes for i in r['items'])
assert not any(i['icon'].startswith('org.lumo.') for r in notes for i in r['items'])
for release in notes:
    datetime.date.fromisoformat(release.get('date', release['id'][:10]))
PY

grep -Fq 'readonly property string channelTool: "/usr/libexec/lumo-update-channel"' \
  "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  && grep -Fq 'Process.run("pkexec", [page.channelTool, "set", on ? "demo" : "stable"]' \
  "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  && grep -Fq 'checked: page.channelBusy ? page.channelWanted : page.demo' \
  "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  || fail "Settings cannot turn demo updates on and off"
grep -q lumo-update-channel "$package_root/apps/settings/qml/pages/UpdatesPage.qml" \
  && fail "the demo updates switch is back on the updates page"
grep -Fq 'title: i18n("Early access")' "$package_root/apps/settings/qml/pages/SystemPage.qml" \
  || fail "demo updates are not under Early access in System"
grep -Fq "project(lumo-apps VERSION $version LANGUAGES C CXX)" "$package_root/CMakeLists.txt" \
  || fail "the CMake project version is not $version"
grep -Fq 'AppIconSync icons;' "$package_root/src/updatenotifier/main.cpp" \
  && grep -Fq '"/Lumo/scalable/apps"' "$package_root/src/updatenotifier/appiconsync.cpp" \
  && grep -Fq 'readEntry("themedApps", false)' "$package_root/src/updatenotifier/appiconsync.cpp" \
  && grep -Fq 'connect(KSycoca::self(), &KSycoca::databaseChanged' "$package_root/src/updatenotifier/appiconsync.cpp" \
  && grep -Fq 'service->noDisplay()' "$package_root/src/updatenotifier/appiconsync.cpp" \
  && grep -Fq 'info.absolutePath().contains(QLatin1String("/apps"))' "$package_root/src/updatenotifier/appiconsync.cpp" \
  && grep -Fq 'lumo-app-icons --self-test' "$package_root/debian/rules" \
  || fail "app icons are not made the same size and shape"
for file in Main AppsPage ProcessesPage PerformancePage TaskPage UsageCard; do
  [[ -s "$package_root/apps/taskmanager/qml/$file.qml" ]] || fail "Task Manager lacks $file.qml"
done
grep -Fq 'Procs.ApplicationDataModel {' "$package_root/apps/taskmanager/qml/Main.qml" \
  && grep -Fq 'Procs.ProcessDataModel {' "$package_root/apps/taskmanager/qml/ProcessesPage.qml" \
  && grep -Fq 'Files.exists("file:///proc/" + pid)' "$package_root/apps/taskmanager/qml/Main.qml" \
  && grep -Fq 'Procs.ProcessController.KillSignal' "$package_root/apps/taskmanager/qml/Main.qml" \
  && grep -Fq 'sensorId: "gpu/all/totalVram"' "$package_root/apps/taskmanager/qml/PerformancePage.qml" \
  && grep -Fq 'direction: Charts.XYChart.ZeroAtEnd' "$package_root/apps/taskmanager/qml/UsageCard.qml" \
  && grep -Fq 'fillMode: Charts.HistoryProxySource.FillFromStart' "$package_root/apps/taskmanager/qml/UsageCard.qml" \
  && grep -Fq 'return pid > 0 ? [pid] : [];' "$package_root/apps/taskmanager/qml/TaskPage.qml" \
  && grep -Fq 'onClicked: page.sortKey = key' "$package_root/apps/taskmanager/qml/TaskPage.qml" \
  || fail "Task Manager can't list, end or chart"
grep -Fxq 'X-KDE-Shortcuts=Ctrl+Shift+Esc,Ctrl+Esc' "$package_root/apps/taskmanager/org.lumo.taskmanager.desktop" \
  && grep -Fq 'DESTINATION ${KDE_INSTALL_DATADIR}/kglobalaccel' "$package_root/CMakeLists.txt" \
  && grep -q 'share taskmanager' "$package_root/src/apps/CMakeLists.txt" \
  || fail "Task Manager has no shortcut or is not built"
for dependency in ksystemstats libksysguard-bin qml6-module-org-kde-ksysguard qml6-module-org-kde-kitemmodels qml6-module-org-kde-quickcharts; do
  grep -Eq "^ $dependency,?$" "$package_root/debian/control" || fail "Task Manager needs $dependency"
done
msgfmt --check -o /dev/null "$package_root/po/ru/lumo-taskmanager.po" || fail "the Task Manager translation is broken"
for po in "$package_root"/po/*/*.po; do
  msgfmt --check -o /dev/null "$po" 2>/dev/null || fail "translation does not compile: ${po#"$package_root"/}"
done
grep -Fq 'key: "themedApps"' "$package_root/apps/settings/qml/pages/AppearancePage.qml" \
  && grep -Fq 'msgid "Themed app icons"' "$package_root/po/ru/lumo-settings.po" \
  && grep -Eq '^ qt6-svg-plugins,$' "$package_root/debian/control" \
  || fail "themed app icons cannot be turned on"
grep -Eq '^ lumo-archive \(>= 1\.8\),$' "$package_root/debian/control" \
  || fail "lumo-apps does not require the lumo-archive with Debian's contrib and non-free components"
grep -Fq 'msgid "Demo updates"' "$package_root/po/ru/lumo-settings.po" \
  || fail "the demo updates switch is not translated"

grep -Fq 'void Files::setLockScreenPlugin' "$package_root/src/system/files.cpp" \
  && grep -Fq 'Files.syncGreeterBackground' "$package_root/apps/settings/qml/pages/AppearancePage.qml" \
  || fail "live wallpapers cannot reach the lock and login screens"

grep -Fq 'GreeterSync greeter;' "$package_root/src/updatenotifier/main.cpp" \
  && grep -Fq '/usr/libexec/lumo-greeter-background' "$package_root/src/updatenotifier/greetersync.cpp" \
  && grep -Fq 'plasma-org.kde.plasma.desktop-appletsrc' "$package_root/src/updatenotifier/greetersync.cpp" \
  || fail "the login screen does not follow wallpapers chosen outside Settings"

grep -Fq 'AvatarSync avatar;' "$package_root/src/updatenotifier/main.cpp" \
  && grep -Fq 'lumo/faces/%1.png' "$package_root/src/updatenotifier/avatarsync.cpp" \
  && grep -Fq 'lumo/faces/%1.png' "$package_root/src/system/accounts.cpp" \
  || fail "the Lumo avatar does not follow the colour"
grep -Fq 'wallpaper.colour, wallpaper.mode' "$package_root/src/updatenotifier/greetersync.cpp" \
  || fail "the login screen does not get the colour and theme"
grep -Fq '"/kdedefaults/kdeglobals"' "$package_root/src/updatenotifier/greetersync.cpp" \
  || fail "the login screen turns dark after plasma moves the colour scheme to kdedefaults"

grep -Fq 'MLoadingIndicator {' "$package_root/apps/store/qml/AppPage.qml" \
  || fail "screenshots in Store do not use the loading indicator"
grep -Fq 'component BusyIndicatorOverlay: MLoadingIndicator {' "$package_root/apps/photos/qml/Main.qml" \
  || fail "the photo viewer does not use the loading indicator"
grep -Fq '.filter(m => !internal.includes(m.id) && catalog.resolve(m.id) === null)' "$package_root/apps/settings/qml/pages/ModulesPage.qml" \
  && grep -Fq '"kcm_activities"' "$package_root/apps/settings/qml/pages/ModulesPage.qml" \
  || fail "More settings still lists KDE modules Lumo replaces"
grep -Fq "writeConfig('IntroAt', String(Date.now()));" "$package_root/src/system/files.cpp" \
  || fail "switching a live wallpaper does not mark it for its intro"
grep -Fq 'id: selectionBar' "$package_root/apps/files/qml/Main.qml" \
  && grep -Fq 'active: !fab.collapsed || M3.classic' "$package_root/apps/files/qml/Main.qml" \
  || fail "Files has no selection toolbar or collapsing button"
grep -Fq 'FloatingToolbar {' "$package_root/apps/photos/qml/Main.qml" \
  && grep -Fq 'shown: chrome.shown' "$package_root/apps/photos/qml/Main.qml" \
  || fail "the photo viewer has no floating toolbar"
for file in apps/calculator/qml/Main.qml apps/player/qml/Main.qml apps/photos/qml/Main.qml \
    apps/welcome/qml/Main.qml apps/settings/qml/components/WallpaperTile.qml; do
  ! grep -Fq 'Behavior on radius' "$package_root/$file" && grep -Fq 'MMorph {' "$package_root/$file" \
    || fail "$file still changes shape on a plain curve"
done
! grep -qi 'ocean' "$package_root/apps/settings/qml/pages/SoundPage.qml" \
  || fail "Settings still offers the KDE sound theme"
grep -Fq 'onClosing: retire()' "$package_root/apps/welcome/qml/Main.qml" \
  && grep -Fq 'Config.write(entry, "Desktop Entry", "NoDisplay", true);' "$package_root/apps/welcome/qml/Main.qml" \
  || fail "welcome does not leave after its first showing"
grep -Fq 'readonly property string versionText: SystemInfo.osVersion' "$package_root/apps/settings/qml/pages/AboutPage.qml" \
  || fail "About still glues the codename onto the version"
grep -Fq 'indeterminate: Updates.progress <= 0 || Updates.progress >= 100' "$package_root/apps/settings/qml/pages/UpdatesPage.qml" \
  || fail "the update bar flashes full while packagekit reports 100%"

grep -Fq '{ id: "android", title: i18n("Android apps")' "$package_root/apps/settings/qml/components/Catalog.qml" \
  && grep -Fq 'readonly property string tool: "/usr/libexec/lumo-android"' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq 'page.request(page.choice === "gapps" ? "setup-gapps" : "setup-vanilla")' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  || fail "Settings cannot turn Android on"
grep -Fxq 'MimeType=application/vnd.android.package-archive;' "$package_root/apps/apkinstaller/org.lumo.apkinstaller.desktop" \
  && grep -Fq 'Android.inspect(url)' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -Fq 'Android.install(app.file, app.apk.package' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -q ' drivers apkinstaller appsplash androiddialog)' "$package_root/src/apps/CMakeLists.txt" \
  || fail "the APK installer is missing"
grep -Fq 'adaptive-icon' "$package_root/src/system/apk.cpp" \
  && grep -Fq 'QSvgRenderer renderer(vectorToSvg(elements));' "$package_root/src/system/apk.cpp" \
  && grep -Fq 'KF6::Archive' "$package_root/src/system/CMakeLists.txt" \
  || fail "the APK reader cannot draw app icons"
for dependency in libkf6archive-dev qt6-svg-dev qt6-image-formats-plugins; do
  grep -Eq "^ $dependency,?$" "$package_root/debian/control" || fail "the APK reader needs $dependency"
done
msgfmt --check -o /dev/null "$package_root/po/ru/lumo-apkinstaller.po" || fail "the APK installer translation is broken"
grep -Fq 'QGuiApplication::setDesktopFileName(QStringLiteral("waydroid.") + argument);' "$package_root/src/apps/appsplash.cpp" \
  && grep -Fq 'MLoadingIndicator {' "$package_root/apps/appsplash/qml/Main.qml" \
  && msgfmt --check -o /dev/null "$package_root/po/ru/lumo-appsplash.po" \
  || fail "Android apps open without their splash"
grep -Fq 'flags: Qt.Dialog | Qt.FramelessWindowHint' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -Fq 'app.startSystemMove();' "$package_root/apps/apkinstaller/qml/Main.qml" \
  || fail "the APK installer is not a Material dialog"
grep -Fq 'android: ["apk"]' "$package_root/apps/files/qml/kinds.js" \
  && grep -Fq 'Android.iconOf(fileUrl' "$package_root/apps/files/qml/FileItem.qml" \
  && grep -Fq 'void Android::iconOf(' "$package_root/src/system/android.cpp" \
  || fail "Files does not show the icons of APK files"
! grep -Fq 'Android.openSettings()' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq '"lumo-android.service"' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  || fail "Settings still opens Android's own settings or has no faster start"
grep -Fq 'msgid "Android apps"' "$package_root/po/ru/lumo-settings.po" \
  || fail "the Android page is not translated"
grep -Fq 'info.remaining' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fxq 'msgstr "Осталось меньше минуты"' "$package_root/po/ru/lumo-settings.po" \
  || fail "Settings does not show how long the Android apps download takes"
grep -Fq 'property string choice: "gapps"' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq 'recommended: true' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fxq 'msgstr "Google Play и APK-файлы"' "$package_root/po/ru/lumo-settings.po" \
  && ! grep -Fq 'MShape' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -Fq 'readonly property string step' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -Fq 'waitForPackage(package, callback, InstallChecks)' "$package_root/src/system/android.cpp" \
  && grep -Fxq 'msgstr "Установить приложение?"' "$package_root/po/ru/lumo-apkinstaller.po" \
  || fail "Google Play is not the recommended choice or the installer does not follow Android's"
! grep -Fq 'registerWithGoogle' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq 'Open Google Play and sign in with your Google account.' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq 'info.bytes_total' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fxq 'msgstr "Завершите настройку Google Play"' "$package_root/po/ru/lumo-settings.po" \
  || fail "Settings does not walk through Google Play or show the whole setup progress"
python3 -c 'import json, sys; e = json.load(open(sys.argv[1]))[0]; sys.exit(not (e["id"] == "2026-11-07" and e["items"][0]["icon"] == "lumo-android"))' "$package_root/data/whatsnew.json" \
  || fail "What's new does not lead with Android apps"
grep -Fq 'readonly property bool runs: apk.compatible || android.arm !== "unsupported"' "$package_root/apps/apkinstaller/qml/Main.qml" \
  && grep -Fq 'msgstr "Почти готово"' "$package_root/po/ru/lumo-apkinstaller.po" \
  || fail "The installer still refuses apps made for ARM processors"
grep -Fq 'Process.run("pkexec", [page.tool, "report"]' "$package_root/apps/settings/qml/pages/AndroidPage.qml" \
  && grep -Fq 'msgstr "Сообщить о проблеме"' "$package_root/po/ru/lumo-settings.po" \
  || fail "Settings cannot save a report about Android apps"

printf 'lumo-apps source test: OK\n'
