#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-desktop"
package_version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
binary_dir="$project_root/_build/binary-packages"
desktop_deb="$binary_dir/lumo-desktop_${package_version}_all.deb"
installer_deb="$binary_dir/lumo-calamares_${package_version}_all.deb"

fail() {
  printf 'lumo-desktop binary test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-deb find grep mktemp; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done

for deb in "$desktop_deb" "$installer_deb"; do
  [[ -s "$deb" ]] || fail "binary package does not exist: $deb"
  [[ "$(dpkg-deb --field "$deb" Version)" == "$package_version" ]] \
    || fail "wrong package version in $deb"
  [[ "$(dpkg-deb --field "$deb" Architecture)" == "all" ]] \
    || fail "wrong package architecture in $deb"
done
[[ "$(dpkg-deb --field "$desktop_deb" Package)" == "lumo-desktop" ]] \
  || fail "wrong desktop package name"
[[ "$(dpkg-deb --field "$installer_deb" Package)" == "lumo-calamares" ]] \
  || fail "wrong installer package name"
dpkg-deb --field "$installer_deb" Depends | grep -Fq calamares \
  || fail "installer configuration does not depend on calamares"

temporary_root=$(mktemp -d /tmp/lumo-desktop-test.XXXXXX)
trap 'find "$temporary_root" -depth -delete' EXIT
dpkg-deb --extract "$desktop_deb" "$temporary_root/desktop"
dpkg-deb --extract "$installer_deb" "$temporary_root/installer"

for path in \
  etc/dpkg/dpkg.cfg.d/lumo-wallpapers \
  usr/share/icons/lumo_cursors/index.theme \
  usr/share/icons/lumo_cursors/cursor.theme \
  usr/share/icons/lumo_cursors/cursors/default \
  usr/share/icons/lumo_cursors/cursors/wait \
  usr/share/icons/lumo_cursors/cursors/progress \
  usr/share/icons/lumo_cursors/cursors_scalable/wait/metadata.json \
  etc/xdg/kcminputrc \
  etc/xdg/klaunchrc \
  usr/share/plasma/look-and-feel/org.lumo.desktop/metadata.json \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/defaults \
  etc/xdg/kdeglobals \
  usr/share/icons/hicolor/scalable/apps/lumo-logo.svg \
  usr/share/icons/hicolor/48x48/apps/lumo-logo.png \
  usr/share/icons/hicolor/256x256/apps/lumo-logo.png \
  etc/skel/.face \
  etc/skel/.local/share/applications/org.kde.plasma.emojier.desktop \
  etc/skel/.local/share/applications/org.kde.drkonqi.coredump.gui.desktop \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/plasmoidsetupscripts/org.kde.plasma.kickoff.js \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/plasmoidsetupscripts/org.kde.plasma.icontasks.js \
  usr/share/icons/Lumo/index.theme \
  usr/share/icons/Lumo/scalable/apps/start-here-kde-symbolic.svg \
  usr/share/icons/Lumo/scalable/apps/start-here-kde.svg \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/splash/Splash.qml \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
  etc/xdg/plasmarc \
  usr/share/color-schemes/LumoDark.colors \
  usr/share/color-schemes/LumoLight.colors \
  usr/share/plasma/desktoptheme/lumo/metadata.json \
  usr/share/plasma/desktoptheme/lumo/colors \
  usr/share/plasma/desktoptheme/lumo/widgets/panel-background.svg \
  usr/share/plasma/desktoptheme/lumo/dialogs/background.svg \
  usr/share/plasma/desktoptheme/lumo/widgets/tasks.svg \
  usr/share/plasma/desktoptheme/lumo/widgets/slider.svg \
  usr/share/plasma/desktoptheme/lumo/icons/audio.svg \
  usr/share/icons/Lumo/scalable/status/audio-volume-high.svg \
  usr/share/icons/Lumo/scalable/status/audio-volume-high-symbolic.svg \
  usr/share/icons/Lumo/scalable/actions/system-shutdown.svg \
  usr/share/icons/Lumo/scalable/categories/ksysguardd.svg \
  usr/share/icons/Lumo/scalable/categories/lumo-analog-clock.svg \
  usr/share/icons/Lumo/scalable/devices/device-notifier.svg \
  usr/share/locale/ru/LC_MESSAGES/plasma_applet_org.lumo.launcher.mo \
  usr/share/locale/ru/LC_MESSAGES/plasma_applet_org.lumo.quicksettings.mo \
  usr/share/locale/ru/LC_MESSAGES/plasma_applet_org.lumo.clipboard.mo \
  etc/xdg/klipperrc \
  etc/skel/.config/kglobalshortcutsrc \
  usr/share/knotifications6/lumo-devices.notifyrc \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/sources/DeviceSource.qml \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/sources/ThemeSource.qml \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/TileGrid.qml \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/InternetPanel.qml \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/BluetoothPanel.qml \
  usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/PanelRow.qml \
  usr/share/plasma/plasmoids/org.lumo.launcher/contents/ui/SessionGroup.qml \
  usr/share/plasma/desktoptheme/lumo-md1/metadata.json \
  usr/share/plasma/desktoptheme/lumo-md1-light/colors \
  usr/share/plasma/desktoptheme/lumo-md2/dialogs/background.svg \
  usr/share/plasma/desktoptheme/lumo-md2-light/metadata.json \
  usr/share/color-schemes/LumoMD1Dark.colors \
  usr/share/color-schemes/LumoMD1Light.colors \
  usr/share/color-schemes/LumoMD2Dark.colors \
  usr/share/color-schemes/LumoMD2Light.colors \
  usr/share/Kvantum/LumoMD1/LumoMD1Dark.kvconfig \
  usr/share/Kvantum/LumoMD2/LumoMD2.svg \
  usr/share/aurorae/themes/lumo-md1/decoration.svg \
  usr/share/aurorae/themes/lumo-md2-light/lumo-md2-lightrc \
  usr/share/plasma/wallpapers/org.lumo.shapes/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.shapes/contents/ui/main.qml \
  usr/share/plasma/wallpapers/org.lumo.shapes/contents/ui/materialshapes.js \
  usr/share/plasma/wallpapers/org.lumo.shapes/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.shapes/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.rhythm/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.rhythm/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.rhythm/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.rhythm/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.pastel/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.starfall/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.starfall/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.starfall/contents/ui/materialshapes.js \
  usr/share/plasma/wallpapers/org.lumo.starfall/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.starfall/contents/ui/palettes/blue-grey.qml \
  usr/share/locale/ru/LC_MESSAGES/plasma_wallpaper_org.lumo.starfall.mo \
  usr/share/plasma/wallpapers/org.lumo.pastel/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.pastel/contents/ui/materialshapes.js \
  usr/share/plasma/wallpapers/org.lumo.waves/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.waves/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.waves/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.waves/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.aurora/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.aurora/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.aurora/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.aurora/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.dunes/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.dunes/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.dunes/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.dunes/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.bloom/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.bloom/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.bloom/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.bloom/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.contour/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.contour/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.contour/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.contour/contents/ui/palettes/blue-grey.qml \
  usr/share/plasma/wallpapers/org.lumo.waves/contents/ui/Power.qml \
  usr/share/plasma/wallpapers/org.lumo.shapes/contents/ui/PowerBattery.qml \
  usr/share/plasma/wallpapers/org.lumo.starfall/contents/ui/PowerProfile.qml \
  usr/share/plasma/wallpapers/org.lumo.bloom/contents/ui/materialshapes.js \
  usr/share/locale/nl/LC_MESSAGES/plasma_wallpaper_org.lumo.aurora.mo \
  usr/share/kconf_update/lumo-marbles-to-pastel.upd \
  usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/lumo_marbles_to_pastel.js \
  usr/share/kconf_update/lumo-tower-to-shapes.upd \
  etc/xdg/plasma-workspace/env/lumo-video-decoding.sh \
  usr/share/kconf_update/lumo-tower-to-shapes.sh \
  usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/lumo_tower_to_shapes.js \
  usr/share/plasma/wallpapers/org.lumo.pastel/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.pastel/contents/ui/palettes/blue-grey.qml \
  usr/share/locale/ru/LC_MESSAGES/plasma_wallpaper_org.lumo.pastel.mo \
  usr/share/plasma/wallpapers/org.lumo.ribbon/metadata.json \
  usr/share/plasma/wallpapers/org.lumo.ribbon/contents/ui/Scene.qml \
  usr/share/plasma/wallpapers/org.lumo.ribbon/contents/ui/morphs.js \
  usr/share/plasma/wallpapers/org.lumo.ribbon/contents/ui/palettes/lumo.qml \
  usr/share/plasma/wallpapers/org.lumo.ribbon/contents/ui/palettes/blue-grey.qml \
  usr/share/locale/ru/LC_MESSAGES/plasma_wallpaper_org.lumo.ribbon.mo \
  usr/share/Kvantum/Lumo/Lumo.kvconfig \
  usr/share/Kvantum/Lumo/Lumo.svg \
  usr/share/Kvantum/Lumo/LumoDark.kvconfig \
  usr/share/Kvantum/Lumo/LumoDark.svg \
  etc/xdg/Kvantum/kvantum.kvconfig \
  usr/share/aurorae/themes/lumo/metadata.desktop \
  usr/share/aurorae/themes/lumo/lumorc \
  usr/share/aurorae/themes/lumo/decoration.svg \
  usr/share/aurorae/themes/lumo/close.svg \
  usr/share/aurorae/themes/lumo/maximize.svg \
  usr/share/aurorae/themes/lumo/minimize.svg \
  usr/share/aurorae/themes/lumo/restore.svg \
  usr/share/aurorae/themes/lumo-light/lumo-lightrc \
  usr/share/aurorae/themes/lumo-light/decoration.svg \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/qmldir \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/Button.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/Menu.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/private/SwitchIndicator.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/qmldir \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/qmldir \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/M3.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/ui/qmldir \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/ui/ListItem.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/ui/FloatingToolbar.qml \
  usr/libexec/lumo-splash-wallpaper \
  usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/ContextMenu.qml \
  usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/Task.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/ui/Page.qml \
  usr/share/locale/ru/LC_MESSAGES/lumo-ui.mo \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/M3.qml \
  etc/xdg/plasma-workspace/env/lumo-qtquick-style.sh \
  etc/xdg/kwinrc \
  etc/skel/.local/share/applications/kvantummanager.desktop \
  usr/share/icons/Lumo/scalable/apps/preferences-system.svg \
  usr/share/icons/Lumo/scalable/categories/preferences-desktop-effects.svg; do
  [[ -s "$temporary_root/desktop/$path" ]] \
    || fail "desktop package is missing $path"
done

for id in org.lumo.launcher org.lumo.quicksettings org.lumo.clipboard; do
  applet="$temporary_root/desktop/usr/share/plasma/plasmoids/$id"
  for path in metadata.json contents/ui/main.qml contents/ui/m3/qmldir \
    contents/ui/m3/M3.qml contents/ui/m3/MSlider.qml contents/ui/m3/MTile.qml; do
    [[ -s "$applet/$path" ]] || fail "applet $id is missing $path"
  done
  grep -Fq 'pragma Singleton' "$applet/contents/ui/m3/M3.qml" \
    || fail "applet $id carries no design-token singleton"
  if grep -Eq 'property color on[A-Z]' "$applet/contents/ui/m3/M3.qml"; then
    fail "applet $id tokens declare an on* colour property"
  fi
done
[[ -s "$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.launcher/contents/config/main.xml" ]] \
  || fail "launcher has no configuration schema"

kdeglobals="$temporary_root/desktop/etc/xdg/kdeglobals"
grep -Fxq 'LookAndFeelPackage=org.lumo.desktop' "$kdeglobals" \
  || fail "Lumo look-and-feel is not the system default"
grep -Fxq 'ColorScheme=LumoDark' "$kdeglobals" \
  || fail "system defaults do not carry the Lumo colour scheme"
grep -Fxq '[Colors:Window]' "$kdeglobals" \
  || fail "system defaults do not carry the colour scheme's colours"
grep -Fxq 'Theme=Lumo' "$kdeglobals" \
  || fail "system defaults do not select the Lumo icon theme"
grep -Fxq 'name=lumo' "$temporary_root/desktop/etc/xdg/plasmarc" \
  || fail "system defaults do not select the Lumo Plasma theme"
grep -Fq 'Inherits=breeze-dark' "$temporary_root/desktop/usr/share/icons/Lumo/index.theme" \
  || fail "icon theme does not inherit Breeze"
[[ -L "$temporary_root/desktop/usr/share/icons/Lumo/scalable/status/audio-volume-high-symbolic.svg" ]] \
  || fail "icon aliases are not symlinks"
platform="$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/plugins/kf6/kirigami/platform"
[[ "$(readlink "$platform/org.lumo.desktop.so")" == "org.kde.desktop.so" ]] \
  || fail "Kirigami platform plugin link does not lead to the desktop plugin"
[[ "$(readlink "$temporary_root/desktop/etc/skel/.face.icon")" == ".face" ]] \
  || fail "the shell does not see the default profile picture"
grep -Fxq 'widgetStyle=kvantum-dark' "$kdeglobals" \
  || fail "system defaults do not select the Kvantum widget style"
if grep -q '^AccentColor=' "$temporary_root/desktop/usr/share/color-schemes/LumoDark.colors"; then
  fail "colour scheme carries an accent colour KDE would blend into selections"
fi
grep -Fq 'pragma Singleton' \
  "$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/M3.qml" \
  || fail "Qt Quick style carries no design-token singleton"
for field in fonts-roboto-unhinted plasma-workspace qt-style-kvantum kwin-common \
  qml6-module-org-kde-desktop qml6-module-qtquick-shapes; do
  dpkg-deb --field "$desktop_deb" Depends | grep -Fq "$field" \
    || fail "desktop package does not depend on $field"
done

for path in \
  etc/calamares/settings.conf \
  etc/calamares/modules/unpackfs.conf \
  etc/calamares/modules/removeuser.conf \
  etc/calamares/modules/shellprocess-drivers.conf \
  etc/calamares/branding/lumo/branding.desc \
  etc/calamares/branding/lumo/show.qml \
  etc/calamares/branding/lumo/lumo-logo.png \
  etc/calamares/branding/lumo/lumo-welcome.png \
  etc/calamares/branding/lumo/calamares-sidebar.qml \
  etc/calamares/branding/lumo/calamares-navigation.qml \
  etc/calamares/branding/lumo/welcomeq.qml \
  etc/calamares/branding/lumo/localeq.qml \
  etc/calamares/branding/lumo/keyboardq.qml \
  etc/calamares/branding/lumo/keymaps.js \
  etc/calamares/branding/lumo/lang/calamares-lumo_ru.qm \
  etc/calamares/branding/lumo/stylesheet.qss \
  etc/calamares/branding/lumo/images/partition-erase-auto.svg \
  etc/calamares/branding/lumo/usersq.qml \
  etc/calamares/branding/lumo/summaryq.qml \
  etc/calamares/branding/lumo/finishedq.qml \
  etc/calamares/modules/usersq.conf \
  etc/calamares/modules/finishedq.conf \
  usr/bin/lumo-installer \
  usr/share/polkit-1/actions/org.lumo.installer.policy \
  usr/share/polkit-1/rules.d/49-lumo-installer.rules \
  usr/share/applications/org.lumo.installer.desktop; do
  [[ -s "$temporary_root/installer/$path" ]] \
    || fail "installer package is missing $path"
done
dpkg-deb --field "$installer_deb" Depends | grep -Fq pkexec \
  || fail "installer package does not depend on pkexec, which starts Calamares"

for path in \
  etc/alacritty/alacritty.toml \
  usr/share/lumo/terminal/dark.toml \
  usr/share/lumo/terminal/light.toml \
  usr/share/applications/org.lumo.terminal.desktop \
  usr/share/plasma/desktoptheme/lumo-light/metadata.json \
  usr/share/plasma/desktoptheme/lumo-light/colors \
  usr/share/icons/Lumo/scalable/apps/org.lumo.settings.svg \
  usr/share/icons/Lumo/scalable/apps/org.lumo.files.svg \
  usr/share/icons/Lumo/scalable/apps/org.lumo.taskmanager.svg \
  usr/share/sddm/themes/lumo/Main.qml \
  usr/share/sddm/themes/lumo/metadata.desktop \
  usr/share/sddm/themes/lumo/icons/login.svg \
  usr/share/lumo/faces/lumo.png \
  usr/share/lumo/faces/light-blue.png \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/MShapeEcho.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/materialshapes.js \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/MLinearProgress.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/MCircularProgress.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/MLinearProgress.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/MCircularProgress.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/ProgressBar.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/MLoadingIndicator.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/MMorph.qml \
  usr/libexec/lumo-grub-theme \
  usr/libexec/lumo-boot-theme \
  usr/share/lumo/boot/plymouth.pack \
  usr/share/lumo/grub/lumo-dark/theme.txt \
  usr/share/lumo/grub/lumo-dark/select_c.png \
  usr/share/lumo/grub/light-blue-light/theme.txt \
  usr/share/lumo/grub/green-dark/logo.png \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/MMorph.qml \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/loadingshapes.js \
  usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/loadingshapes.js \
  usr/share/plymouth/themes/lumo/wave-0.png \
  usr/share/plymouth/themes/lumo/wave-89.png; do
  [[ -e "$temporary_root/desktop/$path" ]] \
    || fail "desktop package is missing $path"
done
[[ ! -e "$temporary_root/desktop/usr/share/sddm/themes/lumo/palette.js" ]] || fail "the login screen still ships a fixed palette"
grep -Fxq 'MShapeEcho MShapeEcho.qml' "$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/qmldir" \
  || fail "the shape echo is not part of org.lumo.m3"
grep -Fxq 'MLinearProgress MLinearProgress.qml' "$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/qmldir" \
  && grep -Fxq 'MCircularProgress MCircularProgress.qml' "$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/impl/qmldir" \
  && grep -Fxq 'ProgressBar 1.0 ProgressBar.qml' "$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/desktop/qmldir" \
  || fail "the wavy progress indicators are not registered"
cmp -s "$temporary_root/desktop/usr/share/lumo/grub/lumo-dark/theme.txt" "$temporary_root/desktop/usr/share/grub/themes/lumo/theme.txt" \
  || fail "the default boot menu and the lumo dark variant differ"
grep -Fq 'desktop-color: "#f' "$temporary_root/desktop/usr/share/lumo/grub/light-blue-light/theme.txt" \
  || fail "the light boot menu is not light"
boot_work=$(mktemp -d)
python3 -I - "$temporary_root/desktop" "$boot_work" <<'PY' || fail "the boot theme tool does not build a working Plymouth theme"
import importlib.machinery, importlib.util, pathlib, sys
root, work = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("boot", str(root / "usr/libexec/lumo-boot-theme"))
spec = importlib.util.spec_from_loader("boot", loader)
boot = importlib.util.module_from_spec(spec)
loader.exec_module(boot)
boot.PACK = root / "usr/share/lumo/boot/plymouth.pack"
boot.PALETTES = root / "usr/share/lumo/palettes"
boot.THEMES = work
stock = root / "usr/share/plymouth/themes/lumo"
boot.build("lumo", "dark")
theme = work / boot.NAME
assert (theme / f"{boot.NAME}.script").read_text() == (stock / "lumo.script").read_text()
assert sorted(p.name for p in stock.glob("*.png")) == sorted(p.name for p in theme.glob("*.png"))
boot.build("light-blue", "light")
theme = work / boot.NAME
assert (theme / "variant").read_text().strip() == "light-blue-light"
for png in theme.glob("*.png"):
    assert png.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", png
script = (theme / f"{boot.NAME}.script").read_text()
assert "@BG@" not in script and "Window.SetBackgroundTopColor(0.976, 0.976, 0.988)" in script, script[:400]
assert f"ImageDir={work / boot.NAME}" in (theme / f"{boot.NAME}.plymouth").read_text()
PY
rm -rf "$boot_work"
cmp -s "$temporary_root/desktop/usr/share/lumo/faces/lumo.png" "$temporary_root/desktop/usr/share/lumo/avatars/00-lumo.png" \
  || fail "the Lumo face and the stock Lumo avatar differ"
cmp -s "$temporary_root/desktop/usr/share/lumo/faces/lumo.png" "$temporary_root/desktop/usr/share/lumo/faces/light-blue.png" \
  && fail "the Lumo face does not change with the colour"

shell=usr/share/plasma/shells/org.kde.plasma.desktop/contents
notifications=usr/share/plasma/plasmoids/org.kde.plasma.notifications/contents/ui
for path in \
  "$shell/lockscreen/LockScreen.qml" \
  "$shell/lockscreen/LumoMediaControls.qml" \
  "$shell/osd/Osd.qml" \
  "$shell/osd/LumoOsdItem.qml" \
  "$shell/configuration/AppletConfiguration.qml" \
  "$shell/configuration/ConfigurationContainmentAppearance.qml" \
  "$shell/configuration/ConfigurationContainmentActions.qml" \
  "$shell/configuration/AboutPlugin.qml" \
  "$shell/configuration/ConfigurationShortcuts.qml" \
  usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/ConfigLocation.qml \
  usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/ConfigIcons.qml \
  usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/ConfigFilter.qml \
  usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/ConfigOverlay.qml \
  usr/share/plasma/plasmoids/org.kde.plasma.panelspacer/contents/ui/main.qml \
  "$shell/explorer/WidgetExplorer.qml" \
  "$shell/explorer/WidgetPreview.qml" \
  "$shell/explorer/WidgetDrag.qml" \
  "$shell/explorer/WidgetCard.qml" \
  "$shell/explorer/OtherPreview.qml" \
  "$shell/explorer/widgets.js" \
  "$shell/explorer/MaterialShape.qml" \
  "$shell/explorer/materialshapes.js" \
  "$shell/views/DesktopEditMode.qml" \
  "$shell/configuration/panelconfiguration/PanelRepresentation.qml" \
  "$notifications/main.qml" \
  "$notifications/lumo/global/Globals.qml" \
  "$notifications/lumo/global/qmldir" \
  "$notifications/lumo/NotificationPopup.qml" \
  "$notifications/lumo/FullRepresentation.qml" \
  "$notifications/lumo/CompactRepresentation.qml" \
  "$notifications/lumo/delegates/DelegatePopup.qml" \
  "$notifications/lumo/components/AppBadge.qml" \
  usr/share/locale/ru/LC_MESSAGES/lumo-notifications.mo \
  usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/Badge.qml \
  usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/ToolTipInstance.qml \
  usr/share/plymouth/themes/lumo/lumo.plymouth \
  usr/share/plymouth/themes/lumo/lumo.script \
  usr/share/plymouth/themes/lumo/logo.png \
  usr/share/plymouth/themes/lumo/shape-6.png \
  usr/share/plymouth/themes/lumo/entry.png \
  usr/share/plymouth/plymouthd.defaults \
  etc/default/grub.d/lumo.cfg \
  usr/lib/systemd/system/plymouth-quit.service.d/plymouth-quit-lumo.conf \
  usr/lib/systemd/system/sddm.service.d/sddm-plymouth.conf \
  usr/share/grub/themes/lumo/theme.txt \
  usr/share/grub/themes/lumo/logo.png \
  usr/share/grub/themes/lumo/select_nw.png \
  usr/share/grub/themes/lumo/roboto-regular-16.pf2 \
  usr/share/grub/themes/lumo/roboto-medium-16.pf2 \
  usr/share/grub/themes/lumo/roboto-regular-24.pf2 \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/logout/Logout.qml \
  usr/share/plasma/look-and-feel/org.lumo.desktop/contents/logout/timer.js \
  usr/share/kwin/tabbox/org.lumo.switcher/metadata.json \
  usr/share/kwin/tabbox/org.lumo.switcher/contents/ui/main.qml \
  usr/share/themes/Lumo/gtk-3.0/gtk.css \
  usr/share/themes/Lumo/gtk-3.0/gtk-dark.css \
  usr/share/themes/Lumo/gtk-4.0/gtk.css \
  usr/share/themes/LumoMD1/gtk-3.0/gtk.css \
  usr/share/themes/LumoMD2/gtk-3.0/gtk.css \
  usr/share/glib-2.0/schemas/90_lumo.gschema.override \
  usr/share/kconf_update/lumo-gtk-theme.upd \
  usr/share/kconf_update/lumo-gtk-theme.sh \
  etc/skel/.config/gtk-3.0/settings.ini \
  usr/share/librewolf/distribution/extensions/theme@lumo.os.xpi \
  usr/share/librewolf/browser/defaults/preferences/lumo.js \
  usr/share/lumo/librewolf/userChrome.css \
  usr/share/kconf_update/lumo-librewolf-chrome.upd \
  usr/share/kconf_update/lumo-librewolf-chrome.sh \
  usr/share/sounds/lumo/index.theme \
  usr/share/lumo/avatars/00-lumo.png \
  usr/share/lumo/avatars/01-ember-layers.png \
  usr/share/sounds/lumo/stereo/desktop-login.wav \
  usr/share/sounds/lumo/stereo/dialog-information.wav \
  usr/share/sounds/lumo/stereo/bell-window-system.wav \
  usr/share/kconf_update/lumo-sound-theme.upd \
  usr/share/kconf_update/lumo-sound-theme.sh \
  usr/share/kconf_update/lumo-terminal-entry.upd \
  usr/share/kconf_update/lumo-terminal-entry.sh \
  etc/xdg/plasma_workspace.notifyrc \
  usr/libexec/lumo-crash-notifier \
  usr/lib/systemd/user/drkonqi-coredump-launcher@.service.d/drkonqi-coredump-launcher-lumo.conf \
  etc/xdg/mimeapps.list; do
  [[ -e "$temporary_root/desktop/$path" ]] \
    || fail "desktop package is missing $path"
done
grep -Fxq 'LayoutName=org.lumo.switcher' "$temporary_root/desktop/etc/xdg/kwinrc" \
  || fail "Alt+Tab does not use the Lumo window switcher"
grep -Fxq 'Theme=lumo' "$temporary_root/desktop/usr/share/plymouth/plymouthd.defaults" \
  || fail "Plymouth does not default to the Lumo boot splash"
find "$temporary_root/desktop/usr/share/plymouth/themes/lumo" -name '*.svg' | grep -q . \
  && fail "the boot splash still carries SVGs Plymouth cannot read"
grep -Fxq 'X-KDE-Shortcuts=Alt+F2,Search,Meta+R' "$temporary_root/desktop/usr/share/kglobalaccel/org.kde.krunner.desktop" \
  || fail "KRunner still takes Alt+Space from the Lumo launcher"
grep -Fq 'launcher.globalShortcut = "Alt+Space"' \
  "$temporary_root/desktop/usr/share/plasma/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
  || fail "the Lumo launcher does not open with Alt+Space"
grep -Fxq 'X-KDE-Shortcuts=Ctrl+Alt+T' "$temporary_root/desktop/usr/share/applications/org.lumo.terminal.desktop" \
  && grep -Fxq 'Exec=lumo-terminal' "$temporary_root/desktop/usr/share/applications/org.lumo.terminal.desktop" \
  || fail "Ctrl+Alt+T does not open the Lumo Terminal"
[[ "$(find "$temporary_root/desktop/usr/share/lumo/avatars" -name '*.png' | wc -l)" -eq 15 ]] \
  || fail "the Lumo profile pictures are missing"
[[ "$(find "$temporary_root/desktop/usr/share/lumo/palettes" -name '*.conf' | wc -l)" -eq 20 ]] \
  || fail "the colour palettes are not twenty"
for path in \
  usr/share/color-schemes/LumoDeepPurpleMD1Light.colors \
  usr/share/color-schemes/LumoBlueDark.colors \
  usr/share/Kvantum/LumoBlue/LumoBlue.kvconfig \
  usr/share/Kvantum/LumoBlueGreyMD2/LumoBlueGreyMD2Dark.svg \
  usr/share/aurorae/themes/lumo-blue-md1-light/decoration.svg \
  usr/share/themes/LumoTeal/gtk-3.0/gtk.css \
  usr/share/lumo/terminal/blue/dark.toml \
  usr/share/icons/Lumo-blue/index.theme \
  usr/share/icons/Lumo-blue/scalable/apps/org.lumo.files.svg \
  usr/share/plasma/desktoptheme/lumo-blue/colors \
  usr/share/plasma/desktoptheme/lumo-blue-md1-light/widgets/panel-background.svg; do
  [[ -e "$temporary_root/desktop/$path" ]] || fail "a colour theme is incomplete: $path"
done
[[ -L "$temporary_root/desktop/usr/share/plasma/desktoptheme/lumo-red/widgets" ]] \
  || fail "the red Plasma theme copies its pictures instead of linking them"
[[ -s "$temporary_root/desktop/usr/lib/sysctl.d/90-lumo-panic.conf" ]] || fail "the panic timeout is missing"
[[ -x "$temporary_root/desktop/usr/libexec/lumo-panic-report" ]] || fail "the panic report is missing"
grep -Fxq 'After=systemd-pstore.service' "$temporary_root/desktop/usr/lib/systemd/system/lumo-panic-report.service" \
  || fail "the panic report does not wait for systemd-pstore"
dpkg-deb --ctrl-tarfile "$desktop_deb" | tar -xO ./postinst 2>/dev/null | grep -q 'lumo-panic-report.service' \
  || fail "the panic report service is not enabled on installation"
[[ -x "$temporary_root/desktop/usr/libexec/lumo-drivers" ]] \
  && [[ -s "$temporary_root/desktop/usr/share/lumo/nvidia-archive-keyring.gpg" ]] \
  && [[ -s "$temporary_root/desktop/usr/lib/systemd/system/lumo-drivers@.service" ]] \
  && [[ -s "$temporary_root/desktop/usr/share/polkit-1/actions/org.lumo.drivers.policy" ]] \
  || fail "the graphics driver tool is incomplete"
dpkg-deb --ctrl-tarfile "$desktop_deb" | tar -xO ./postinst 2>/dev/null | grep -q 'lumo-drivers.timer' \
  || fail "the graphics driver check is not enabled on installation"
dpkg-deb --ctrl-tarfile "$desktop_deb" | tar -xO ./postinst 2>/dev/null | grep -q "'lumo-drivers.service'" \
  && fail "installing the package would run the driver install inside the dpkg transaction"
triggers=$(dpkg-deb --ctrl-tarfile "$desktop_deb" | tar -xO ./triggers 2>/dev/null || true)
grep -Fxq 'activate-noawait update-initramfs' <<<"$triggers" \
  || fail "lumo-desktop does not rebuild the initramfs for its hook"
if grep -Ev '^(#.*|activate(-await|-noawait)? .+|interest(-await|-noawait)? .+|)$' <<<"$triggers" | grep -q .; then
  fail "lumo-desktop's triggers file has lines dpkg rejects"
fi
dpkg-deb -c "$desktop_deb" | grep -E '^-rwxr-xr-x .* \./usr/share/initramfs-tools/hooks/zz-lumo-firmware$' >/dev/null \
  || fail "the initramfs firmware hook is not installed executable"
[[ "$(readlink "$temporary_root/desktop/usr/share/kglobalaccel/org.lumo.terminal.desktop")" == */applications/org.lumo.terminal.desktop ]] \
  || fail "kglobalaccel does not see the terminal's launch shortcut"
grep -Fxq 'Icon=org.lumo.terminal' "$temporary_root/desktop/etc/skel/.local/share/applications/Alacritty.desktop" \
  || fail "a terminal started without its class shows the Wayland icon"
grep -Fq 'clipboard.globalShortcut = "Meta+V"' \
  "$temporary_root/desktop/usr/share/plasma/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
  || fail "the Lumo clipboard does not open with Meta+V"
grep -Fxq 'show-on-mouse-pos=none,Meta+V,Show Clipboard Items at Mouse Position' \
  "$temporary_root/desktop/etc/skel/.config/kglobalshortcutsrc" \
  || fail "Klipper's own popup still takes Meta+V from the Lumo clipboard"
grep -Fxq 'IgnoreImages=false' "$temporary_root/desktop/etc/xdg/klipperrc" \
  || fail "the clipboard history leaves pictures out"
grep -Fxq 'DesktopEntry=org.lumo.files' "$temporary_root/desktop/usr/share/knotifications6/lumo-devices.notifyrc" \
  || fail "storage notifications do not come from Files"
m3_tokens="$temporary_root/desktop/usr/lib/x86_64-linux-gnu/qt6/qml/org/lumo/m3/M3.qml"
grep -Fq 'property string generation: "md3"' "$m3_tokens" && grep -Fq '/lumorc' "$m3_tokens" \
  && grep -Fq 'md1: { dark:' "$m3_tokens" && grep -Fq 'md2: { dark:' "$m3_tokens" \
  || fail "the design tokens do not carry the Material generations"
grep -Fxq 'ColorScheme=LumoMD2Dark' "$temporary_root/desktop/usr/share/color-schemes/LumoMD2Dark.colors" \
  || fail "the Material Design 2 colour scheme is misnamed"
shade_sheet="$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.quicksettings/contents/ui/ShadeSheet.qml"
grep -Fq 'i18n("Dark Theme")' "$shade_sheet" && grep -Fq 'i18n("Screenshot")' "$shade_sheet" \
  || fail "quick settings lack the Dark Theme and Screenshot tiles"
grep -Fxq 'X-KDE-Shortcuts=Meta+Ctrl+Alt+Shift+Space' "$temporary_root/desktop/usr/share/kglobalaccel/org.kde.plasma.emojier.desktop" \
  || fail "the emoji selector still takes Meta+. from the Lumo emoji tab"
grep -Fq 'emoji.globalShortcut = "Meta+."' \
  "$temporary_root/desktop/usr/share/plasma/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
  || fail "the Lumo emoji tab does not open with Meta+."
for widget in clock glance weather battery calendar media photo note; do
  widget_root="$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.widget.$widget"
  for path in metadata.json contents/ui/main.qml contents/ui/m3/M3.qml contents/ui/materialshapes.js \
      contents/ui/MaterialShape.qml contents/config/main.xml; do
    [[ -s "$widget_root/$path" ]] || fail "the $widget widget lacks $path"
  done
  python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["KPlugin"]; assert m["Name[ru]"] and m["Description[ru]"]' \
    "$widget_root/metadata.json" || fail "the $widget widget has no Russian name"
  grep -q 'name="placed"' "$widget_root/contents/config/main.xml" \
    || fail "the $widget widget does not remember that it was placed"
done
for widget in glance weather; do
  [[ -s "$temporary_root/desktop/usr/share/locale/ru/LC_MESSAGES/plasma_applet_org.lumo.widget.$widget.mo" ]] \
    || fail "the $widget widget is not translated"
  [[ -s "$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.widget.$widget/contents/ui/WeatherModel.qml" ]] \
    || fail "the $widget widget has no weather source"
done
[[ -s "$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.widget.glance/contents/ui/BatterySource.qml" ]] \
  || fail "At a Glance has no battery source"
[[ -s "$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.widget.media/contents/ui/MediaSource.qml" ]] \
  || fail "the Now Playing widget has no media source"
grep -Fxq 'Script=lumo-add-widgets-menu.sh,sh' "$temporary_root/desktop/usr/share/kconf_update/lumo-add-widgets-menu.upd" \
  || fail "the desktop menu migration is not installed"
grep -Fxq 'ExecStartPre=-/usr/share/kconf_update/lumo-add-widgets-menu.sh' \
  "$temporary_root/desktop/usr/lib/systemd/user/plasma-plasmashell.service.d/lumo-widgets-menu.conf" \
  || fail "the desktop menu lacks Add Widgets until plasmashell restarts"
grep -Fq 'text/x-plasmoidservicename' "$temporary_root/desktop/$shell/explorer/WidgetDrag.qml" \
  || fail "widgets cannot be dragged from the Lumo widget picker"
grep -Fq 'onShouldClose: main.closed()' "$temporary_root/desktop/$shell/explorer/WidgetExplorer.qml" \
  || fail "the Lumo widget picker does not keep Plasma's explorer contract"
[[ -s "$temporary_root/desktop/usr/share/plasma/desktoptheme/lumo/widgets/margins-highlight.svg" ]] \
  || fail "the Plasma theme lets edit mode fall back to Breeze's margin highlight"
grep -Fq 'allowDmaBuf: false' "$temporary_root/desktop/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/LumoWindowThumbnail.qml" \
  || fail "window previews may arrive garbled over DMA-BUF"
grep -Fq 'source: "LumoWindowThumbnail.qml"' "$temporary_root/desktop/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/ToolTipInstance.qml" \
  || fail "the task tooltip does not use the Lumo window preview"
[[ ! -e "$temporary_root/desktop/usr/share/plasma/wallpapers/org.lumo.marbles" ]] || fail "Marble Run is still installed"
[[ ! -e "$temporary_root/desktop/usr/share/plasma/wallpapers/org.lumo.tower" ]] || fail "Tower is still installed"
clipboard_ui="$temporary_root/desktop/usr/share/plasma/plasmoids/org.lumo.clipboard/contents/ui"
[[ -s "$clipboard_ui/EmojiPage.qml" && -s "$clipboard_ui/emoji.js" ]] \
  || fail "the clipboard sheet has no emoji tab"
grep -Fq '"😀","grinning face","широко улыбается"' "$clipboard_ui/emoji.js" \
  || fail "the emoji data lacks English and Russian names"
for file in FolderView.qml LumoIconLayout.qml IconPlacement.js; do
  cmp "$project_root/packages/native/lumo-desktop/data/folderview/$file" \
    "$temporary_root/desktop/usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/$file" \
    || fail "the packaged desktop icon layout differs from source: $file"
done
desktop_control=$(mktemp -d /tmp/lumo-desktop-control.XXXXXX)
dpkg-deb --control "$desktop_deb" "$desktop_control"
for file in lockscreen/LockScreen.qml osd/Osd.qml configuration/AppletConfiguration.qml \
    configuration/ConfigurationContainmentAppearance.qml configuration/ConfigurationContainmentActions.qml \
    configuration/AboutPlugin.qml configuration/ConfigurationShortcuts.qml \
    org.kde.desktopcontainment/contents/ui ConfigLocation.qml ConfigIcons.qml ConfigFilter.qml ConfigOverlay.qml FolderView.qml \
    explorer/WidgetExplorer.qml views/DesktopEditMode.qml panelconfiguration/PanelRepresentation.qml \
    org.kde.plasma.panelspacer/contents/ui/main.qml \
    org.kde.plasma.notifications/contents/ui main.qml \
    org.kde.plasma.taskmanager/contents/ui Badge.qml ToolTipInstance.qml kglobalaccel/org.kde.krunner.desktop \
    kglobalaccel/org.kde.plasma.emojier.desktop plymouth/plymouthd.defaults; do
  grep -Fq "$file" "$desktop_control/preinst" \
    || fail "Plasma's $file is not diverted before the Lumo one is unpacked"
done
for name in left_ptr pointer hand2 xterm watch left_ptr_watch grabbing size_ver nesw-resize not-allowed; do
  [[ -e "$temporary_root/desktop/usr/share/icons/lumo_cursors/cursors/$name" ]] \
    || fail "the Lumo cursor theme lacks $name"
done
frames=$(python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(); print(struct.unpack('<I', d[12:16])[0])" \
  "$temporary_root/desktop/usr/share/icons/lumo_cursors/cursors/wait")
(( frames >= 100 )) || fail "the wait cursor is not animated ($frames images)"
grep -q 'update-alternatives --install /usr/share/icons/default/index.theme x-cursor-theme' "$desktop_control/postinst" \
  || fail "Lumo's cursors do not become the default cursor theme"
grep -qx 'Bouncing=false' "$temporary_root/desktop/etc/xdg/klaunchrc" \
  || fail "the bouncing launch icon is still on"
grep -Fq 'import "lumo/global"' "$temporary_root/desktop/$notifications/main.qml" \
  || fail "the notification applet does not load the Lumo popups"
if grep -Eq '^import "global"' "$temporary_root/desktop/$notifications/main.qml"; then
  fail "the notification applet still imports Plasma's popup manager"
fi
grep -q 'dpkg-divert --package lumo-desktop --remove --rename' "$desktop_control/postrm" \
  || fail "the diversions are not removed with the package"
find "$desktop_control" -depth -delete

export LC_ALL=C
(
  cd "$temporary_root/desktop" && find . -type f
) | sort > "$temporary_root/desktop.list"
(
  cd "$temporary_root/installer" && find . -type f
) | sort > "$temporary_root/installer.list"
if comm -12 "$temporary_root/desktop.list" "$temporary_root/installer.list" \
  | grep -q .; then
  fail "the two binary packages ship an overlapping path"
fi

printf 'lumo-desktop binary test: OK\n'
