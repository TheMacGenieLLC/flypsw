# flypsw User Guide

**Version:** Build 101  
**Updated:** 2026-07-19  
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
- [Release History](#release-history)

---

## Introduction

flypsw automates the download and verification of Apple device firmware — the
**IPSW** files used to restore or update iPhone, iPad, iPod touch, and Apple TV.
Instead of hunting for direct links, copying URLs, and manually checking that
each download came through intact, flypsw reads Apple's own firmware catalog,
downloads anything you don't already have, and verifies each file against the
hash Apple publishes — all in a single pass.

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
- The **Xcode Command Line Tools.** flypsw parses Apple's firmware catalog
  (which is distributed as an XML property list) with `python3`, which is
  included in the tools. If they are not present, flypsw offers to install them
  at launch and then exits so installation can complete.
- An **internet connection** for the catalog download and the downloads
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

3. Verification mode: Fast (archive check of existing files)

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

8. All devices in Apple's catalog
   (iPhone, iPad, iPod, Apple TV, plus anything else Apple lists)

X. Return to main menu
```

Because Apple's catalog arrives in a single download, gathering firmware
information takes about the same time no matter how many families you select —
the selection mainly controls how many files end up in your library. Choosing
**8 — All devices in Apple's catalog** is the most thorough option and also
picks up the occasional device outside the four main families (such as the
original HomePod), which is filed under **Other Software Updates**.

Apple Watch firmware does not appear in Apple's catalog — watches were never
restored through iTunes — so flypsw does not offer it.

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
└── Other Software Updates/
```

Firmware for devices outside the four main families is filed under **Other
Software Updates** so nothing is lost.

Pointing successive runs at the same destination is the intended workflow:
flypsw checks what's already there before downloading, so re-running it keeps the
library current without re-fetching files you already have.

---

## How Downloading Works

Once you've chosen device types and a destination, flypsw runs the full workflow
on its own:

1. **Catalog download.** flypsw fetches Apple's firmware catalog — a single
   download of a few megabytes that covers every device (see
   [The Firmware Catalog](#the-firmware-catalog)).
2. **Device filtering.** The catalog's device list is narrowed to the families
   you selected.
3. **Firmware lookup.** For each device, flypsw picks out the newest IPSW Apple
   posts — its filename, download URL, and published SHA1 hash. Because the
   whole catalog is already on disk, this step needs no further network access.
   Apple often ships one IPSW for many closely related models (a dozen iPad
   identifiers can share a single file), and flypsw queues each distinct file
   only once.
4. **Destination check.** flypsw compares the latest firmware against what's
   already in the destination and builds a queue of only the files that are
   missing, out of date, or failed verification (see
   [Verification & Self-Healing](#verification--self-healing)).
5. **Confirmation.** flypsw reports how many files it needs to download, checks
   their sizes against the destination volume's free space (warning if it may
   not have room), and waits for you to begin (or press Ctrl-C to cancel). If
   everything is already present and verified, it tells you there's nothing to
   do and returns to the menu.
6. **Download & verify.** Each queued file is downloaded with a progress bar
   under a temporary working name, verified as it completes, and only then
   renamed into the library. A download interrupted by a transient network drop
   resumes from where it left off rather than starting over — and if a run is
   interrupted outright, the next run picks the partial file back up instead of
   starting from scratch. When the run finishes, flypsw reports how many files
   succeeded and how many (if any) failed.

If any downloads fail, flypsw removes the incomplete files and suggests running
it again — a subsequent run simply re-queues whatever is still missing.

> **Which firmware gets picked?** Apple keeps its catalog updated as releases
> ship, so for a device Apple still supports, the newest entry is the version
> Apple currently signs — the build you can actually restore. For devices Apple
> no longer updates, the newest entry is the final firmware ever posted, which
> is exactly what a repair or preservation library wants on hand.

---

## Verification & Self-Healing

flypsw is built to be run repeatedly against the same library and to leave it in
a known-good state.

**Freshly downloaded files are always fully verified**, no matter which
verification mode is set:

- **Hash verification.** When the catalog publishes a SHA1 hash, flypsw checks
  every download against it. A file that doesn't match is deleted immediately so
  it can be re-fetched cleanly.
- **Integrity check without a hash.** When the catalog provides no hash (true of
  a handful of the oldest firmware), flypsw instead confirms the download is a
  structurally complete archive (IPSW files are zip archives). A partial or
  truncated download fails this check — because the archive's directory at the
  end of the file is missing — and is removed.

**Files already in the destination** are re-checked according to the
**verification mode** (Main Menu option 3):

- **Fast (default).** flypsw confirms each existing file's archive structure
  reads back complete — the same check described above, which catches the
  common failure (a truncated file) by reading only the archive's directory.
  This keeps repeat runs fast even on a large library, because it avoids
  re-reading every multi-gigabyte file end to end.
- **Thorough.** flypsw re-hashes every existing file in full (or, lacking a hash,
  re-checks the whole archive). This is much slower on a large library but also
  catches *silent corruption* — a file whose size is unchanged but whose contents
  have rotted — which the fast check cannot see.

Other safeguards apply in both modes:

- **Staged downloads.** Files download under a temporary working name and are
  renamed into the library only after passing verification, so the library
  itself never contains an unverified file — even if flypsw is interrupted
  mid-download or mid-verification.
- **Resume on transient drops and across runs.** Within a download, a brief
  network interruption is retried automatically and the transfer resumes from
  where it stopped rather than restarting the whole file (this relies on
  Apple's servers supporting resumable downloads, which they do). If a run is
  interrupted outright, the partial working file is kept, and the next run
  resumes it from where it stopped. A working file that turns out to be
  complete already — say, flypsw was interrupted during verification — is
  verified and kept without re-downloading anything.
- **Clean failures.** A download whose content fails verification is always
  removed rather than left in place, so a later run never mistakes a broken
  file for a good one, and nothing corrupt is ever resumed.

The practical result: you can interrupt flypsw, lose your connection mid-file, or
simply run it on a schedule, and the next run will repair and complete the
library without manual cleanup. For unattended/scheduled runs, Fast mode keeps
each pass quick; switch to Thorough when you want a deep re-verification.

> **Integrity vs. authenticity.** The SHA1 check confirms a file matches the
> hash Apple's catalog published, which reliably catches a corrupted or
> truncated download — including for older firmware that Apple still serves
> over plain http. The catalog itself is fetched from Apple over https, and
> Apple's firmware signing, enforced by the device at restore time, is what
> ultimately governs whether an IPSW can be installed.

---

## The Firmware Catalog

flypsw looks up device and firmware information from **Apple's own firmware
catalog** — the version manifest at `itunes.apple.com` that iTunes queried
before restoring a device. Apple still keeps it current as new releases ship,
and it reaches back to the very first iPhone, iPod touch, and Apple TV
firmware, so one source covers both this week's release and a restore for a
device from 2007. No third-party service sits in the middle: the catalog, the
download URLs, and the hashes all come from Apple.

The catalog arrives in a single download of a few megabytes. flypsw reads the
device list and the firmware details out of that one local copy, so after the
initial fetch, gathering firmware information for any number of devices needs
no further network access. The IPSW files themselves are downloaded directly
from Apple's content-delivery network using the URLs the catalog provides.

Two quirks of the catalog are worth knowing about. First, Apple Watch firmware
is not in it — watches were never restored through iTunes — so flypsw does not
track it. Second, a few of the oldest paid iPod touch upgrades are listed with
a special protected address whose download server Apple shut down years ago;
flypsw skips those entries and offers the newest firmware that can actually be
fetched (for the original iPod touch, that is the last free release rather than
the paid upgrade).

Network failures are handled gracefully: if the catalog can't be downloaded,
flypsw reports the problem and returns to the menu without making changes.

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

1. **Firmware lookups and downloads.** flypsw fetches Apple's firmware catalog
   over `https`, then downloads the IPSW files from Apple's content-delivery
   network using the URLs exactly as the catalog publishes them. Some older
   firmware is served from Apple hosts that only answer over plain `http`;
   every such download is verified against the SHA1 hash from the
   https-delivered catalog before being kept. As noted in
   [Verification & Self-Healing](#verification--self-healing), the hash check
   proves integrity against corruption; Apple's firmware signing governs
   whether a file can actually be restored.
2. **Pushover notifications.** Only if you configure them (Main Menu option 2),
   and only to send the notifications you requested.

Pushover credentials, if configured, are stored in your **login keychain** rather
than in any file on disk. flypsw writes, reads, and deletes them with the macOS
`security` tool, and is careful never to place the secret values on a command
line where other local users could observe them. The login keychain scopes the
credentials to your user account; no administrator authorization is required.

---

## Release History

The complete release history, from the current build back to flypsw's origins
in 2013, lives in [RELEASE_HISTORY.md](RELEASE_HISTORY.md).
