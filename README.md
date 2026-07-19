# flypsw

**Keep a local library of the latest Apple device IPSW firmware, downloaded and verified automatically.**

flypsw is a single Bash script that automates the tedious parts of collecting
Apple device firmware: it looks up the latest IPSW for every device you care
about, downloads anything you don't already have, and verifies each file against
the SHA1 hash Apple publishes. Point it at a destination folder, choose which
device families to track — iPhone, iPad, iPod touch, Apple TV, or everything —
and flypsw builds and maintains an organized, ready-to-restore firmware library
in one pass.

> **Note:** flypsw is meant to keep an existing library current. Run it on a
> schedule or whenever new releases ship and it downloads only what's new or
> missing, leaving verified files in place.

<a href="https://www.buymeacoffee.com/themacgenie"><img width="214" height="60" src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee"></a>
---
## Features

- **One-pass library updates** — looks up the latest IPSW for each selected
  device, downloads only what's missing or out of date, and skips everything
  already present and verified.
- **Device-family selection** — track iPhone, iPad, iPod touch, or Apple TV
  individually, in common combinations, or every device in Apple's catalog at
  once.
- **Sourced directly from Apple** — firmware information comes from Apple's own
  catalog, and for each device flypsw takes the newest firmware Apple currently
  posts (the build Apple will still let you restore on supported devices).
- **Integrity verification** — every freshly downloaded file is fully verified
  against the SHA1 hash Apple publishes (or, when none is published, by
  confirming the archive is complete); files that fail are removed so a retry
  re-fetches a clean copy.
- **Fast or thorough re-checks** — a menu toggle controls how already-present
  files are re-checked on each run: **Fast** (default) confirms each file's
  archive structure reads back complete, keeping repeat runs quick on a large
  library; **Thorough** re-hashes every file in full to catch silent corruption.
- **Self-healing downloads** — downloads are staged under a working name and
  renamed into the library only after verification, so the library never holds
  an unverified file. Transfers resume rather than restart after a transient
  network drop, and a partial file left by an interrupted run is resumed by the
  next run instead of starting over.
- **Shared firmware fetched once** — Apple ships a single IPSW for many closely
  related models (a dozen iPad identifiers can share one file); flypsw
  downloads each distinct file once rather than once per model.
- **One catalog download covers everything** — a single fetch of Apple's
  catalog carries firmware information for every device, so even an "all
  devices" run needs no per-device queries.
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

flypsw looks up firmware information from **Apple's own firmware catalog** — the
version manifest at `itunes.apple.com` that iTunes queried before restoring a
device. It carries the restore URL and SHA1 hash for every iPhone, iPad, iPod
touch, and Apple TV firmware Apple has posted, and Apple keeps it current as new
releases ship. No third-party service sits in the middle: the catalog, the
downloads, and the hashes all come from Apple. The SHA1 check protects downloads
against corruption in transit; Apple's own firmware signing is what governs
whether an IPSW can actually be restored to a device. Apple Watch firmware does
not appear in this catalog (watches were never restored through iTunes), so
flypsw does not track it.

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

3. Verification mode: Fast (archive check of existing files)

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
