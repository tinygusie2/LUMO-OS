# Apps: the Lumo applications and installer

Lumo keeps KDE Plasma as its desktop technology and replaces what the
user sees of KDE with its own applications. They share the Material 3 design
of the shell: the same tokens, components, symbols and motion.

## Packages

| Package | What it carries |
| --- | --- |
| `kernora-desktop` | The QML modules `org.kernora.m3` (tokens, text, icons, sliders, state layers) and `org.kernora.ui` (pages, list rows, groups, dialogs, fields, navigation), the Terminal entry and colours, light variants of the Plasma theme and window frames, app icons. |
| `kernora-apps` | The applications and `org.kernora.system`, the C++ Qt Quick module through which they read and change the system, plus `kernora-update-notifier` (see [UPDATES.md](UPDATES.md#notifications)). |
| `kernora-calamares` | The installer: Calamares configuration, the Material 3 branding and the `kernora-installer` launcher. Removed from the installed system. |
| `calamares` (derived) | Debian's Calamares rebuilt with the Lumo partition page patch (`packages/derived/calamares`). |

## Applications

| Application | Replaces | Notes |
| --- | --- | --- |
| Settings (`kernora-settings`) | System Settings | Categories with search; every page changes the real setting (NetworkManager, BlueZ, PipeWire, KScreen, KWin, PowerDevil, AccountsService, timedated, PackageKit…). `/usr/bin/systemsettings` is diverted to it, so `systemsettings kcm_…` from Plasma opens the matching page; modules without a Lumo page open in their own window. |
| Files (`kernora-files`) | Dolphin | Places and drives (mount, eject), grid and list, copy/move/rename through KIO, the freedesktop trash with restore, ZIP and archive extraction (bsdtar). |
| Text Editor (`kernora-editor`) | Kate, KWrite | KSyntaxHighlighting, find and replace, line numbers, unsaved-change guard. |
| Photos (`kernora-photos`) | Gwenview | Gallery of Pictures, viewer with zoom, rotation, slideshow, details, wallpaper. |
| Media Player (`kernora-player`) | Elisa, Dragon | Qt Multimedia over FFmpeg; video with auto-hiding controls, music with a queue from the folder. |
| Calculator (`kernora-calculator`) | KCalc | Own expression parser (no `eval`), scientific functions, history. |
| Screenshot (`kernora-screenshot`) | Spectacle | Works like the Windows Snipping Tool: KWin ScreenShot2 (the desktop entry must name `/usr/bin/kernora-screenshot`), a bar at the top with rectangle, freeform, window and full screen, snips taken on release, saved to Pictures/Screenshots and copied. A notification with a preview opens the snip for pen and highlighter markup. Bound to Print and Meta+Shift+S; `kernora-screenshot resident` starts hidden at login so the shortcut opens instantly. |
| Task Manager (`kernora-tasks`) | System Monitor | Laid out like Windows Task Manager, see below. Reads `/proc` and `/sys` through `Tasks` in `org.kernora.system`. Ctrl+Shift+Esc opens it. |
| Terminal | Konsole | Alacritty started as `org.kernora.terminal`, with colours generated from the tokens and switched with the theme. Ctrl+Alt+T opens it (the entry is linked into `/usr/share/kglobalaccel`). |
| Calendar (`kernora-calendar`) | — | Day, week and month views; events with a time or all day, repeating daily, weekly, monthly or yearly, with a reminder, location and notes; `.ics` import (also by opening the file) and export to Documents. Events are kept in `~/.local/share/kernora/calendar/events.json`. `kernora-calendar reminders` starts hidden at login and sends the reminders (`kernora-calendar.notifyrc`); opening the app shows that instance, and closing the window hides it again. |
| Focus (`kernora-focus`) | — | Focus mode with a Pomodoro timer, see below. |
| Welcome (`kernora-welcome`) | Plasma Welcome | Runs at the first logins of an installed system (`--first-run`, closes in the live session) until finished. |
| File chooser (`kernora-filechooser`) | KDE's file dialog | Every program's open, save and folder dialogs; see below. |

Quick Share with Android phones is RQuickShare. It has no apt repository:
`scripts/fetch-rquickshare` downloads the release `.deb` pinned by URL and
SHA-256 in `configs/upstream/rquickshare.env`, and `build-local-archive`
puts it in the Kernora archive as `r-quick-share`, so the image and installed
systems get it through kernora-apps, which depends on it. kernora-apps
diverts its own menu entry aside and adds `org.kernora.quickshare.desktop`
and an autostart entry; both run `kernora-quickshare`, which sets
RQuickShare's `startminimized` setting (on at login, off from the menu)
before it starts. Settings > Phone opens it and switches the autostart.
Phone and computer have to be on the same network: Quick Share finds devices
with mDNS, which does not cross routers.

The web browser is LibreWolf, which also opens PDFs; `/etc/xdg/mimeapps.list`
(kernora-desktop) makes it the default for the web and PDFs and keeps
pictures with Photos and JSON and XML with the Text Editor, as LibreWolf
claims those types too. It is not a Debian package: `scripts/fetch-librewolf`
downloads the version pinned in `configs/upstream/librewolf.env` after
checking the repository's InRelease against the key pinned in
`keys/librewolf-fingerprint.txt`, and the installed system takes updates from
`/etc/apt/sources.list.d/librewolf.sources`. The Lumo theme
(`tools/gen-browser-theme`) is a distribution add-on that LibreWolf installs
into new profiles. `kernora.js` in `/usr/share/librewolf/browser/defaults/preferences`
makes it the default and allows it unsigned: that directory is read after the
browser's built-in defaults, which `defaults/pref` and `distribution.ini`
are not early or late enough to override for the add-on manager.
LibreWolf draws its own dialogs, such as its language prompt, with only the
colours from GTK. `gen-browser-theme` therefore also writes a `userChrome.css`
(`/usr/share/kernora/librewolf`) that makes their buttons Material pills,
tonal and the default one filled, and `kernora.js` lets LibreWolf load
`userChrome.css` files. `kconf_update/kernora-librewolf-chrome.sh` links the
file into each LibreWolf profile of the account once, and leaves a profile
that has its own. For a new account it also writes the profile list LibreWolf
would create on its first start (`profiles.ini`, `installs.ini`, with the
install hash of `/usr/share/librewolf`), so even that first start has the
style.
LibreWolf's own policies (uBlock Origin, no telemetry) are untouched, since a
policies file of ours in `/etc/librewolf/policies` would replace them rather
than add to them.
About > Legal reads LibreWolf's copyright summary from
`/usr/share/kernora/copyright/librewolf`, as its package has none.

The KDE applications in the
"Replaces" column are pinned out of the image
(`configs/live/excluded-packages.txt`); System Settings stays installed for
the modules it carries, behind the diverted command.

### Task Manager

Task Manager follows Windows Task Manager, with five pages in a side bar:

- **Processes** groups processes the way Windows does. *Apps* are the
  programs you started: a process belongs to an app when its systemd unit is
  an `app-<desktop id>-….scope` or `app-<desktop id>@….service` (how Plasma
  starts programs), and the app's name and icon come from its desktop entry.
  Everything else of yours is a *background process* (apps started at login,
  `@autostart`, are counted here, as Windows does with tray apps); processes
  of other users and of the system are *system processes*. An app with more
  than one process expands to show them. Columns: status, CPU, memory (the
  private part, `RssAnon`), disk (`/proc/<pid>/io`, only readable for your own
  processes) with the totals above them and a colour that deepens with use.
  Click a column to sort, click it again to reverse.
- **Performance** has a tile with a small graph per CPU, memory, disk, network
  adapter and graphics card. CPU shows speed, processes, threads, up time,
  cores, sockets, logical processors (with a graph each), virtualisation and
  L3 cache; memory shows in use, available, committed, cached and swap; disks
  show active time and read and write speed; network adapters show send and
  receive, the IP addresses and link speed; graphics shows how busy the card
  is and its memory where the driver reports it (`amdgpu`).
- **Startup apps** turns login items on and off (unchanged).
- **Details** lists every process with PID, status, user, CPU, memory,
  threads and priority.
- **Services** lists the system's and your systemd services
  (`systemctl list-units --output=json`) and starts, stops and restarts them;
  system services ask for the administrator password through polkit.

The context menu (right-click or long press) and the buttons above the list
offer *End task* (SIGTERM to every process of the row), *Force end* (SIGKILL),
*Efficiency mode* (nice 19 on every thread; turning it off sets nice 0),
*Go to details*, *Open file location*, *Search online* and *Properties*.
Ending another user's process or lowering a nice value runs `pkexec kill` or
`pkexec renice`, so it asks for the administrator password. *Run new task*
starts a program, opens a folder or an internet address. *Update speed* is
High (0.5 s), Normal (1 s), Low (4 s) or Paused and is kept in
`kernora-tasksrc`, as is the last page. Graphs show the last 60 samples.

Shortcuts: Delete ends the selected task, Shift+Delete forces it, Ctrl+F
searches by name or PID, Ctrl+N runs a new task, F5 refreshes, Ctrl+1 to
Ctrl+5 switch pages.

### Focus

Focus is a Pomodoro timer that turns on focus mode while it runs. A session
is a number of focus rounds (25 minutes by default) with a break (5 minutes)
between them; it ends after the last focus round. Settings › Focus mode
chooses the distracting apps, the lengths, the number of rounds, whether Do
Not Disturb is on during focus rounds and whether the distracting apps are
allowed in the breaks. Everything is kept in `kernorafocusrc` (`[General]`
`Apps`, a comma-separated list of desktop entries, `FocusMinutes`,
`BreakMinutes`, `Rounds`, `DoNotDisturb`, `AppsInBreaks`), and the running
timer picks up changes straight away.

While focus mode is on, `Focus.block()` in `org.kernora.system` looks through
`/proc` every two seconds and ends (SIGTERM) the user's processes of a chosen
app: those in its systemd unit (`app-<id>@….service` or `app-<id>-….scope`,
also for Flatpaks) and those running its program from `Exec=`. Focus then
comes to the front and says the app is blocked. Before a session starts,
Focus lists the chosen apps that are open and asks before closing them. Do
Not Disturb uses `org.freedesktop.Notifications.Inhibit`; it is lifted in the
breaks so the break notifications show (`kernora-focus.notifyrc`).

Focus mode is not saved anywhere: it exists only while `kernora-focus` runs
a session. When the timer is over, when you press Stop, or after a restart,
the desktop is back to normal, and the inhibition goes with the process.
Closing the window during a session minimises it instead; the window title
shows the time left. `kernora-focus start` (also the *Start focus* action of
its menu entry and the button in Settings) starts a session.

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
the FileChooser interface to `kernora-filechooser`, a backend that D-Bus
starts on the first request and that leaves five minutes after the last.
Each request gets a window from `share/kernora/filechooser/Chooser.qml`,
built from Files' places, path bar and tiles.

* Routing: `/etc/xdg-desktop-portal/kde-portals.conf` takes precedence
  over xdg-desktop-portal-kde's copy and names `kernora;kde` for
  FileChooser (KDE's dialog is the fallback). The `kernora.portal` file
  declares the backend, and the D-Bus service file starts it.
* Programs: `/etc/xdg/plasma-workspace/env/kernora-file-dialogs.sh` sets
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
  (`kernora-filesrc` `[Chooser] LastFolder`).
* Window: Qt programs on Wayland pass `x11:<id>` as their window, so the
  chooser cannot be made their child. `/etc/xdg/kwinrulesrc` keeps it
  centred, above other windows and out of the task bar. GTK programs pass
  a real `wayland:` handle, which `KWindowSystem::setMainWindow` uses.
  Programs that create a QGuiApplication instead of a QApplication, such as
  `qml6`, get Qt's own fallback dialog: plasma-integration offers native
  dialogs only to QApplication programs.

## Light and dark

`Appearance.setDark()` in `org.kernora.system` switches everything together:
the colour scheme (`KernoraDark`/`KernoraLight`), the Kvantum variant, the
Plasma theme (`kernora`/`kernora-light`), the Aurorae frame
(`kernora`/`kernora-light`) and the terminal colours
(`~/.config/alacritty/kernora-colors.toml`). The shell and the applications
follow through the palette.

## Installer

`kernora-installer` starts Calamares through pkexec (`org.kernora.installer`;
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
  data/calamares/branding/kernora/keymaps.js
```

Calamares 3.3.14 leaves some messages without Russian (the summary's time
zone and partition lines, installation steps, password checks).
`data/calamares/lang/calamares-kernora_ru.ts` supplies them; the build
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

The boot menu starts the live session in English (the default) or Russian
(`kernora.lang=`), which the installer inherits.

## Translations

Each application has its domain (`kernora-settings`, `kernora-files`, …, and
`kernora-system` for the C++ module) in `packages/native/kernora-apps/po`.
`tools/extract-messages` refreshes the templates and merges them into the
translations; the package build compiles them.

## Developing

```sh
scripts/preview-desktop start          # boot the preview VM
scripts/preview-desktop apps           # build the apps incrementally, install them
scripts/preview-desktop apps --qml-only
scripts/preview-desktop launch kernora-settings network
scripts/preview-desktop sync           # the shell, themes, icons and installer files
```

## Bluetooth pairing

`kernora-bluetooth-agent` (kernora-apps, started at login from
`/etc/xdg/autostart`) is the session's BlueZ agent. It registers with the
`DisplayYesNo` capability and asks to be the default agent, again whenever
`bluetoothd` restarts. Pairing requests open a small Material 3 window
(`/usr/share/kernora/bluetoothagent/Main.qml`):

- a PIN or 6-digit passkey the device asks for is typed in;
- a passkey to compare is shown with Pair and Cancel;
- a code to type on a keyboard is shown with a dot for every key pressed;
- a device that pairs by itself, or an untrusted device that wants to use a
  service, has to be allowed. Paired and trusted devices are let through.

The bluedevil KDED module is turned off in `/etc/xdg/kded6rc`
(kernora-desktop), so its agent does not take the requests. Settings >
Bluetooth > Pair a new device starts the pairing; when it fails, the row says
why (wrong code, cancelled, no answer, out of reach).

## Coming from Windows

### Windows programs and games

Wine is installed, and `org.kernora.wine.desktop` (kernora-desktop; Debian's
`wine` has no desktop entry) runs `wine start /unix` on `.exe`, `.msi` and
`.lnk` files, the default for those types in `/etc/xdg/mimeapps.list`.
GameMode (`gamemoderun`) and MangoHud are installed for games; Steam with
Proton, Bottles, Lutris and Heroic come from Flathub through the Store.

### Bring files from Windows

Settings > System > Bring files from Windows (`MigratePage.qml`, also
`kernora-settings migrate` and a link in Welcome) lists NTFS, exFAT and FAT
partitions with `lsblk`, opens closed ones read-only with
`udisksctl mount -o ro`, and offers every `Users/<name>` with a Documents or
Desktop folder, and drives that hold such folders themselves. A folder can be
chosen too. It copies Documents, Pictures, Music, Videos, Desktop and
Downloads into the matching folders with `cp -rn`, so nothing is overwritten;
sets `AppData/Roaming/Microsoft/Windows/Themes/TranscodedWallpaper` as the
wallpaper; and turns the Bookmarks files of Edge, Chrome and Brave into HTML
files in Documents that LibreWolf imports. A drive Windows left hibernated
(Fast Startup) cannot be opened; the page says so.

### Printers & scanners

`PrintersPage.qml` lists the queues CUPS knows (`lpstat -p -d`), makes one the
default with `lpoptions -d` and prints a test page with `lp`. Add a printer,
the queue and advanced options open KDE's print manager (`kde-add-printer`,
`kcm_printer_manager`). CUPS, ipp-usb and sane-airscan make network and USB
printers and scanners work without drivers; Scan a document opens Skanpage.

### Phone

`PhonePage.qml` drives KDE Connect through `kdeconnect-cli`: it lists phones,
pairs a nearby one, sends files (`--share`), opens the phone in Files
(`kdeconnect://<id>/`), sends a text message (`--send-sms`), opens KDE
Connect's Messages, rings the phone and unpairs it. KDE Connect itself shares
notifications (Android) and the clipboard; More options opens
`kcm_kdeconnect`. KDE Connect is no longer in the excluded packages.

### PIN

Settings > Account > PIN sets a PIN of 6 to 12 digits for the lock screen.
`kernora-pin` (kernora-apps, setuid root, `src/pin/pin.c`) keeps a yescrypt
hash in `/var/lib/kernora/pin/<uid>` and the wrong tries in
`/var/lib/kernora/pin/<uid>.state`, root only, in a 0711 directory so that
Settings can see whether a PIN is set:

- `kernora-pin set` and `remove` run through pkexec
  (`org.kernora.pin.manage`, `auth_self`) and act on `PKEXEC_UID`, so setting
  a PIN takes the user's password;
- `kernora-pin check` runs from `pam_exec` with `expose_authtok`, placed before
  `pam_unix` by the pam-auth-update profile `kernora-pin`. It accepts only the
  `kde` and `kde-fingerprint` services (the lock screen) and only the caller's
  own account. A PIN that matches signs in; anything else falls through to the
  password with `try_first_pass`. SDDM, sudo and polkit never take the PIN, so
  after a restart the password comes first;
- after 5 wrong PINs in a row the PIN is refused for a minute, after 7 for
  five minutes, after 9 for half an hour, and the tenth removes it. A right PIN
  clears the count.

The lock screen's field reads Password or PIN.
