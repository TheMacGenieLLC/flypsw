# flypsw Release History

Full release history from initial development through the current build.
For context on current features, see [USER_GUIDE.md](USER_GUIDE.md).

---

### Build 101 — 2026-07-19

- **Firmware information now comes directly from Apple.** flypsw reads Apple's
  own firmware catalog (the version manifest at `itunes.apple.com` that iTunes
  queried before restoring a device), replacing the third-party ipsw.me catalog
  used in Build 100. This restores the direct-from-Apple sourcing of flypsw's
  earliest versions: the catalog, the download URLs, and the verification
  hashes all come from Apple, with no third-party service in the middle.
- **One catalog download replaces per-device lookups.** The catalog arrives as
  a single download of a few megabytes covering every device, so gathering
  firmware information no longer needs one query per device — large selections
  are ready as soon as the catalog lands.
- **Verification now uses Apple's published SHA1 hashes** (the catalog's hash
  format) in place of ipsw.me's SHA256. Freshly downloaded files are still
  always fully verified, and the handful of the oldest firmware without a
  published hash still gets the archive-completeness check.
- **Fast verification mode now checks archive structure.** Apple's catalog does
  not publish file sizes, so the Fast re-check of existing files confirms each
  file's zip archive reads back complete instead of comparing sizes — still
  quick, and it catches truncation the same way.
- **The free-space check asks Apple's servers for file sizes** (several at a
  time) before a run begins, since sizes are no longer in the catalog.
- **Download URLs are used exactly as Apple publishes them.** Some older
  firmware lives on Apple hosts that only answer over plain `http`; upgrading
  those addresses to `https` breaks them, so flypsw no longer rewrites URLs and
  relies on hash verification for integrity.
- **Shared firmware is downloaded once.** Apple ships a single IPSW for many
  closely related models — a dozen iPad identifiers can share one file — and
  flypsw now queues each distinct file once instead of once per model. On a
  full-catalog run this avoids re-downloading well over a hundred gigabytes.
  (The Build 100 catalog shared files the same way, so this corrects an
  inherited inefficiency as well.)
- **Downloads are staged and renamed only after verification.** Files download
  under a temporary working name and enter the library only once verified, so
  the library never contains an unverified file. A partial file left by an
  interrupted run is resumed by the next run instead of restarted, and a
  staged file that turns out to be complete is verified and kept without
  re-downloading.
- **Free-space size lookups now show progress** as they're dispatched, instead
  of a silent pause while Apple's servers are queried for file sizes.
- **A corrupt or unreadable firmware catalog is now reported distinctly** from
  a selection that legitimately matches no devices, so a bad download and an
  empty result no longer look the same.
- **Firmware entries are now required to name a `.ipsw` file** before flypsw
  will queue them, so an unexpected shape in Apple's catalog can't produce a
  malformed download.
- **Apple Watch support removed.** Watch firmware was only ever available
  through the third-party catalog — it has never appeared in Apple's own — so
  the Apple Watch menu option and destination subfolder are gone. The former
  "all supported devices" option is now "all devices in Apple's catalog."
- Entries listed with the retired protected-download address (a few of the
  oldest paid iPod touch upgrades) are skipped in favor of the newest firmware
  that can actually be fetched.

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
