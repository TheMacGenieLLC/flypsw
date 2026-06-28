# flypsw

**Keep a local library of the latest Apple device IPSW firmware, downloaded and verified automatically.**

flypsw is a single Bash script that automates the tedious parts of collecting
Apple device firmware: it looks up the latest IPSW for every device you care
about, downloads anything you don't already have, and verifies each file against
its published SHA256 hash. Point it at a destination folder, choose which device
families to track — iPhone, iPad, iPod touch, Apple TV, Apple Watch, or
everything — and flypsw builds and maintains an organized, ready-to-restore
firmware library in one pass.

> **Note:** flypsw is meant to keep an existing library current. Run it on a
> schedule or whenever new releases ship and it downloads only what's new or
> missing, leaving verified files in place.

<a href="https://www.buymeacoffee.com/themacgenie"><img width="214" height="60" src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee"></a>
---
## Features

- **One-pass library updates** — looks up the latest IPSW for each selected
  device, downloads only what's missing or out of date, and skips everything
  already present and verified.
- **Device-family selection** — track iPhone, iPad, iPod touch, Apple TV, or
  Apple Watch individually, in common combinations, or all supported devices at
  once.
- **Signed firmware preferred** — for each device flypsw chooses the latest
  *signed* release (the build Apple will still let you restore) rather than
  blindly taking the newest entry.
- **Integrity verification** — every freshly downloaded file is fully verified
  against the catalog's published SHA256 hash (or, when none is published, by
  confirming the archive is complete); files that fail are removed so a retry
  re-fetches a clean copy.
- **Fast or thorough re-checks** — a menu toggle controls how already-present
  files are re-checked on each run: **Fast** (default) trusts a file whose size
  matches the catalog, keeping repeat runs quick on a large library; **Thorough**
  re-hashes every file in full to catch silent corruption.
- **Self-healing downloads** — existing files are re-verified on each run, and
  partial or corrupt files (including interrupted downloads with no published
  hash) are detected and re-downloaded. Transfers resume rather than restart
  after a transient network drop.
- **Parallel catalog lookups** — firmware information for many devices is
  gathered concurrently, so even an "all devices" run stays reasonably quick.
- **Organized output** — firmware is filed into per-device-type subfolders inside
  the destination you choose, with a free-space check before large runs.
- **Optional Pushover notifications** for per-file progress and a final summary,
  so long download runs don't need watching.
- **Single-instance safety** — a per-user, self-healing lockfile prevents two
  copies of flypsw from running at once.

## Requirements

- A reasonably current version of macOS, on Apple Silicon or Intel.
- The **Xcode Command Line Tools** (for `python3`, used to parse the firmware
  catalog). flypsw checks for them at launch and offers to install them if
  they're missing.
- An internet connection. Optional Pushover credentials are stored in your
  **login keychain**.

## Firmware Catalog

flypsw looks up firmware information from **[ipsw.me](https://ipsw.me)**
(`api.ipsw.me`), a third-party service that indexes Apple's IPSW releases and
their download URLs on Apple's content-delivery network. flypsw is not affiliated
with ipsw.me; the service's availability and any rate limits are outside flypsw's
control. The SHA256 check protects downloads against corruption in transit — note
that the hash and the URL both come from the same catalog, so verification proves
integrity, not authenticity. Apple's own firmware signing is what governs whether
an IPSW can actually be restored to a device.

## Getting Started

1. Place `flypsw.command` anywhere convenient (the Desktop works well).
2. Double-click `flypsw.command` to launch it in Terminal.
3. Read the welcome screen and press **Y** to continue.
4. From the Main Menu, choose **1** to download firmware, pick the device types
   and a destination folder, and flypsw does the rest:

```
flypsw Main Menu

1. Download latest IPSW files

2. Configure Pushover notifications

3. Verification mode: Fast (size check of existing files)

X. Exit flypsw
```

flypsw creates the destination folder structure for you if it doesn't already
exist.

## Where Files Go

flypsw saves IPSW files into per-device-type subfolders inside the destination
you select (Downloads, Desktop, or your iTunes library):

```
IPSW Files/
├── iPhone Software Updates/
├── iPad Software Updates/
├── iPod Software Updates/
├── Apple TV Software Updates/
├── Apple Watch Software Updates/
└── Other Software Updates/
```

Because flypsw verifies what's already on disk before downloading, you can point
successive runs at the same destination to keep the library current without
re-downloading files you already have.

## Documentation

The full manual, including the menu walkthrough, verification details, and the
complete changelog, is in **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**.

## License

Released under the [MIT License](LICENSE). © 2013–2026 The Mac Genie LLC.

## Author

Created by Ian Williams — ian@themacgenie.com
