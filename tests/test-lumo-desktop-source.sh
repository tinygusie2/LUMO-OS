#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-desktop"

fail() {
  printf 'lumo-desktop source test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-parsechangelog grep python3; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done

version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
distribution=$(dpkg-parsechangelog \
  -l"$package_root/debian/changelog" -S Distribution)
[[ "$version" == "1.4.60" ]] || fail "unexpected source version"
[[ "$distribution" == "UNRELEASED" ]] \
  || fail "development package must remain UNRELEASED"
[[ "$(<"$package_root/debian/source/format")" == "3.0 (native)" ]] \
  || fail "wrong source format"
[[ -x "$package_root/debian/rules" ]] || fail "debian/rules is not executable"

control="$package_root/debian/control"
grep -Fxq 'Package: lumo-desktop' "$control" \
  || fail "desktop binary stanza is missing"
grep -Fxq 'Package: lumo-calamares' "$control" \
  || fail "installer binary stanza is missing"
grep -Fxq 'Standards-Version: 4.7.4' "$control" \
  || fail "wrong Standards-Version"
grep -Eq '^ calamares \(>= [^)]*lumo[0-9]+\),$' "$control" \
  || fail "installer configuration does not depend on the Lumo calamares"

data_root="$package_root/data"
for wallpaper in shapes tower rhythm starfall pastel waves aurora; do
  for file in metadata.json contents/ui/main.qml contents/ui/Scene.qml contents/ui/config.qml contents/config/main.xml; do
    [[ -s "$data_root/wallpaper/org.lumo.$wallpaper/$file" ]] \
      || fail "the $wallpaper wallpaper lacks $file"
  done
  [[ -s "$package_root/data/shell/po/plasma_wallpaper_org.lumo.$wallpaper.ru.po" ]] \
    || fail "the $wallpaper wallpaper has no Russian translation"
done
[[ -s "$data_root/wallpaper/org.lumo.tower/contents/ui/tower.js" ]] || fail "the tower's simulation is missing"
for wallpaper in shapes tower rhythm starfall pastel waves aurora; do
  main="$data_root/wallpaper/org.lumo.$wallpaper/contents/ui/main.qml"
  grep -Fq 'root.configuration.SaveBattery && power.unplugged' "$main" \
    || fail "the $wallpaper wallpaper does not slow down on battery"
  grep -Fq '!resting' "$main" || fail "the $wallpaper wallpaper does not rest in power saving"
  grep -Fq '<entry name="SaveBattery" type="Bool">' "$data_root/wallpaper/org.lumo.$wallpaper/contents/config/main.xml" \
    || fail "the $wallpaper wallpaper has no battery setting"
done
for file in Power.qml PowerBattery.qml PowerProfile.qml; do
  [[ -s "$data_root/wallpaper/common/$file" ]] || fail "the wallpapers' $file is missing"
done
for wallpaper in dunes bloom contour; do
  for file in metadata.json contents/ui/main.qml contents/ui/Scene.qml; do
    [[ -s "$data_root/wallpaper/org.lumo.$wallpaper/$file" ]] \
      || fail "the still $wallpaper wallpaper lacks $file"
  done
  grep -Fq '"X-Lumo-Still": true' "$data_root/wallpaper/org.lumo.$wallpaper/metadata.json" \
    || fail "the $wallpaper wallpaper is not marked still"
  grep -Eq 'Timer|FrameAnimation|TasksModel' "$data_root/wallpaper/org.lumo.$wallpaper/contents/ui/main.qml" \
    && fail "the still $wallpaper wallpaper runs a clock"
done
[[ ! -e "$data_root/wallpaper/org.lumo.marbles" ]] || fail "Marble Run is back"
sh -n "$package_root/data/kconf_update/lumo-marbles-to-pastel.sh" || fail "the Marble Run migration does not parse"
marbles_home=$(mktemp -d)
printf '[Greeter]\nWallpaperPlugin=org.lumo.marbles\n' > "$marbles_home/kscreenlockerrc"
XDG_CONFIG_HOME="$marbles_home" sh "$package_root/data/kconf_update/lumo-marbles-to-pastel.sh"
grep -Fxq 'WallpaperPlugin=org.lumo.pastel' "$marbles_home/kscreenlockerrc" \
  || fail "a lock screen with Marble Run does not move to Pastel"
grep -Fq '"org.lumo.pastel"' "$package_root/data/shell-updates/lumo_marbles_to_pastel.js" \
  || fail "desktops with Marble Run do not move to Pastel"
rm -rf "$marbles_home"
themes=$(mktemp -d)
for wallpaper in waves aurora dunes bloom contour; do
  python3 "$package_root/tools/gen-wallpaper-assets" "$themes/$wallpaper" "$wallpaper" >/dev/null \
    || fail "gen-wallpaper-assets cannot write the $wallpaper palette"
done
rm -rf "$themes"
assets=$(mktemp -d)
python3 "$package_root/tools/gen-wallpaper-assets" "$assets" tower >/dev/null \
  || fail "gen-wallpaper-assets cannot write the tower's assets"
grep -q '"hull":\[\[' "$assets/materialshapes.js" || fail "the shapes have no hulls"
grep -q '"paper"' "$assets/palettes/lumo.qml" || fail "the tower's palette has no paper"
LUMO_COLOUR=blue python3 "$package_root/tools/gen-wallpaper-assets" "$assets" tower >/dev/null \
  || fail "gen-wallpaper-assets cannot write the tower's blue palette"
cmp -s "$assets/palettes/lumo.qml" "$assets/palettes/blue.qml" && fail "the wallpaper does not change with the colour"
rm -rf "$assets"
palettes=$(mktemp -d)
for colour in lumo blue grey; do
  LUMO_COLOUR=$colour python3 "$package_root/tools/gen-qml-tokens" --palette "$palettes/$colour.conf" >/dev/null \
    || fail "no $colour palette"
done
grep -Fxq 'id=blue' "$palettes/blue.conf" || fail "the blue palette does not name itself"
grep -Fxq '[md1-light]' "$palettes/blue.conf" || fail "the blue palette lacks Material Design 1"
python3 - "$palettes/grey.conf" <<'PYTHON_TEST' || fail "the grey theme is not grey"
import configparser, sys
c = configparser.ConfigParser(interpolation=None)
c.optionxform = str
c.read(sys.argv[1])
rgb = bytes.fromhex(c["md3-dark"]["primary"])
assert max(rgb) - min(rgb) <= 6, rgb.hex()
PYTHON_TEST
LUMO_COLOUR=violet python3 "$package_root/tools/gen-qml-tokens" --palette "$palettes/x.conf" >/dev/null 2>&1 \
  && fail "an unknown colour was accepted"
rm -rf "$palettes"
[[ ! -e "$data_root/wallpapers" ]] || fail "picture wallpapers are back in the package"
grep -Fxq 'path-exclude=/usr/share/wallpapers/Next/*' "$data_root/dpkg/lumo-wallpapers" \
  || fail "Breeze's picture wallpaper is not kept out"

defaults="$data_root/look-and-feel/org.lumo.desktop/contents/defaults"
[[ -s "$defaults" ]] || fail "look-and-feel defaults are missing"
grep -Fq 'wallpaperPlugin = "org.lumo.shapes"' "$data_root/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
  || fail "the default layout does not use Lumo Shapes"
grep -Fxq 'cursorTheme=lumo_cursors' "$defaults" \
  || fail "look-and-feel does not select the Lumo cursors"
[[ -x "$package_root/tools/gen-cursor-theme" ]] || fail "the cursor theme generator is missing"
grep -Fxq 'Theme=Lumo' "$defaults" \
  || fail "look-and-feel does not select the Lumo icon theme"
grep -Fxq 'Theme=org.lumo.desktop' "$defaults" \
  || fail "look-and-feel does not select the Lumo session splash"
grep -Fq 'loglevel=3' "$package_root/data/grub/lumo.cfg" \
  && grep -Fq 'update-grub' "$package_root/debian/lumo-desktop.postinst" \
  || fail "installed systems print kernel errors over the boot splash"
grep -Fq 'Keys.onReturnPressed: event => event.accepted = true' "$package_root/data/widgets/common/CityPicker.qml" \
  || fail "Enter in the city search closes the widget settings"
grep -Fq 'property Timer watch' "$package_root/data/widgets/common/WeatherModel.qml" \
  && grep -Fq 'text: weather.city' "$package_root/data/widgets/weather/contents/ui/main.qml" \
  || fail "the weather widget does not show the chosen city"
grep -Fq 'function commit()' "$package_root/data/widgets/common/CityPicker.qml" \
  && grep -Fq 'picker.commit()' "$package_root/data/widgets/weather/contents/ui/ConfigLocation.qml" \
  && grep -Fq 'picker.commit()' "$package_root/data/widgets/glance/contents/ui/ConfigWeather.qml" \
  && grep -Fq 'onTextChanged: typing.restart()' "$package_root/data/widgets/common/CityPicker.qml" \
  || fail "the weather city does not follow Apply or does not search while typing"
grep -Fq 'readonly property bool shown: Plasmoid.configuration.interactiveMute' "$package_root/data/taskmanager/AudioStream.qml" \
  && grep -Fq '"$tasks/AudioStream.qml"' "$package_root/debian/lumo-desktop.preinst" \
  && grep -Fq '"$tasks/AudioStream.qml"' "$package_root/debian/lumo-desktop.postrm" \
  || fail "the task audio indicator ignores its setting"
grep -Fq 'RightButton;NoModifier=org.kde.contextmenu' "$package_root/data/kconf_update/lumo-add-widgets-menu.sh" \
  || fail "a new user's desktop can lose its right-click menu"
drivers="$package_root/data/drivers"
bash -n "$drivers/lumo-drivers" || fail "lumo-drivers is not valid bash"
[[ -x "$drivers/lumo-drivers" ]] || fail "lumo-drivers is not executable"
[[ "$(gpg --show-keys --with-colons "$drivers/nvidia-archive-keyring.gpg" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')" == 02182E60104FCDC26EAE1B8597A5D4CB8793F200 ]] \
  || fail "the NVIDIA archive key is not NVIDIA's Debian 13 key"
grep -Fq 'OnActiveSec=90s' "$drivers/lumo-drivers.timer" \
  && grep -Fq 'ExecStart=/usr/libexec/lumo-drivers auto' "$drivers/lumo-drivers.service" \
  && grep -Fq 'ExecStart=/usr/libexec/lumo-drivers %i' "$drivers/lumo-drivers@.service" \
  || fail "the driver check is not scheduled"
grep -Fq '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/lumo-drivers</annotate>' "$drivers/org.lumo.drivers.policy" \
  || fail "Settings cannot run lumo-drivers"
grep -Fxq '  - shellprocess@drivers' "$package_root/data/calamares/settings.conf" \
  && grep -Fq 'lumo-drivers install --target' "$package_root/data/calamares/modules/shellprocess-drivers.conf" \
  || fail "the installer does not install graphics drivers"
grep -Fxq 'ColorScheme=LumoDark' "$defaults" \
  || fail "look-and-feel does not select the Lumo colour scheme"
grep -Fxq 'name=lumo' "$defaults" \
  || fail "look-and-feel does not select the Lumo Plasma theme"

tools_root="$package_root/tools"
for tool in gen-color-schemes gen-icon-theme gen-kdeglobals gen-plasma-theme \
  gen-qml-tokens gen-translations fetch-symbols gen-wallpaper-assets \
  gen-kvantum-theme gen-aurorae-theme gen-avatar gen-avatars gen-terminal-theme gen-greeter-palette \
  gen-keyboard-maps gen-qm gen-installer-icons gen-installer-style gen-browser-theme gen-gtk-theme gen-sound-theme gen-plymouth-theme gen-grub-theme gen-emoji-data; do
  [[ -x "$tools_root/$tool" ]] || fail "design-system tool missing: $tool"
done
grep -Fxq 'pref("extensions.activeThemeID", "theme@lumo.os");' "$package_root/data/librewolf/lumo.js" \
  || fail "LibreWolf does not default to the Lumo theme"
grep -Fxq 'pref("widget.use-xdg-desktop-portal.file-picker", 1);' "$package_root/data/librewolf/lumo.js" \
  || fail "LibreWolf does not pick files in the Lumo chooser"
mimeapps="$package_root/data/xdg-mimeapps/mimeapps.list"
for default in 'x-scheme-handler/https=librewolf.desktop;' 'text/html=librewolf.desktop;' \
  'image/png=org.lumo.photos.desktop;' 'application/json=org.lumo.editor.desktop;'; do
  grep -Fxq "$default" "$mimeapps" || fail "mimeapps.list lacks $default"
done
grep -Fxq "gtk-theme='Lumo'" "$package_root/data/gtk/90_lumo.gschema.override" \
  || fail "GTK applications do not default to the Lumo theme"
for version in 3.0 4.0; do
  grep -Fxq 'gtk-theme-name=Lumo' "$package_root/data/skel-config/gtk-$version/settings.ini" \
    || fail "new accounts do not start with the Lumo GTK $version theme"
done
sh -n "$package_root/data/kconf_update/lumo-gtk-theme.sh" || fail "the GTK theme migration does not parse"
gtk_themes=$(mktemp -d)
for generation in md1 md2 md3; do
  LUMO_GENERATION=$generation python3 "$tools_root/gen-gtk-theme" "$gtk_themes" >/dev/null \
    || fail "gen-gtk-theme fails for $generation"
done
for theme in Lumo LumoMD1 LumoMD2; do
  for file in gtk-3.0/gtk.css gtk-3.0/gtk-dark.css gtk-4.0/gtk.css gtk-4.0/gtk-dark.css; do
    grep -q '@import url("../../Breeze/' "$gtk_themes/$theme/$file" || fail "$theme/$file does not build on Breeze"
  done
done
rm -rf "$gtk_themes"
grep -Fxq 'pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "$package_root/data/librewolf/lumo.js" \
  || fail "LibreWolf does not load the Lumo dialog style"
link_script="$package_root/data/kconf_update/lumo-librewolf-chrome.sh"
sh -n "$link_script" || fail "the LibreWolf dialog style script does not parse"
browser=$(mktemp -d)
python3 "$tools_root/gen-browser-theme" "$browser/theme.xpi" "$browser/userChrome.css" >/dev/null \
  || fail "gen-browser-theme fails"
grep -Fq 'button[dlgtype][default] {' "$browser/userChrome.css" \
  || fail "the LibreWolf dialog style does not fill the default button"
sed "s|^sheet=.*|sheet=$browser/userChrome.css|" "$link_script" > "$browser/link.sh"
HOME="$browser/new" XDG_CONFIG_HOME="$browser/new/.config" sh "$browser/link.sh"
new_root="$browser/new/.config/librewolf/librewolf"
[[ "$(readlink "$new_root/lumo.default-default/chrome/userChrome.css")" == "$browser/userChrome.css" ]] \
  || fail "a new account's LibreWolf profile does not get the Lumo dialog style"
grep -Fxq '[Install6C4726F70D182CF7]' "$new_root/profiles.ini" \
  && grep -Fxq 'Default=lumo.default-default' "$new_root/installs.ini" \
  || fail "LibreWolf would not use the prepared profile"
own_root="$browser/own/.config/librewolf/librewolf"
mkdir -p "$own_root/mine.default/chrome" "$own_root/plain.default"
printf '[Profile0]\nIsRelative=1\nPath=mine.default\n\n[Profile1]\nIsRelative=1\nPath=plain.default\n' > "$own_root/profiles.ini"
printf 'own\n' > "$own_root/mine.default/chrome/userChrome.css"
HOME="$browser/own" XDG_CONFIG_HOME="$browser/own/.config" sh "$browser/link.sh"
[[ "$(<"$own_root/mine.default/chrome/userChrome.css")" == own ]] \
  || fail "the Lumo dialog style replaced a user's own userChrome.css"
[[ "$(readlink "$own_root/plain.default/chrome/userChrome.css")" == "$browser/userChrome.css" ]] \
  || fail "an existing LibreWolf profile does not get the Lumo dialog style"
[[ ! -e "$own_root/lumo.default-default" ]] || fail "a profile was added next to existing ones"
rm -rf "$browser"
grep -Fxq "theme-name='lumo'" "$package_root/data/gtk/90_lumo.gschema.override" \
  || fail "GTK applications do not default to the Lumo sounds"
grep -Fxq 'gtk-sound-theme-name=lumo' "$package_root/data/skel-config/gtk-3.0/settings.ini" \
  || fail "new accounts do not start with the Lumo sounds"
sh -n "$package_root/data/kconf_update/lumo-sound-theme.sh" || fail "the sound theme migration does not parse"
sh -n "$package_root/data/kconf_update/lumo-terminal-entry.sh" || fail "the terminal entry migration does not parse"
sh -n "$package_root/data/kconf_update/lumo-add-widgets-menu.sh" || fail "the widgets menu migration does not parse"
sh -n "$package_root/data/kconf_update/lumo-projection-shortcut.sh" || fail "the projection shortcut migration does not parse"
grep -Fxq 'display=none,Display\tMeta+P,Switch Display' "$package_root/data/skel-config/kglobalshortcutsrc" \
  || fail "the KDE screen switcher still takes Meta+P"
menu_home=$(mktemp -d)
XDG_CONFIG_HOME="$menu_home" sh "$package_root/data/kconf_update/lumo-add-widgets-menu.sh"
XDG_CONFIG_HOME="$menu_home" sh "$package_root/data/kconf_update/lumo-add-widgets-menu.sh"
[[ "$(grep -c "add widgets=true" "$menu_home/plasma-org.kde.plasma.desktop-appletsrc")" == 1 ]] \
  || fail "the desktop menu does not offer Add Widgets exactly once"
rm -rf "$menu_home"
sh -n "$package_root/data/crash/lumo-panic-report" || fail "the panic report does not parse"
for widget in clock glance weather battery calendar media photo note; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$package_root/data/widgets/$widget/metadata.json" \
    || fail "the $widget widget metadata is not JSON"
  xmllint --noout "$package_root/data/widgets/$widget/contents/config/main.xml" \
    || fail "the $widget widget configuration is not XML"
  grep -q "^WIDGETS = .*\b$widget\b" "$package_root/debian/rules" || fail "the $widget widget is not built"
done
for po in "$package_root"/data/shell/po/plasma_applet_org.lumo.widget.*.ru.po; do
  msgfmt -c -o /dev/null "$po" 2>/dev/null || fail "$(basename "$po") does not compile"
done
grep -Fq 'api.open-meteo.com/v1/forecast' "$package_root/data/widgets/common/WeatherModel.qml" \
  || fail "the weather widgets do not use Open-Meteo"
grep -Fxq 'kernel.panic = 10' "$package_root/data/crash/90-lumo-panic.conf" \
  || fail "a kernel panic would not restart the computer"
python3 "$tools_root/check-contrast" >/dev/null || fail "a colour theme draws text or icons that blend into their background"
grep -Fxq '  - shellprocess@upgrade' "$package_root/data/calamares/settings.conf" \
  || fail "the installer does not bring the new system up to date"
grep -Fq 'full-upgrade' "$package_root/data/calamares/modules/shellprocess-upgrade.conf" \
  || fail "the installer's update step does not upgrade"
sounds=$(mktemp -d)
python3 "$tools_root/gen-sound-theme" "$sounds" desktop-login,bell >/dev/null || fail "gen-sound-theme fails"
grep -Fxq 'Inherits=freedesktop' "$sounds/lumo/index.theme" || fail "the sound theme does not fall back to freedesktop"
[[ "$(head -c 4 "$sounds/lumo/stereo/desktop-login.wav")" == RIFF ]] || fail "the login sound is not a WAV file"
[[ "$(readlink "$sounds/lumo/stereo/bell-window-system.wav")" == bell.wav ]] || fail "the window bell does not use the bell sound"
rm -rf "$sounds"
avatars=$(mktemp -d)
python3 "$tools_root/gen-avatars" "$avatars" >/dev/null || fail "gen-avatars fails"
[[ "$(find "$avatars" -name '*.svg' | wc -l)" -eq 14 ]] || fail "the profile pictures are not fourteen plus the Lumo mark"
grep -l '<path ' "$avatars"/*.svg | wc -l | grep -qx 14 || fail "a profile picture has no waves"
rm -rf "$avatars"
if grep -rIl 'firefox-esr' "$package_root/data" >/dev/null; then
  fail "the desktop still refers to Firefox: $(grep -rIl 'firefox-esr' "$package_root/data" | head -1)"
fi
PYTHONDONTWRITEBYTECODE=1 python3 - "$tools_root" <<'PY' || fail "the Material generations are incomplete"
import sys
sys.path.insert(0, sys.argv[1])
import lumo_design as design
roles = set(design.palette("md3", True))
for generation in design.GENERATIONS:
    for dark in (True, False):
        assert set(design.palette(generation, dark)) == roles, (generation, dark)
for kind, values in design.CORNERS.items():
    assert len(values) == len(design.GENERATIONS), kind
for kind, values in design.ELEVATION_LEVEL.items():
    assert len(values) == len(design.GENERATIONS), kind
PY
icons=$(mktemp -d)
python3 "$tools_root/gen-icon-theme" "$package_root/data/symbols" "$icons/Lumo" >/dev/null \
  || fail "gen-icon-theme fails"
grep -Fxq 'Inherits=breeze-dark,breeze,hicolor' "$icons/Lumo/index.theme" \
  || fail "icon theme does not inherit Breeze and would lose every other icon"
LUMO_COLOUR=blue python3 "$tools_root/gen-icon-theme" "$package_root/data/symbols" "$icons/Lumo-blue" >/dev/null \
  || fail "gen-icon-theme fails for a colour"
grep -Fxq 'Inherits=Lumo,breeze-dark,breeze,hicolor' "$icons/Lumo-blue/index.theme" \
  || fail "a colour's icons do not fall back to Lumo's"
[[ "$(find "$icons/Lumo-blue/scalable" -name '*.svg' -type f | wc -l)" -eq 14 ]] \
  || fail "a colour's icon theme should hold only the fourteen app icons"
find "$icons/Lumo-blue" -name 'preferences-system*' | grep -q . \
  && fail "a colour's icons would shadow preferences-system-* through KDE's generic fallback"
rm -rf "$icons"
grep -Fq 'LookAndFeelPackage=org.lumo.desktop' "$tools_root/gen-kdeglobals" \
  || fail "Lumo look-and-feel is not the system default"
PYTHONDONTWRITEBYTECODE=1 python3 "$tools_root/fetch-symbols" --check >/dev/null \
  || fail "vendored Material Symbols do not match data/symbols.lock"
[[ -s "$data_root/symbols/LICENSE" ]] || fail "Material Symbols licence is missing"

shell_root="$data_root/shell"
for applet in launcher:org.lumo.launcher shade:org.lumo.quicksettings clipboard:org.lumo.clipboard; do
  directory=${applet%%:*}
  id=${applet#*:}
  grep -Fq "\"Id\": \"$id\"" "$shell_root/$directory/metadata.json" \
    || fail "applet $directory does not declare the id $id"
  [[ -s "$shell_root/$directory/contents/ui/main.qml" ]] \
    || fail "applet $directory has no main.qml"
  grep -Fq "\"$id\"" \
    "$data_root/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
    || fail "default layout does not place $id"
  [[ -s "$shell_root/po/plasma_applet_$id.ru.po" ]] \
    || fail "applet $id has no Russian catalog"
done
while read -r first second third; do
  file=$second
  [[ "$first" == "singleton" ]] && file=$third
  [[ "$file" == "M3.qml" || -s "$shell_root/m3/$file" ]] \
    || fail "qmldir names a missing component: $file"
done < "$shell_root/m3/qmldir"
if grep -rEn 'M3\.on[A-Z]' "$shell_root" "$data_root/style" >/dev/null; then
  fail "QML uses an M3.on* role; use the *Content spelling"
fi

wallpaper_plugin="$data_root/wallpaper/org.lumo.shapes"
grep -Fq '"Id": "org.lumo.shapes"' "$wallpaper_plugin/metadata.json" \
  || fail "live wallpaper does not declare its id"
for file in main.qml Scene.qml choreography.js config.qml; do
  [[ -s "$wallpaper_plugin/contents/ui/$file" ]] \
    || fail "live wallpaper is missing $file"
done
grep -Fq '"org.lumo.shapes"' \
  "$data_root/look-and-feel/org.lumo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" \
  || fail "default layout does not select the live wallpaper"

style="$data_root/style/org.lumo.desktop"
grep -Fxq 'module org.lumo.desktop' "$style/qmldir" \
  || fail "Qt Quick style module is misnamed"
grep -Fxq 'import org.kde.desktop auto' "$style/qmldir" \
  || fail "Qt Quick style has no fallback to the desktop style"
while read -r type _version file; do
  [[ "$type" == module || "$type" == import ]] && continue
  [[ -s "$style/$file" ]] || fail "Qt Quick style names a missing control: $file"
done < "$style/qmldir"
grep -Fxq 'export QT_QUICK_CONTROLS_STYLE=org.lumo.desktop' \
  "$data_root/plasma-env/lumo-qtquick-style.sh" \
  || fail "the session does not select the Lumo Qt Quick style"
grep -Fq 'org.lumo.desktop.so' "$package_root/debian/lumo-desktop.links" \
  || fail "Kirigami has no platform plugin under the Lumo style name"

grep -Fxq 'widgetStyle=kvantum-dark' "$defaults" \
  || fail "look-and-feel does not select the Kvantum widget style"
grep -Fxq 'theme=__aurorae__svg__lumo' "$defaults" \
  || fail "look-and-feel does not select the Lumo window decoration"
grep -Fxq 'theme=Lumo' "$data_root/kvantum/kvantum.kvconfig" \
  || fail "Kvantum does not default to the Lumo theme"
grep -Fq '"widgetStyle=kvantum-dark"' "$tools_root/gen-kdeglobals" \
  || fail "system defaults do not select the Kvantum widget style"
if grep -Fq '"AccentColor"' "$tools_root/kde_colors.py"; then
  fail "colour schemes carry an accent colour"
fi
splash="$data_root/look-and-feel/org.lumo.desktop/contents/splash/Splash.qml"
[[ -s "$splash" ]] || fail "session splash is missing"
grep -Fq 'images/lumo.png' "$splash" \
  || fail "splash does not draw the Lumo mark"
if grep '^import' "$splash" | grep -qv '^import QtQuick$'; then
  fail "splash imports something other than QtQuick"
fi
grep -Fxq 'Current=lumo' "$data_root/sddm.conf.d/lumo-theme.conf" \
  || fail "greeter does not use the Lumo login screen"
grep -Fxq 'InputMethod=' "$data_root/sddm.conf.d/lumo-theme.conf" \
  || fail "the login screen would show the virtual keyboard"
[[ -s "$data_root/sddm-theme/lumo/Main.qml" ]] || fail "the Lumo login screen is missing"
grep -Fxq 'DisplayServer=wayland' "$data_root/sddm.conf.d/lumo-wayland.conf" \
  || fail "the login screen does not run on Wayland"
grep -Eq '^CompositorCommand=kwin_wayland ' "$data_root/sddm.conf.d/lumo-wayland.conf" \
  || fail "the login screen is not drawn by KWin"
grep -Fxq 'data/sddm.conf.d/lumo-wayland.conf etc/sddm.conf.d' "$package_root/debian/lumo-desktop.install" \
  || fail "the Wayland login screen setting is not installed"

settings="$data_root/calamares/settings.conf"
[[ -s "$settings" ]] || fail "installer settings are missing"
grep -Fxq 'branding: lumo' "$settings" \
  || fail "installer does not use the Lumo branding"
for module in partition mount unpackfs users removeuser bootloader umount; do
  grep -Fq "  - $module" "$settings" \
    || fail "installer sequence is missing the $module module"
done

for page in $(awk '/^  - [a-z]+q$/ { print $2 }' "$settings" | sort -u); do
  [[ -s "$data_root/calamares/branding/lumo/$page.qml" ]] \
    || fail "installer page has no Lumo QML: $page"
done
keymaps="$data_root/calamares/branding/lumo/keymaps.js"
for layout in '"us":' '"ru":' '"ru(phonetic)":' '"de":'; do
  grep -Fq "$layout" "$keymaps" || fail "keyboard table lacks $layout"
done

scratch_qm=$(mktemp)
python3 "$tools_root/gen-qm" "$data_root/calamares/lang/calamares-lumo_ru.ts" "$scratch_qm" >/dev/null \
  || fail "the installer's Russian supplement does not compile"
rm -f "$scratch_qm"

for config in unpackfs users removeuser shellprocess bootloader packages partition; do
  [[ -s "$data_root/calamares/modules/$config.conf" ]] \
    || fail "missing module configuration: $config.conf"
done

# shellcheck disable=SC1091
source "$project_root/configs/live/live-user.env"
grep -Fxq "username: $LIVE_USER" "$data_root/calamares/modules/removeuser.conf" \
  || fail "installer does not remove the live account defined for the image"
grep -Fq 'getent group autologin | cut -d: -f4 | grep -q . || rm -f /etc/xdg/kwalletrc' \
  "$data_root/calamares/modules/shellprocess.conf" \
  || fail "an installed system with automatic login would ask to set up a wallet"

logo="$data_root/icons/lumo-logo.svg"
[[ -s "$logo" ]] || fail "logo master is missing"
grep -q 'viewBox=' "$logo" || fail "logo has no viewBox and cannot scale"
grep -q '<image' "$logo" && fail "logo embeds a raster image"
grep -Eq 'stroke="(?!none)' "$logo" 2>/dev/null && fail "logo uses strokes"

branding="$data_root/calamares/branding/lumo/branding.desc"
grep -Fq 'productName:         Lumo' "$branding" \
  || fail "installer branding does not name Lumo"
[[ -s "$data_root/calamares/branding/lumo/lumo-welcome.png" ]] \
  || fail "installer welcome image is missing"
grep -Fq 'productLogo:    "lumo-logo.png"' "$branding" \
  || fail "branding does not point at the generated logo"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$tools_root" python3 - "$branding" <<'PYTHON_TEST' \
  || fail "installer sidebar colours drifted from the design tokens"
import sys
import lumo_design as design
text = open(sys.argv[1], encoding="utf-8").read()
for key, role in (("SidebarBackground", "surfaceContainerLow"), ("SidebarText", "onSurfaceVariant"),
                  ("SidebarTextCurrent", "onPrimaryContainer"), ("SidebarBackgroundCurrent", "primaryContainer")):
    line = f'{key}:'.ljust(26) + f'"{design.DARK[role]}"'
    if line not in text:
        raise SystemExit(f"{key} is not {role}")
PYTHON_TEST

grep -Fq 'import org.lumo.shell' "$package_root/data/editmode/ConfigOverlay.qml" \
  && grep -Fq 'overlay.appletSettings.open(applet.plasmoid, overlay)' "$package_root/data/editmode/ConfigOverlay.qml" \
  || fail "a widget's settings end edit mode"

printf 'lumo-desktop source test: OK\n'
