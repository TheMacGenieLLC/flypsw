# flypsw User Guide

**Version:** Build 100  
**Updated:** 2026-06-27  
**Author:** Ian Williams  
**Contact:** [ian@themacgenie.com](ian@themacgenie.com)  
**Project:** [https://github.com/TheMacGenie/flypsw](https://github.com/TheMacGenie/flypsw)

---

## Contents

- [Introduction](#introduction)
- [Hardware & Software Requirements](#hardware--software-requirements)
- [Quick Start](#quick-start)
- [The Main Menu](#the-main-menu)
- [Selecting Device Types](#selecting-device-types)
- [Choosing a Destination](#choosing-a-destination)
- [How Downloading Works](#how-downloading-works)
- [Verification & Self-Healing](#verification--self-healing)
- [The Firmware Catalog](#the-firmware-catalog)
- [Pushover Notifications](#pushover-notifications)
- [Single-Instance Protection](#single-instance-protection)
- [Security Considerations](#security-considerations)
- [Changelog](#changelog)
- [Future Plans](#future-plans)
- [Formalities and Colophon](#formalities-and-colophon)

---

## Introduction

flypsw automates the download and verification of Apple device firmware — the
**IPSW** files used to restore or update iPhone, iPad, iPod touch, Apple TV, and
Apple Watch. Instead of hunting for direct links, copying URLs, and manually
checking that each download came through intact, flypsw looks up the latest
firmware for every device you select, downloads anything you don't already have,
and verifies each file against its published hash — all in a single pass.

Point flypsw at a destination folder and it builds and maintains an organized,
ready-to-restore firmware library. Run it again later and it downloads only
what's new or missing, leaving verified files in place. This makes it easy to
keep a deployment or repair library current, whether that's a single device
family or the entire Apple lineup.

> **Note:** flypsw runs entirely as your user. It downloads firmware into your
> user folders, does not erase or modify any disks, and requires no administrator
> privileges — optional Pushover credentials are stored in your own login
> keychain.

---

## Hardware & Software Requirements

**Host (the Mac that runs flypsw):**

- A reasonably current version of macOS. flypsw runs on both Apple Silicon and
  Intel Macs.
- The **Xcode Command Line Tools.** flypsw parses the firmware catalog (which is
  distributed as JSON) with `python3`, which is included in the tools. If they
  are not present, flypsw offers to install them at launch and then exits so
  installation can complete.
- An **internet connection** for the catalog lookups and the downloads
  themselves.

**Storage:**

- Enough free space at the destination for the firmware you intend to keep. IPSW
  files are large — often several gigabytes each — and selecting many device
  families can add up quickly. A drive with plenty of headroom keeps a library
  useful as new releases ship.
- A fast connection and disk make a meaningful difference when downloading and
  verifying large numbers of files.

---

## Quick Start

flypsw is a single self-contained script — there are no companion files to keep
alongside it. Place `flypsw.command` anywhere convenient (the Desktop works
well) and double-click it to launch it in Terminal.

The first thing flypsw does is verify that the Xcode Command Line Tools are
present. If they're missing, it offers to install them (`xcode-select --install`)
and exits so installation can complete; run flypsw again once it's done.

With the tools in place, flypsw shows a welcome screen describing what it does.
Press **Y** to continue or any other key to exit. From there:

1. Choose **1 — Download latest IPSW files** from the Main Menu.
2. Select which **device types** to check (see
   [Selecting Device Types](#selecting-device-types)).
3. Choose a **destination folder** (see
   [Choosing a Destination](#choosing-a-destination)).
4. flypsw looks up the latest firmware, compares it against what's already on
   disk, and shows how many files it needs to download before it begins.

Once downloading starts, no further input is needed. flypsw works through the
queue, verifying each file as it finishes, and returns you to the Main Menu when
it's done.

---

## The Main Menu

```
flypsw Main Menu

1. Download latest IPSW files

2. Configure Pushover notifications

3. Verification mode: Fast (size check of existing files)

X. Exit flypsw
```

- **1 — Download latest IPSW files.** The main workflow: choose device types and
  a destination, then let flypsw look up, download, and verify the latest
  firmware. This is where nearly all of your time is spent.
- **2 — Configure Pushover notifications.** Optional push notifications for
  download progress and completion. See
  [Pushover Notifications](#pushover-notifications).
- **3 — Verification mode.** Toggles how flypsw re-checks files that are already
  in the destination, between **Fast** and **Thorough**. The label shows the
  current mode. See [Verification & Self-Healing](#verification--self-healing).
- **X — Exit flypsw.** Quits and cleans up temporary files.

---

## Selecting Device Types

After choosing to download, flypsw asks which device families to check for new
firmware:

```
Select the device types to check for new firmware:

1. iPhone, iPad, iPod touch, and Apple TV
   (The classic iOS device set)

2. iPhone only

3. iPad only
   (Includes iPad mini, iPad Air, and iPad Pro)

4. iPod touch only

5. Apple TV only

6. iPhone and iPad

7. iPhone, iPad, and iPod touch

8. Apple Watch only

9. All supported devices
   (iPhone, iPad, iPod, Apple TV, Watch, and more)

X. Return to main menu
```

Narrowing the selection to the families you actually support keeps catalog
lookups and downloads quick. Choosing **9 — All supported devices** is the most
thorough option but checks the largest number of models and can take several
minutes just to gather firmware information before any download begins.

---

## Choosing a Destination

Next, flypsw asks where downloaded firmware should be saved:

```
Choose a destination folder for downloaded IPSW files:

1. Downloads folder
   (~/Downloads/IPSW Files)

2. Desktop
   (~/Desktop/IPSW Files)

3. iTunes library folder
   (~/Library/iTunes)

X. Return to main menu
```

If the destination folder structure doesn't already exist, flypsw creates it.
Within the destination, files are organized into per-device-type subfolders:

```
IPSW Files/
├── iPhone Software Updates/
├── iPad Software Updates/
├── iPod Software Updates/
├── Apple TV Software Updates/
├── Apple Watch Software Updates/
└── Other Software Updates/
```

Files whose names don't match a known device family are filed under **Other
Software Updates** so nothing is lost.

Pointing successive runs at the same destination is the intended workflow:
flypsw checks what's already there before downloading, so re-running it keeps the
library current without re-fetching files you already have.

---

## How Downloading Works

Once you've chosen device types and a destination, flypsw runs the full workflow
on its own:

1. **Catalog download.** flypsw fetches the current device list from the firmware
   catalog (see [The Firmware Catalog](#the-firmware-catalog)).
2. **Device filtering.** The list is narrowed to the device families you
   selected.
3. **Firmware lookup.** For each device, flypsw retrieves the latest *signed*
   IPSW's filename, download URL, published SHA256 hash, and size. These lookups
   run several at a time (in parallel), so even a large selection completes in a
   fraction of the time a one-at-a-time pass would take.
4. **Destination check.** flypsw compares the latest firmware against what's
   already in the destination and builds a queue of only the files that are
   missing, out of date, or failed verification (see
   [Verification & Self-Healing](#verification--self-healing)).
5. **Confirmation.** flypsw reports how many files it needs to download, warns if
   the destination volume may not have room for them, and waits for you to begin
   (or press Ctrl-C to cancel). If everything is already present and verified, it
   tells you there's nothing to do and returns to the menu.
6. **Download & verify.** Each queued file is downloaded with a progress bar and
   verified as it completes. A download interrupted by a transient network drop
   resumes from where it left off rather than starting over. When the run
   finishes, flypsw reports how many files succeeded and how many (if any) failed.

If any downloads fail, flypsw removes the incomplete files and suggests running
it again — a subsequent run simply re-queues whatever is still missing.

> **Why signed firmware?** Apple "signs" the firmware versions it currently
> allows devices to be restored to. An unsigned (older) IPSW generally cannot be
> installed, so flypsw selects the newest signed build for each device rather
> than the newest build overall.

---

## Verification & Self-Healing

flypsw is built to be run repeatedly against the same library and to leave it in
a known-good state.

**Freshly downloaded files are always fully verified**, no matter which
verification mode is set:

- **Hash verification.** When the catalog publishes a SHA256 hash, flypsw checks
  every download against it. A file that doesn't match is deleted immediately so
  it can be re-fetched cleanly.
- **Integrity check without a hash.** When the catalog provides no hash, flypsw
  instead confirms the download is a structurally complete archive (IPSW files
  are zip archives). A partial or truncated download fails this check — because
  the archive's directory at the end of the file is missing — and is removed.

**Files already in the destination** are re-checked according to the
**verification mode** (Main Menu option 3):

- **Fast (default).** flypsw trusts an existing file whose size matches the
  catalog's reported size, and only re-downloads when the size differs (which is
  what a truncated or wrong file looks like). When the catalog didn't report a
  size, flypsw falls back to the quick archive-completeness check. This keeps
  repeat runs fast even on a large library, because it avoids re-reading every
  multi-gigabyte file end to end.
- **Thorough.** flypsw re-hashes every existing file in full (or, lacking a hash,
  re-checks the whole archive). This is much slower on a large library but also
  catches *silent corruption* — a file whose size is unchanged but whose contents
  have rotted — which the fast check cannot see.

Other safeguards apply in both modes:

- **Resume on transient drops.** Within a download, a brief network interruption
  is retried automatically and the transfer resumes from where it stopped rather
  than restarting the whole file (this relies on Apple's servers supporting
  resumable downloads, which they do).
- **Clean failures.** A failed or unverifiable download is always removed rather
  than left in place, so a later run never mistakes a broken file for a good one.

The practical result: you can interrupt flypsw, lose your connection mid-file, or
simply run it on a schedule, and the next run will repair and complete the
library without manual cleanup. For unattended/scheduled runs, Fast mode keeps
each pass quick; switch to Thorough when you want a deep re-verification.

> **Integrity vs. authenticity.** The SHA256 check confirms a file matches the
> hash the catalog published, which reliably catches a corrupted or truncated
> download. Because the hash and the download URL come from the same catalog, it
> is not a guarantee of authenticity against a compromised catalog — Apple's
> firmware signing, enforced by the device at restore time, is what ultimately
> governs whether an IPSW can be installed.

---

## The Firmware Catalog

flypsw looks up device and firmware information from **[ipsw.me](https://ipsw.me)**
(`api.ipsw.me`), a third-party service that indexes Apple's IPSW releases and
returns their download URLs on Apple's content-delivery network. flypsw is an
independent tool and is not affiliated with ipsw.me; the service's availability
and any rate limits are outside flypsw's control.

flypsw queries the catalog in two stages — once for the full device list, and
then once per selected device for that device's firmware (these per-device
lookups run several at a time). The IPSW files themselves are downloaded directly
from Apple's content-delivery network using the URLs the catalog provides.

Network failures during lookups are handled gracefully: if the device list can't
be downloaded, flypsw reports the problem and returns to the menu without making
changes; if an individual device lookup fails, flypsw skips that device and
continues with the rest.

---

## Pushover Notifications

flypsw can send push notifications (via [Pushover](https://pushover.net)) as
downloads progress and when a run finishes, so you don't have to watch the
screen during a long session. You'll receive a message as each file is
downloaded and verified, a final summary, and a notice for any file that fails.

Configure it from Main Menu option 2:

- **Configure or update credentials** — enter your Pushover user key and
  application (API) token. They are stored in your **login keychain**, not in any
  plain-text file, and are written without ever appearing on a command line.
- **Send a test notification** — confirms your credentials work.
- **Remove credentials** — deletes the stored keys from the keychain; flypsw
  stops sending notifications.

Pushover is entirely optional. If no credentials are configured, flypsw simply
doesn't send notifications, and the download workflow is unaffected.

---

## Single-Instance Protection

Only one copy of flypsw can run at a time. On launch, flypsw writes its process
ID to a per-user lockfile; if you try to start a second copy while one is already
running, flypsw tells you and exits. The lock is self-healing — if a previous run
crashed without cleaning up, flypsw detects the stale lockfile (its process is no
longer alive) and removes it automatically, so a crash never leaves you locked
out. Because the lockfile is per-user, separate user accounts on the same Mac
never block one another.

The lockfile and any temporary catalog files are removed automatically when
flypsw exits, including when you interrupt it with Ctrl-C.

---

## Security Considerations

flypsw runs entirely as your user and does not erase disks or modify the system.
Because it is an open shell script, its behavior can be readily audited against
your security policy.

flypsw makes network connections in two situations:

1. **Firmware lookups and downloads.** flypsw contacts the ipsw.me catalog to
   determine the latest firmware for your selected devices, then downloads the
   IPSW files from Apple's content-delivery network. Every download for which a
   hash is published is verified against that hash before being kept. As noted in
   [Verification & Self-Healing](#verification--self-healing), this proves
   integrity against corruption, not authenticity against a compromised catalog;
   Apple's firmware signing governs whether a file can actually be restored. flypsw
   prefers `https` download URLs.
2. **Pushover notifications.** Only if you configure them (Main Menu option 2),
   and only to send the notifications you requested.

Pushover credentials, if configured, are stored in your **login keychain** rather
than in any file on disk. flypsw writes, reads, and deletes them with the macOS
`security` tool, and is careful never to place the secret values on a command
line where other local users could observe them. The login keychain scopes the
credentials to your user account; no administrator authorization is required.

---

## Changelog

### Build 100 — 2026-06-27 (first public release)

- Initial public release of flypsw as a standalone IPSW firmware download and
  verification tool.
- **Device-family selection** for iPhone, iPad, iPod touch, Apple TV, and Apple
  Watch — individually, in common combinations, or all supported devices at once.
- **Firmware lookup** against the ipsw.me catalog, retrieving filename, download
  URL, SHA256 hash, and size for each selected device, and **preferring the
  latest signed build** (the version Apple still allows for restore), chosen
  independently of the order the catalog returns entries in.
- **Parallel catalog lookups** (bounded concurrency) so large selections gather
  firmware information quickly.
- **One-pass library updates** that download only what's missing or out of date
  and skip files already present and verified.
- **Full verification of every download** — SHA256 when the catalog publishes a
  hash, and an archive-completeness check when it doesn't — with automatic
  removal and re-queueing of files that fail.
- **Selectable re-check mode** for existing files: **Fast** (size match, the
  default) for quick repeat runs, or **Thorough** (full re-hash) to catch silent
  corruption, toggled from the Main Menu.
- **Resumable downloads** that ride out transient network drops instead of
  restarting a file from the beginning.
- **Free-space check** that warns before a large run if the destination volume
  may not have room.
- **Organized output** into per-device-type subfolders (routed by device
  identifier), with destination choices of Downloads, Desktop, or the iTunes
  library.
- **Pushover notifications** for per-file progress, completion, and failures,
  with credentials stored in your login keychain, validated on entry, never
  exposed on a command line, and read from the keychain only once per run.
- **Per-user, single-instance lockfile** with automatic stale-lock recovery and
  cleanup on exit, including on Ctrl-C.
- **Xcode Command Line Tools check** at launch, offering to install them
  (`xcode-select --install`) if they're missing.
- **Graceful network handling** so failed lookups or downloads leave the library
  in a clean state and can be retried by running flypsw again.

---

## Future Plans

- **A graphical interface.** A native GUI is desired but not a current priority;
  flypsw ships as a Terminal script for now.
- **Custom destination paths.** Allowing an arbitrary destination folder in
  addition to the built-in Downloads, Desktop, and iTunes choices.
- **Retaining older firmware.** Optionally keeping previous IPSW versions
  alongside the latest, rather than tracking only the most recent release.
- **Scheduled runs.** Guidance and helpers for running flypsw unattended on a
  schedule to keep a library current automatically.