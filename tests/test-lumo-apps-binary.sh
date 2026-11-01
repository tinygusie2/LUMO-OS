#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-apps"
package_version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
deb="$project_root/_build/binary-packages/lumo-apps_${package_version}_amd64.deb"

fail() {
  printf 'lumo-apps binary test: %s\n' "$*" >&2
  exit 1
}

[[ -s "$deb" ]] || fail "binary package does not exist: $deb"
[[ "$(dpkg-deb --field "$deb" Architecture)" == "amd64" ]] || fail "wrong architecture"
[[ "$(dpkg-deb --field "$deb" Version)" == "$package_version" ]] || fail "wrong version"

temporary_root=$(mktemp -d /tmp/lumo-apps-test.XXXXXX)
trap 'find "$temporary_root" -depth -delete' EXIT
dpkg-deb --extract "$deb" "$temporary_root"

for dependency in flatpak appstream libflatpak0 libappstreamqt3; do
  dpkg-deb --field "$deb" Depends | grep -Eq "(^|, )$dependency( |,|$)" || fail "missing dependency: $dependency"
done
for path in usr/share/lumo/store/featured.json usr/share/flatpak/remotes.d/flathub.flatpakrepo etc/apt/apt.conf.d/60lumo-store usr/share/knotifications6/lumo-store.notifyrc usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/store/qmldir usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/store/liblumostore.so; do
  [[ -s "$temporary_root/$path" ]] || fail "missing Store file: $path"
done
qml=usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/system
for path in "$qml/qmldir" "$qml/liblumosystem.so" usr/share/knotifications6/lumo-screenshot.notifyrc \
  usr/share/knotifications6/lumo-updates.notifyrc \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/shell/qmldir \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/shell/liblumoshell.so; do
  [[ -s "$temporary_root/$path" ]] || fail "missing $path"
done
for app in settings files welcome editor photos player calculator screenshot store share taskmanager; do
  [[ -x "$temporary_root/usr/bin/lumo-$app" ]] || fail "missing lumo-$app"
  [[ -s "$temporary_root/usr/share/lumo/$app/Main.qml" ]] || fail "missing the $app interface"
  cmp -s "$package_root/apps/$app/qml/Main.qml" "$temporary_root/usr/share/lumo/$app/Main.qml" || fail "$app interface differs from the source"
  [[ -s "$temporary_root/usr/share/applications/org.lumo.$app.desktop" ]] || fail "missing the $app desktop entry"
done
[[ -x "$temporary_root/usr/bin/lumo-terminal" ]] || fail "missing lumo-terminal"
cmp -s "$package_root/apps/terminal/qml/Main.qml" "$temporary_root/usr/share/lumo/terminal/Main.qml" || fail "the terminal interface differs from the source"
cmp -s "$package_root/data/terminal/lumo.bashrc" "$temporary_root/usr/share/lumo/terminal/lumo.bashrc" || fail "missing the terminal start-up file"
[[ -s "$temporary_root/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/terminal/qmldir" ]] || fail "missing the org.lumo.terminal module"
grep -q 'X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2' \
  "$temporary_root/usr/share/applications/org.lumo.screenshot.desktop" \
  || fail "Screenshot cannot ask KWin for screenshots"
cmp -s "$temporary_root/usr/share/applications/org.lumo.taskmanager.desktop" "$temporary_root/usr/share/kglobalaccel/org.lumo.taskmanager.desktop" \
  && grep -qx 'X-KDE-Shortcuts=Ctrl+Shift+Esc,Ctrl+Esc' "$temporary_root/usr/share/kglobalaccel/org.lumo.taskmanager.desktop" \
  || fail "Ctrl+Shift+Esc does not open the Task Manager"
grep -qx 'Exec=/usr/bin/lumo-screenshot' \
  "$temporary_root/usr/share/applications/org.lumo.screenshot.desktop" \
  || fail "Screenshot's Exec is not an absolute path; KWin would refuse it"

for domain in settings files editor photos player calculator screenshot welcome system update-notifier store share taskmanager terminal; do
  [[ -s "$temporary_root/usr/share/locale/ru/LC_MESSAGES/lumo-$domain.mo" ]] \
    || fail "Russian translation is missing: lumo-$domain"
done
grep -qx 'Exec=lumo-welcome --first-run' \
  "$temporary_root/etc/xdg/autostart/org.lumo.welcome.desktop" \
  || fail "Welcome is not started at login"
[[ -x "$temporary_root/usr/bin/lumo-update-notifier" ]] || fail "missing lumo-update-notifier"
grep -qx 'Exec=lumo-update-notifier' \
  "$temporary_root/etc/xdg/autostart/org.lumo.update-notifier.desktop" \
  || fail "the update notifier is not started at login"
grep -qx 'DesktopEntry=org.lumo.settings' "$temporary_root/usr/share/knotifications6/lumo-updates.notifyrc" \
  || fail "update notifications would not come from Settings"
python3 - "$temporary_root/usr/share/lumo/whatsnew.json" <<'PYTHON_TEST' || fail "the release notes for What's new are missing or broken"
import json, sys
releases = json.load(open(sys.argv[1], encoding="utf-8"))
assert releases and all(r["id"] and r["items"] for r in releases)
ids = [r["id"] for r in releases]
assert ids == sorted(ids, reverse=True), "newest release first"
for item in (i for r in releases for i in r["items"]):
    assert item["icon"] and item["title"]["en"] and item["title"]["ru"] and item["text"]["en"] and item["text"]["ru"]
PYTHON_TEST
grep -q 'lumo-settings' "$temporary_root/usr/bin/systemsettings" \
  || fail "the systemsettings wrapper is missing"
grep -Fxq 'License: MPL-2.0' "$temporary_root/usr/share/lumo/copyright/librewolf" \
  || fail "the LibreWolf copyright summary is missing"
[[ -x "$temporary_root/usr/lib/x86_64-linux-gnu/libexec/lumo-filechooser" ]] \
  || fail "the file chooser backend is missing"
[[ -s "$temporary_root/usr/share/lumo/filechooser/Chooser.qml" ]] || fail "the file chooser window is missing"
grep -qx 'Exec=/usr/lib/x86_64-linux-gnu/libexec/lumo-filechooser' \
  "$temporary_root/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.lumo.service" \
  || fail "D-Bus cannot start the file chooser"
grep -q 'org.freedesktop.impl.portal.FileChooser' "$temporary_root/usr/share/xdg-desktop-portal/portals/lumo.portal" \
  || fail "the file chooser portal is not declared"
grep -qx 'org.freedesktop.impl.portal.FileChooser=lumo;kde;' "$temporary_root/etc/xdg-desktop-portal/kde-portals.conf" \
  || fail "the portal does not use the Lumo file chooser under Plasma"
grep -qx 'default=kde' "$temporary_root/etc/xdg-desktop-portal/kde-portals.conf" \
  || fail "the other portals no longer come from KDE"
grep -qx 'export PLASMA_INTEGRATION_USE_PORTAL=1' "$temporary_root/etc/xdg/plasma-workspace/env/lumo-file-dialogs.sh" \
  || fail "Qt programs do not use the portal for their file dialogs"
grep -qx 'wmclass=org.lumo.filechooser' "$temporary_root/etc/xdg/kwinrulesrc" \
  || fail "the file chooser has no window rule"
control=$(mktemp -d /tmp/lumo-apps-control.XXXXXX)
dpkg-deb --control "$deb" "$control"
grep -q 'dpkg-divert --package lumo-apps --add --rename' "$control/preinst" \
  || fail "systemsettings is not diverted before the wrapper is unpacked"
grep -q 'dpkg-divert --package lumo-apps --remove --rename' "$control/postrm" \
  || fail "the systemsettings diversion is not removed with the package"
find "$control" -depth -delete

printf 'lumo-apps binary test: OK\n'
