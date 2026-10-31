# Live and installer language

The Live GRUB menu uses stable identifiers: `live-en`, `live-ru` and
`live-safe`. English is the first Live entry and the default. Russian stays
available by explicit selection. Safe graphics also selects English. If the
ISO finds an installed Lumo system, the existing `installed` entry still
takes boot priority.

The existing Live language service applies the chosen kernel argument before
login, including the system locale and Plasma translation settings. Both
English and Russian locales are generated in the image.

Calamares's welcome language selector already translated the interface. The
location page's language selector only changed the target system language.
The derived `calamares` package now also selects the application translator
there. The welcome selector follows that choice when returning to it, and
changing language there again updates a previously explicit target language.
Explicit regional formats remain independent. Region and timezone models
notify their views after a language change, and the custom city list refreshes
and sorts its translated names. The view-step model also refreshes sidebar
labels when the translator changes.

The full selected target locale is retained even when Calamares uses a more
general available translation, for example `ru_RU.UTF-8` with the `ru`
translation. Missing translations fall back according to Calamares's normal
translation loader; this change does not add new translations.

Packages:

- `calamares 3.3.14-1lumo2`: language integration and translated models.
- `lumo-desktop` and `lumo-calamares 1.4.28`: configuration dependency
  and translated city-list refresh.
- `lumo-apps 1.1.35`: What's New, entry `2026-10-13-8`, dated 13 October
  2026, in English and Russian.

In Lumo the same change ships as `lumo-desktop` / `lumo-calamares` 1.4.31
and `lumo-apps` 1.1.39, What's New entry `2026-10-14-2` in English, Dutch
and Russian. The Lumo boot menu has the ids `live-en`, `live-nl`, `live-ru` and
`live-safe`; English stays the default.

The old Calamares package failed the actual installer regression at the
location-page language change. The new packages passed English → Russian →
German → English switching, a Russian choice on the location page, hidden
welcome-page synchronization and back navigation, translated city names,
sidebar labels, and the final target `LANG` with independently preserved
`LC_*` formats. The sidebar regression also failed before the model
notification was added and passed with the completed patch.
The test loads native Calamares modules with temporary branding and has no
installation jobs. See [the test instructions](../tests/installer-language/README.md).

Native source and binary checks, `make verify`, local archive checks and
Live rootfs checks passed. The Live rootfs's Calamares core, UI library and
locale module were compared byte-for-byte with the final tested binary package. Test logs
and boot screenshots belong in `out/test-logs/installer-language/`.

The Live default is part of the ISO boot menu. Updating an already installed
system does not replace an older USB image; use the updated ISO to get the
English default on that medium.
The final ISO passed static checks and QEMU/KVM BIOS and UEFI boot tests.
A default boot reached Plasma with `LANG=en_US.UTF-8` and English translation
settings. Selecting the second GRUB entry reached Plasma with
`LANG=ru_RU.UTF-8` and Russian translation settings. Both sessions contained
the package versions listed above. Installation to disk was not repeated
for this language change.

ISO SHA256:
`bf90195b5c07de1a4e932105915dba55278426cc9538a0874e40c4e859e53bec`.
