# Apps: the Lumo applications and installer

Lumo keeps KDE Plasma as its desktop technology and replaces what the
user sees of KDE with its own applications. They share the Material 3 design
of the shell: the same tokens, components, symbols and motion.

## Packages

| Package | What it carries |
| --- | --- |
| `lumo-desktop` | The QML modules `org.lumo.m3` (tokens, text, icons, sliders, state layers) and `org.lumo.ui` (pages, list rows, groups, dialogs, fields, navigation), the Terminal entry and colours, light variants of the Plasma theme and window frames, app icons. |
| `lumo-apps` | The applications and `org.lumo.system`, the C++ Qt Quick module through which they read and change the system, plus `lumo-update-notifier` (see [UPDATES.md](UPDATES.md#notifications)). |
| `lumo-calamares` | The installer: Calamares configuration, the Material 3 branding and the `lumo-installer` launcher. Removed from the installed system. |
| `calamares` (derived) | Debian's Calamares rebuilt with the Lumo partition page patch (`packages/derived/calamares`). |

## Applications

| Application | Replaces | Notes |
| --- | --- | --- |
| Settings (`lumo-settings`) | System Settings | Categories with search; every page changes the real setting (NetworkManager, BlueZ, PipeWire, KScreen, KWin, PowerDevil, AccountsService, timedated, PackageKit…). `/usr/bin/systemsettings` is diverted to it, so `systemsettings kcm_…` from Plasma opens the matching page; modules without a Lumo page open in their own window. |
| Files (`lumo-files`) | Dolphin | Places and drives (mount, eject), grid and list, copy/move/rename through KIO, the freedesktop trash with restore, ZIP and archive extraction (bsdtar). |
| Text Editor (`lumo-editor`) | Kate, KWrite | KSyntaxHighlighting, find and replace, line numbers, unsaved-change guard. |
| Photos (`lumo-photos`) | Gwenview | Gallery of Pictures, viewer with zoom, rotation, slideshow, details, wallpaper. |
| Media Player (`lumo-player`) | Elisa, Dragon | Qt Multimedia over FFmpeg; video with auto-hiding controls, music with a queue from the folder. |
| Calculator (`lumo-calculator`) | KCalc | Own expression parser (no `eval`), scientific functions, history. |
| Task Manager (`lumo-taskmanager`) | System Monitor | Apps (ksysguard's `ApplicationDataModel`, one row per app cgroup), background processes (`ProcessDataModel`, the user's own or all) and Performance (CPU, memory, graphics, disk and network charts from ksystemstats through KQuickCharts). Ending sends SIGTERM through `ProcessController` (KAuth for other users' processes) and offers Force quit (SIGKILL) when the process is still there after five seconds. Ctrl+Shift+Esc and Ctrl+Esc open it (the entry is installed into `/usr/share/kglobalaccel`). |
| Screenshot (`lumo-screenshot`) | Spectacle | KWin ScreenShot2 (the desktop entry must name `/usr/bin/lumo-screenshot`), area/screen/window, saved and copied. Bound to Print. |
| Terminal (`lumo-terminal`) | Konsole | Its own terminal view (`org.lumo.terminal`, a `QQuickPaintedItem` on libvterm with a pty from `forkpty`), tabs, 10 000 lines of history, colours read from `~/.config/alacritty/lumo-colors.toml` (written by Settings when the theme changes) or `/usr/share/lumo/terminal/{dark,light}.toml`, and Windows-style copy and paste: Ctrl+C copies a selection and otherwise interrupts, Ctrl+V pastes, a right click copies or pastes. bash starts with `/usr/share/lumo/terminal/lumo.bashrc`, which loads the user's `~/.bashrc`, sets the `folder>` prompt, reports the folder (OSC 7) and title, and adds the Windows commands (`dir`, `cls`, `copy`, `move`, `ren`, `del`, `md`, `rd`, `type`, `cd..`, `ipconfig`, `tasklist`, `taskkill`, `where`, `ver`, `start`; `help` lists them, translated through the `lumo-terminal` domain). Other login shells run without it. Ctrl+Alt+T opens it (the entry is in lumo-desktop and linked into `/usr/share/kglobalaccel`); Ctrl+Shift+T and Ctrl+Shift+W open and close tabs, Ctrl+plus and Ctrl+minus change the text size. |
| Welcome (`lumo-welcome`) | Plasma Welcome | Runs at the first logins of an installed system (`--first-run`, closes in the live session) until finished. |
| File chooser (`lumo-filechooser`) | KDE's file dialog | Every program's open, save and folder dialogs; see below. |

The web browser is LibreWolf, which also opens PDFs; `/etc/xdg/mimeapps.list`
(lumo-desktop) makes it the default for the web and PDFs and keeps
pictures with Photos and JSON and XML with the Text Editor, as LibreWolf
claims those types too. It is not a Debian package: `scripts/fetch-librewolf`
downloads the version pinned in `configs/upstream/librewolf.env` after
checking the repository's InRelease against the key pinned in
`keys/librewolf-fingerprint.txt`, and the installed system takes updates from
`/etc/apt/sources.list.d/librewolf.sources`. The Lumo theme
(`tools/gen-browser-theme`) is a distribution add-on that LibreWolf installs
into new profiles. `lumo.js` in `/usr/share/librewolf/browser/defaults/preferences`
makes it the default and allows it unsigned: that directory is read after the
browser's built-in defaults, which `defaults/pref` and `distribution.ini`
are not early or late enough to override for the add-on manager.
LibreWolf draws its own dialogs, such as its language prompt, with only the
colours from GTK. `gen-browser-theme` therefore also writes a `userChrome.css`
(`/usr/share/lumo/librewolf`) that makes their buttons Material pills,
tonal and the default one filled, and `lumo.js` lets LibreWolf load
`userChrome.css` files. `kconf_update/lumo-librewolf-chrome.sh` links the
file into each LibreWolf profile of the account once, and leaves a profile
that has its own. For a new account it also writes the profile list LibreWolf
would create on its first start (`profiles.ini`, `installs.ini`, with the
install hash of `/usr/share/librewolf`), so even that first start has the
style.
LibreWolf's own policies (uBlock Origin, no telemetry) are untouched, since a
policies file of ours in `/etc/librewolf/policies` would replace them rather
than add to them.
About > Legal reads LibreWolf's copyright summary from
`/usr/share/lumo/copyright/librewolf`, as its package has none.

The KDE applications in the
"Replaces" column are pinned out of the image
(`configs/live/excluded-packages.txt`); System Settings stays installed for
the modules it carries, behind the diverted command.

## Advanced settings

The "advanced" rows in Settings open Lumo pages, not KDE's modules:

| Row | Page | What it changes |
| --- | --- | --- |
| Sound > Advanced sound settings | `SoundDevicesPage`, `SoundDevicePage` | Card profiles, each output's and input's connector, volume per channel, speaker test, notification sound volume, volume above 100% and the volume step (`plasmaparc`). It uses Plasma's `org.kde.plasma.private.volume`, as the main page does. |
| Language & region > Detailed formats | `FormatsPage` | `LC_NUMERIC`, `LC_TIME`, `LC_MONETARY`, `LC_MEASUREMENT` and `LC_PAPER` in `plasma-localerc`, each "as in the region" or its own region; a missing locale is generated first. |
| Keyboard > Advanced keyboard options | `KeyboardOptionsPage`, `KeyboardOptionGroupPage` | The keyboard model and every XKB option from `evdev.xml` (kxkbrc `Model`, `Options`), with the Compose key, Caps Lock, the third-level key and Alt/Meta up front. |
| Keyboard, mouse & touchpad > Touchpad and mouse options | `PointerOptionsPage` | KWin's input device properties: scrolling method, right click method, tap and drag, drag lock, two-finger tap, middle click, acceleration profile, turning the touchpad off while a mouse is connected, and defaults. |
| Battery & power > Advanced power settings | `PowerAdvancedPage` | Low and critical battery levels and the critical action, the warning level of wireless devices, the power mode for each state, the sleep mode and pausing media (`powerdevilrc`). The main page also has the low battery profile. |
| Display & brightness > Arrange screens and more | `DisplayArrangementPage` | Dragging screens into place (they snap to each other's edges), mirroring, and per screen adaptive sync, colour range, HDR, overscan and the ICC profile where the screen supports them. |
| Keyboard, mouse & touchpad > Keyboard shortcuts (also in Apps) | `ShortcutsPage` | Every global shortcut kglobalaccel knows, grouped and searchable. A new shortcut is recorded while global shortcuts are blocked; one already in use is taken from the other action. Default and no shortcut are one tap away (`setForeignShortcut`). |
| Account > Manage accounts | `AccountsPage`, `UserPage` | Adding an account (the user name is made from the name, Cyrillic transliterated), making it an administrator or not, a new password and deleting it with or without its files, through AccountsService. |
| Wallpaper & style > Fonts | `FontsPage` | The interface typeface and size and the typeface and size for code and terminals, with a preview (kdeglobals `font`, `menuFont`, `toolBarFont`, `smallestReadableFont`, `fixed` and the title bar font). |
| Accessibility > More accessibility options | `AccessibilityMorePage` | Sticky keys options, slow and bounce key delays, turning features on from the keyboard, Caps Lock and Num Lock sounds, mouse keys and their speed, the system bell (`kaccessrc`) and shaking the pointer to find it (KWin's `shakecursor`). |

KWin 6.3 has no mirroring of its own: like KDE's module, Lumo puts the
mirror at the same position as its source, and finds mirrors that way.

File types and the network connection editor still open KDE's modules.

Files copies and moves without KIO's own dialogs: it looks for name
conflicts first (`Files.conflicts`) and asks in a Lumo dialog whether to
replace, keep both or skip, then runs the job without a UI delegate
(`Files.transfer`). Pasting into the same folder makes a numbered copy.

## File chooser

Programs ask for files through the desktop portal, and the portal hands
the FileChooser interface to `lumo-filechooser`, a backend that D-Bus
starts on the first request and that leaves five minutes after the last.
Each request gets a window from `share/lumo/filechooser/Chooser.qml`,
built from Files' places, path bar and tiles.

* Routing: `/etc/xdg-desktop-portal/kde-portals.conf` takes precedence
  over xdg-desktop-portal-kde's copy and names `lumo;kde` for
  FileChooser (KDE's dialog is the fallback). The `lumo.portal` file
  declares the backend, and the D-Bus service file starts it.
* Programs: `/etc/xdg/plasma-workspace/env/lumo-file-dialogs.sh` sets
  `PLASMA_INTEGRATION_USE_PORTAL=1`, so Qt programs, Plasma included,
  stop showing KFileWidget, and `GTK_USE_PORTAL=1` does the same for GTK 3.
  LibreWolf's Lumo defaults set `widget.use-xdg-desktop-portal.file-picker`.
* Requests: the backend supports opening one file or several, choosing a
  folder, saving, and saving several files into a folder. It applies the
  program's filters (MIME types turn into globs), suggests a name and asks
  before replacing a file. A program's own choices appear as chips.
* Start folder: when the program names none (Qt never does for opening),
  a picture, music or video filter starts in Pictures, Music or Videos.
  Otherwise the chooser opens the folder of the last choice
  (`lumo-filesrc` `[Chooser] LastFolder`).
* Window: Qt programs on Wayland pass `x11:<id>` as their window, so the
  chooser cannot be made their child. `/etc/xdg/kwinrulesrc` keeps it
  centred, above other windows and out of the task bar. GTK programs pass
  a real `wayland:` handle, which `KWindowSystem::setMainWindow` uses.
  Programs that create a QGuiApplication instead of a QApplication, such as
  `qml6`, get Qt's own fallback dialog: plasma-integration offers native
  dialogs only to QApplication programs.

## Light and dark

`Appearance.setDark()` in `org.lumo.system` switches everything together:
the colour scheme (`LumoDark`/`LumoLight`), the Kvantum variant, the
Plasma theme (`lumo`/`lumo-light`), the Aurorae frame
(`lumo`/`lumo-light`) and the terminal colours
(`~/.config/alacritty/lumo-colors.toml`). The shell and the applications
follow through the palette.

## Installer

`lumo-installer` starts Calamares through pkexec (`org.lumo.installer`;
the live account needs no password) on Xwayland — its QML pages get no
keyboard focus under native Wayland — with the Lumo widget and Qt Quick
styles and the session's language. The branding draws the step list and the
buttons in QML and replaces the welcome, location, keyboard, users, summary
and final pages (`welcomeq.qml`, `localeq.qml`, `keyboardq.qml`,
`usersq.qml`, `summaryq.qml`, `finishedq.qml`). Those files keep Calamares'
own English strings, so its translations apply; the slideshow carries its own
Russian and English text.

The keyboard page draws a Material 3 keyboard with the characters of the
chosen layout and variant. They come from `keymaps.js`, which
`tools/gen-keyboard-maps` generates from Debian's xkb-data with ckbcomp
(console-setup); rerun it when the XKB data changes:

```sh
tools/gen-keyboard-maps XKB_ROOT/usr/share/X11/xkb CONSOLE_SETUP/usr/bin/ckbcomp \
  data/calamares/branding/lumo/keymaps.js
```

Calamares 3.3.14 leaves some messages without Russian (the summary's time
zone and partition lines, installation steps, password checks).
`data/calamares/lang/calamares-lumo_ru.ts` supplies them; the build
compiles it with `tools/gen-qm` into the branding's `lang/`, which Calamares
consults after its own translations.

The partition page is the one Calamares draws with widgets only. Lumo
builds Calamares from Debian's source with a patch
(`packages/derived/calamares`, `make calamares-binary`): flat Material 3 disk
bars and a readable legend in the Lumo palette (also in the size bar of
the partition dialogs), option rows that the branding's `stylesheet.qss`
draws as cards (generated by `tools/gen-installer-style` from the tokens),
and icons taken from the branding's `images/` (generated by
`tools/gen-installer-icons` from Material Symbols). The preview VM carries an
empty 20 GB disk so the partition page can be tried there. The package is built in its own cached build root
(`scripts/create-qt-build-rootfs <dsc> calamares`).

After installation the live-only pieces are removed (autologin, the boot
marker, the boot-menu language service), and Welcome opens at the first
login of the new account.

The boot menu starts the live session in Russian or English
(`lumo.lang=`), which the installer inherits.

## Translations

Each application has its domain (`lumo-settings`, `lumo-files`, …, and
`lumo-system` for the C++ module) in `packages/native/lumo-apps/po`.
`tools/extract-messages` refreshes the templates and merges them into the
translations; the package build compiles them.

## Developing

```sh
scripts/preview-desktop start          # boot the preview VM
scripts/preview-desktop apps           # build the apps incrementally, install them
scripts/preview-desktop apps --qml-only
scripts/preview-desktop launch lumo-settings network
scripts/preview-desktop sync           # the shell, themes, icons and installer files
```
