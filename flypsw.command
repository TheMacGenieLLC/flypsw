#!/bin/bash

# flypsw.command
#
# Created by:
# Ian Williams, The Mac Genie LLC
# ian@themacgenie.com
#
# https://github.com/TheMacGenie/flypsw
#
# Current script version:
currentVersion="2026-06-27 - 01 - Build 100"

# Global Variable Declarations
destinationFolder=""
deviceTypeSelection=""
downloadFailureCount=0
okToRun="N"

# Bold/reset escape sequences for menu emphasis. tput falls back to empty
# strings when no terminal is attached, so output stays clean either way.
boldText=$(tput bold 2>/dev/null)
resetText=$(tput sgr0 2>/dev/null)

# Maximum number of concurrent firmware-catalog lookups. Kept modest to be a
# good citizen toward the public catalog API while still parallelizing.
lookupMaxJobs=6

# Verification mode for files already in the destination:
#   fast     - trust a file whose on-disk size matches the catalog's (cheap).
#   thorough - re-hash every existing file in full on every run (slow but
#              catches silent corruption, not just truncation).
# Freshly downloaded files are always fully verified regardless of this setting.
verifyMode="fast"

# Pushover credentials are read from the keychain once per process and cached
# here, so a long download run doesn't re-query the keychain for every file.
# Configuring or removing credentials resets the cache (see notify_pushover_*).
pushoverCredsLoaded="N"
pushoverUserKey=""
pushoverAppToken=""

# Subfolder names for organizing downloads by device type
AppleTVsubfolder="Apple TV Software Updates"
iPadsubfolder="iPad Software Updates"
iPhonesubfolder="iPhone Software Updates"
iPodsubfolder="iPod Software Updates"
Watchsubfolder="Apple Watch Software Updates"
Othersubfolder="Other Software Updates"

# Lockfile path. Kept per-user (and under the user's own temp directory when
# available) so that on a shared Mac one user's lockfile can never block — or be
# blocked by — another user's. $TMPDIR is per-user on macOS.
flypswLockfile="${TMPDIR:-/tmp}/flypsw_lockfile.$(id -u)"

# Temporary paths (initialized at startup — see main execution block).
flypswDevicesJson=""
flypswFwDir=""

# Global arrays
# deviceModelList entries:     "identifier|name"
# latestUnifiedList entries:   "identifier|filename|URL|sha256_hash|filesize"
# queuedUnifiedList entries:   subset of latestUnifiedList needing download
deviceModelList=()
latestUnifiedList=()
queuedUnifiedList=()

# Firmware catalog API — queries return download URLs on Apple's CDN
IPSW_API_BASE="https://api.ipsw.me/v4"


# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# bail_cleanup
# Removes lock and temp files on exit or interrupt.
# ------------------------------------------------------------------------------
bail_cleanup() {
    # Disarm the trap first so the exit below doesn't re-enter this function.
    trap - EXIT INT TERM
    rm -f "$flypswLockfile"
    [ -n "$flypswDevicesJson" ] && rm -f "$flypswDevicesJson"
    [ -n "$flypswFwDir" ]       && rm -rf "$flypswFwDir"
    exit
}


# ------------------------------------------------------------------------------
# check_instance
# Prevents multiple concurrent instances. Writes the current PID into the
# lockfile so stale lockfiles from crashed runs are detected and removed
# automatically. Uses noclobber for atomic creation to close the TOCTOU race.
# ------------------------------------------------------------------------------
check_instance() {
    if [[ -e "$flypswLockfile" ]]; then
        local storedPID
        storedPID=$(cat "$flypswLockfile" 2>/dev/null)
        # Treat the lock as live only if the stored PID is both alive AND still a
        # flypsw process. This avoids a false "already running" when the OS has
        # recycled that PID for an unrelated program after a hard crash.
        if [[ -n "$storedPID" ]] && kill -0 "$storedPID" 2>/dev/null \
                && ps -p "$storedPID" -o command= 2>/dev/null | grep -q "flypsw"; then
            disp_print_header
            echo "flypsw is already running (PID $storedPID)."
            echo "Only one instance of flypsw can run at a time."
            echo ""
            echo "Hit enter to exit."
            read -r
            exit
        else
            rm -f "$flypswLockfile"
        fi
    fi
    (set -o noclobber; echo $$ > "$flypswLockfile") 2>/dev/null || {
        disp_print_header
        echo "flypsw is already running."
        echo "Only one instance of flypsw can run at a time."
        echo ""
        echo "Hit enter to exit."
        read -r
        exit
    }
}


# ------------------------------------------------------------------------------
# disp_print_header
# Clears the screen and prints the script version and current date/time.
# ------------------------------------------------------------------------------
disp_print_header() {
    clear
    echo "flypsw version $currentVersion"
    date
    echo ""
}


# ------------------------------------------------------------------------------
# preflight_check_xcode_cli_tools
# flypsw depends on python3 from the Xcode Command Line Tools to parse the
# firmware catalog (Apple distributes it as JSON). This runs before any catalog
# lookup so a missing toolchain is resolved up front rather than failing partway
# through. If the tools are absent the user is offered Apple's installer, then
# flypsw exits.
# ------------------------------------------------------------------------------
preflight_check_xcode_cli_tools() {
    if ! xcode-select -p &>/dev/null || ! command -v python3 &>/dev/null; then

        disp_print_header

        echo "The Xcode Command Line Tools do not appear to be installed."
        echo ""
        echo "flypsw requires them for parsing firmware data from the catalog (python3)."
        echo ""
        echo "Enter 'I' to install the Xcode Command Line Tools now, or any other key to exit."
        read -rn 1 xcodeCLTCheck
        echo ""

        case "$xcodeCLTCheck" in

        I|i )
            xcode-select --install
            echo ""
            echo "Follow the prompts to complete installation, then run flypsw again."
            echo ""
            echo "Hit enter to exit flypsw."
            read -r
            bail_cleanup
            ;;

        * )
            bail_cleanup
            ;;

        esac
    fi
}


# ------------------------------------------------------------------------------
# get_subfolder_for_file
# Outputs the correct destination subfolder path for a given device identifier.
# Routing on the catalog's device identifier (e.g., "iPhone14,2") rather than
# the IPSW filename is authoritative — filenames don't always carry the family
# prefix, which would otherwise misfile firmware into "Other".
# $1 = device identifier
# ------------------------------------------------------------------------------
get_subfolder_for_file() {
    case "$1" in
        AppleTV*)  echo "$destinationFolder/$AppleTVsubfolder" ;;
        iPad*)     echo "$destinationFolder/$iPadsubfolder" ;;
        iPhone*)   echo "$destinationFolder/$iPhonesubfolder" ;;
        iPod*)     echo "$destinationFolder/$iPodsubfolder" ;;
        Watch*)    echo "$destinationFolder/$Watchsubfolder" ;;
        *)         echo "$destinationFolder/$Othersubfolder" ;;
    esac
}


# ------------------------------------------------------------------------------
# verify_sha_hash
# Verifies a local file's SHA256 hash against a provided hash.
# Returns 0 on match, non-zero on mismatch.
# $1 = local file path, $2 = expected SHA256 hash
# ------------------------------------------------------------------------------
verify_sha_hash() {
    local shaReturn
    shaReturn=$(shasum -a 256 "$1" | awk '{print $1}')
    [[ "$2" = "$shaReturn" ]] && return 0 || return 1
}


# ------------------------------------------------------------------------------
# verify_zip_archive
# Returns 0 if the file is a structurally complete zip archive (IPSW files are
# zip). This reads the archive directory at the end of the file, so it cheaply
# catches a truncated/partial download without hashing the whole file.
# $1 = local file path
# ------------------------------------------------------------------------------
verify_zip_archive() {
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1])" "$1" 2>/dev/null
}


# ------------------------------------------------------------------------------
# file_size_bytes
# Prints the size of a file in bytes (BSD stat, as shipped with macOS), or
# nothing if the file can't be stat'd.
# $1 = local file path
# ------------------------------------------------------------------------------
file_size_bytes() {
    stat -f%z "$1" 2>/dev/null
}


# ==============================================================================
# PUSHOVER NOTIFICATION FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# notify_pushover_send
# Sends a Pushover notification using credentials stored in the login keychain.
# Returns silently if credentials are not configured or the send fails.
# $1 - Message text to send
# ------------------------------------------------------------------------------
notify_pushover_send() {
    # Load credentials from the keychain once per process, then reuse them. The
    # cache is reset whenever credentials are configured or removed.
    if [ "$pushoverCredsLoaded" != "Y" ]; then
        pushoverUserKey=$(security find-generic-password \
            -s "flypsw-pushover-userkey" -a "flypsw" -w 2>/dev/null)
        pushoverAppToken=$(security find-generic-password \
            -s "flypsw-pushover-apptoken" -a "flypsw" -w 2>/dev/null)
        pushoverCredsLoaded="Y"
    fi

    if [ -z "$pushoverUserKey" ] || [ -z "$pushoverAppToken" ]; then
        return 0
    fi

    # The secret token and user key are passed via a config file on stdin rather
    # than on the command line, so they never appear in the process list (ps).
    curl \
        --silent \
        --max-time 10 \
        --form-string "message=${1}" \
        --config - \
        "https://api.pushover.net/1/messages.json" \
        > /dev/null 2>&1 <<CURLCFG
form-string = "token=${pushoverAppToken}"
form-string = "user=${pushoverUserKey}"
CURLCFG
}


# ------------------------------------------------------------------------------
# notify_pushover_test
# Fetches credentials from the login keychain and sends a test notification,
# reporting the HTTP result.
# ------------------------------------------------------------------------------
notify_pushover_test() {
    local userKey appToken testStatus

    userKey=$(security find-generic-password \
        -s "flypsw-pushover-userkey" -a "flypsw" -w 2>/dev/null)

    appToken=$(security find-generic-password \
        -s "flypsw-pushover-apptoken" -a "flypsw" -w 2>/dev/null)

    if [ -z "$userKey" ] || [ -z "$appToken" ]; then
        echo "No Pushover credentials found in the keychain."
        echo "Configure credentials using option 1 before testing."
        return 1
    fi

    echo "Sending test notification..."
    echo ""

    # Secrets passed via stdin config (see notify_pushover_send) to keep them
    # out of the process list.
    testStatus=$(curl \
        --silent \
        --max-time 10 \
        --output /dev/null \
        --write-out "%{http_code}" \
        --form-string "message=flypsw: Test notification — Pushover is configured correctly." \
        --config - \
        "https://api.pushover.net/1/messages.json" 2>/dev/null <<CURLCFG
form-string = "token=${appToken}"
form-string = "user=${userKey}"
CURLCFG
)

    if [ "$testStatus" = "200" ]; then
        echo "Test notification sent successfully. Check your Pushover device."
        return 0
    else
        echo "Test notification failed (HTTP ${testStatus:-no response})."
        echo "Verify your credentials and network connection."
        return 1
    fi
}


# ------------------------------------------------------------------------------
# notify_pushover_remove
# Confirms intent then permanently removes Pushover credentials from the
# login keychain.
# ------------------------------------------------------------------------------
notify_pushover_remove() {
    disp_print_header

    echo "Remove Pushover Credentials"
    echo ""
    echo "This will permanently remove your Pushover credentials from your login"
    echo "keychain. flypsw will no longer send Pushover notifications."
    echo ""
    printf "Are you sure you want to remove Pushover credentials? Y/N: "
    read -r confirmRemove
    echo ""

    if [ "$confirmRemove" = "Y" ] || [ "$confirmRemove" = "y" ]; then
        security delete-generic-password \
            -s "flypsw-pushover-userkey" -a "flypsw" 2>/dev/null
        security delete-generic-password \
            -s "flypsw-pushover-apptoken" -a "flypsw" 2>/dev/null
        pushoverCredsLoaded="N"   # force a reload on next notification
        echo "Pushover credentials removed from the keychain."
        echo "flypsw will no longer send Pushover notifications."
    else
        echo "Removal cancelled."
    fi

    echo ""
    echo "Hit enter to continue."
    read -r
}


# ------------------------------------------------------------------------------
# notify_pushover_setup
# Sub-menu for all Pushover notification management: configure credentials,
# send a test notification, or remove credentials.
# ------------------------------------------------------------------------------
notify_pushover_setup() {
    local pushoverMenuChoice=""

    while [ "$pushoverMenuChoice" == "" ]; do
        disp_print_header

        echo "Pushover Notification Setup"
        echo ""
        echo " 1. Configure or update credentials"
        echo ""
        echo " 2. Send a test notification"
        echo ""
        echo " 3. Remove credentials"
        echo ""
        echo " X. Return to main menu"
        echo ""
        echo "Enter a number or letter and hit return: "
        echo ""
        read -r pushoverMenuChoice

        case "$pushoverMenuChoice" in

        1 )
            disp_print_header

            echo "Pushover Credential Configuration"
            echo ""
            echo "You will need your Pushover User Key and an Application API Token."
            echo "Both are available from your account at pushover.net."
            echo ""
            echo "Credentials will be stored in your login keychain on this Mac."
            echo ""

            local userKey appToken

            printf "Enter your Pushover User Key (input masked): "
            read -rs userKey
            echo ""

            printf "Enter your Pushover App Token (input masked): "
            read -rs appToken
            echo ""
            echo ""

            if [ -z "$userKey" ] || [ -z "$appToken" ]; then
                echo "Setup cancelled — both a User Key and App Token are required."
            elif ! [[ "$userKey" =~ ^[A-Za-z0-9]+$ ]] || ! [[ "$appToken" =~ ^[A-Za-z0-9]+$ ]]; then
                # Pushover keys/tokens are alphanumeric. Rejecting anything else
                # avoids storing a mistyped value and keeps the value safe for the
                # security interactive parser.
                echo "Setup cancelled — keys must contain only letters and numbers."
                echo "Check that you pasted your Pushover User Key and App Token correctly."
            else
                local saveUserKeyResult saveAppTokenResult

                # Credentials are written via security's interactive mode, fed on
                # stdin, so the secret values never appear on a command line that
                # other local users could observe with ps. -T /usr/bin/security
                # lets flypsw read them back without a GUI prompt; omitting the
                # keychain path targets the user's default (login) keychain.
                security -i >/dev/null 2>&1 <<SECCFG
add-generic-password -U -s "flypsw-pushover-userkey" -a "flypsw" -T /usr/bin/security -w "${userKey}"
SECCFG
                saveUserKeyResult=$?

                security -i >/dev/null 2>&1 <<SECCFG
add-generic-password -U -s "flypsw-pushover-apptoken" -a "flypsw" -T /usr/bin/security -w "${appToken}"
SECCFG
                saveAppTokenResult=$?

                userKey=""; appToken=""
                pushoverCredsLoaded="N"   # force a reload on next notification

                if [ "$saveUserKeyResult" = "0" ] && [ "$saveAppTokenResult" = "0" ]; then
                    echo "Pushover credentials saved to your login keychain."
                    echo ""
                    echo "To verify or remove them, open Keychain Access, select the login"
                    echo "keychain, and search for 'flypsw-pushover'."
                    echo ""
                    printf "Would you like to send a test notification now? Y/N: "
                    read -r testConfirm
                    echo ""
                    if [ "$testConfirm" = "Y" ] || [ "$testConfirm" = "y" ]; then
                        notify_pushover_test
                    fi
                else
                    echo "There was an error saving credentials to the keychain."
                    # Roll back any partial write so a half-configured pair isn't
                    # left behind in the keychain.
                    security delete-generic-password \
                        -s "flypsw-pushover-userkey" -a "flypsw" 2>/dev/null
                    security delete-generic-password \
                        -s "flypsw-pushover-apptoken" -a "flypsw" 2>/dev/null
                fi
            fi

            echo ""
            echo "Hit enter to continue."
            read -r
            pushoverMenuChoice=""
            ;;

        2 )
            disp_print_header
            notify_pushover_test
            echo ""
            echo "Hit enter to continue."
            read -r
            pushoverMenuChoice=""
            ;;

        3 )
            notify_pushover_remove
            pushoverMenuChoice=""
            ;;

        [Xx] )
            break
            ;;

        * )
            pushoverMenuChoice=""
            ;;

        esac
    done
}


# ==============================================================================
# FIRMWARE CATALOG FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# get_device_list
# Downloads the full device list from the firmware catalog API.
# ------------------------------------------------------------------------------
get_device_list() {
    disp_print_header
    echo "Downloading device list from the firmware catalog..."
    echo ""

    if ! curl -sf --max-time 30 "$IPSW_API_BASE/devices" -o "$flypswDevicesJson"; then
        echo "ERROR: Could not download the device list."
        echo "Check your internet connection and try again."
        echo ""
        echo "Hit enter to return to the main menu."
        read -r
        return 1
    fi

    echo "Device list downloaded successfully."
    echo ""
    return 0
}


# ------------------------------------------------------------------------------
# build_device_list
# Filters the downloaded device list by the selected device type(s).
# Populates the global deviceModelList array.
# $1 = filter: "all", or space-separated identifier prefixes (e.g., "iPhone iPad")
# ------------------------------------------------------------------------------
build_device_list() {
    local filter="$1"
    deviceModelList=()

    echo "Filtering device list for selected device types..."
    echo ""

    # The catalog path and the family filter are passed as arguments rather than
    # interpolated into the Python source, so untrusted-looking input can never
    # become executable code.
    local deviceLines
    deviceLines=$(python3 - "$flypswDevicesJson" "$filter" <<'PYEOF' 2>/dev/null
import json, sys

catalogPath = sys.argv[1]
familyFilter = sys.argv[2]

with open(catalogPath) as f:
    devices = json.load(f)

prefixes = None if familyFilter == "all" else familyFilter.split()

for d in devices:
    identifier = d.get("identifier", "")
    name = d.get("name", "")
    if prefixes is None or any(identifier.startswith(p) for p in prefixes):
        print(identifier + "|" + name)
PYEOF
)

    if [ -z "$deviceLines" ]; then
        echo "No devices found for the selected device types."
        echo ""
        echo "Hit enter to return to the main menu."
        read -r
        return 1
    fi

    while IFS= read -r line; do
        [ -n "$line" ] && deviceModelList+=("$line")
    done <<< "$deviceLines"

    echo "Found ${#deviceModelList[@]} devices matching your selection."
    echo ""
    return 0
}


# ------------------------------------------------------------------------------
# build_working_array
# For each device in deviceModelList, fetches firmware data from the catalog in
# parallel (bounded by lookupMaxJobs) and populates latestUnifiedList with
# identifier|filename|URL|sha256_hash|filesize entries, preferring signed builds.
# ------------------------------------------------------------------------------
build_working_array() {
    disp_print_header
    echo "Retrieving latest IPSW information for ${#deviceModelList[@]} devices..."
    echo "This may take a few minutes depending on the number of devices selected."
    echo ""

    # Per-device firmware JSON is fetched into a private temp directory so that
    # parallel lookups never collide on a shared file. The directory is cleaned
    # up here and again by bail_cleanup on interrupt.
    flypswFwDir=$(mktemp -d "${TMPDIR:-/tmp}/flypsw_fw.XXXXXX") || return 1

    local total=${#deviceModelList[@]}
    local idx=0 entry identifier runningJobs

    for entry in "${deviceModelList[@]}"; do
        idx=$(( idx + 1 ))
        identifier=${entry%%|*}

        # Throttle to lookupMaxJobs concurrent curls. bash 3.2 has no `wait -n`,
        # so poll the running-job count with a short sleep.
        runningJobs=$(jobs -rp | wc -l | tr -d ' ')
        while [ "$runningJobs" -ge "$lookupMaxJobs" ]; do
            sleep 0.2
            runningJobs=$(jobs -rp | wc -l | tr -d ' ')
        done

        curl -sf --max-time 15 \
            "$IPSW_API_BASE/device/$identifier?type=ipsw" \
            -o "$flypswFwDir/$identifier.json" 2>/dev/null &

        printf "\r  Dispatched %d of %d lookups..." "$idx" "$total"
    done

    echo ""
    echo "  Waiting for lookups to finish..."
    wait

    # Parse every per-device JSON in one Python pass: pick the newest *signed*
    # firmware (an unsigned IPSW can't be restored), fall back to the newest
    # entry only if none are signed, and emit identifier|filename|url|sha|size.
    local resultLines
    resultLines=$(python3 - "$flypswFwDir" <<'PYEOF' 2>/dev/null
import json, os, sys

fwDir = sys.argv[1]

for fileName in sorted(os.listdir(fwDir)):
    if not fileName.endswith(".json"):
        continue
    identifier = fileName[:-5]
    try:
        with open(os.path.join(fwDir, fileName)) as f:
            data = json.load(f)
    except Exception:
        continue

    firmwares = data.get("firmwares", [])
    if not firmwares:
        continue

    # Don't rely on the catalog's array order: sort newest-first by release date
    # (ISO-8601 strings sort correctly), then prefer the newest *signed* build,
    # falling back to the newest overall only if none are signed.
    firmwares.sort(key=lambda fw: fw.get("releasedate") or "", reverse=True)
    chosen = next((fw for fw in firmwares if fw.get("signed")), firmwares[0])

    url = chosen.get("url", "")
    if not url:
        continue
    if url.startswith("http://"):
        url = "https://" + url[len("http://"):]

    sha256 = chosen.get("sha256sum") or "notPresent"
    filesize = chosen.get("filesize") or 0
    fileName = url.split("/")[-1].split("?")[0]
    if not fileName:
        continue

    print("|".join([identifier, fileName, url, sha256, str(filesize)]))
PYEOF
)

    rm -rf "$flypswFwDir"
    flypswFwDir=""

    if [ -n "$resultLines" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && latestUnifiedList+=("$line")
        done <<< "$resultLines"
    fi

    echo ""

    if [ ${#latestUnifiedList[@]} -eq 0 ]; then
        echo "No IPSW firmware entries were found."
        echo "The firmware catalog may be temporarily unavailable."
        echo ""
        return 1
    fi

    echo "Found ${#latestUnifiedList[@]} IPSW firmware files."
    echo ""
    return 0
}


# ------------------------------------------------------------------------------
# check_destination_contents
# Compares latestUnifiedList against existing files in the destination.
# Files that are missing or fail SHA256 verification are added to queuedUnifiedList.
# Returns 1 (and prompts) if nothing needs to be downloaded.
# ------------------------------------------------------------------------------
check_destination_contents() {
    local cdcIdentifier fileToCheck shaToVerify sizeToCheck pathToCheck filePath
    local total=${#latestUnifiedList[@]}
    local i displayCheckCounter onDiskSize good
    queuedUnifiedList=()

    disp_print_header
    if [ "$verifyMode" = "thorough" ]; then
        echo "Checking the destination (thorough: full hash of every file)..."
    else
        echo "Checking the destination (fast: size check of existing files)..."
    fi
    echo ""

    for (( i = 0; i < total; i++ )); do
        displayCheckCounter=$(( i + 1 ))
        IFS='|' read -r cdcIdentifier fileToCheck _ shaToVerify sizeToCheck <<< "${latestUnifiedList[$i]}"
        pathToCheck=$(get_subfolder_for_file "$cdcIdentifier")
        filePath="$pathToCheck/$fileToCheck"

        printf "\r  Verifying %d of %d existing files...   " "$displayCheckCounter" "$total"

        # Missing file always needs downloading.
        if [ ! -e "$filePath" ]; then
            queuedUnifiedList+=("${latestUnifiedList[$i]}")
            continue
        fi

        good="N"
        if [ "$verifyMode" = "thorough" ]; then
            # Full integrity check: hash when the catalog provides one, otherwise
            # confirm the archive is structurally complete.
            if [[ "$shaToVerify" != "notPresent" ]]; then
                verify_sha_hash "$filePath" "$shaToVerify" && good="Y"
            else
                verify_zip_archive "$filePath" && good="Y"
            fi
        else
            # Fast check: trust a size match against the catalog. When the catalog
            # didn't report a size, fall back to the cheap archive-completeness
            # check rather than hashing the whole file.
            case "$sizeToCheck" in
                ''|0|*[!0-9]*)
                    verify_zip_archive "$filePath" && good="Y"
                    ;;
                *)
                    onDiskSize=$(file_size_bytes "$filePath")
                    [ "$onDiskSize" = "$sizeToCheck" ] && good="Y"
                    ;;
            esac
        fi

        if [ "$good" != "Y" ]; then
            rm -f "$filePath"
            queuedUnifiedList+=("${latestUnifiedList[$i]}")
        fi
    done

    echo ""

    if [ ${#queuedUnifiedList[@]} -eq 0 ]; then
        disp_print_header
        echo "All ${#latestUnifiedList[@]} IPSW files are already present and verified."
        echo "Nothing to download."
        echo ""
        echo "Hit enter to return to the main menu."
        read -r
        return 1
    fi

    disp_print_header
    echo "flypsw has ${#queuedUnifiedList[@]} IPSW file(s) to download."
    echo ""
    check_free_space
    echo "Hit enter to begin downloading, or press Ctrl-C to cancel."
    read -r
    return 0
}


# ------------------------------------------------------------------------------
# check_free_space
# Warns if the destination volume may not have room for the queued downloads.
# Sums the catalog-reported sizes of queuedUnifiedList and compares against the
# free space reported by df. Sizes the catalog doesn't provide are skipped, so
# this is advisory only.
# ------------------------------------------------------------------------------
check_free_space() {
    local entry sizeField neededBytes=0 availKb neededKb

    for entry in "${queuedUnifiedList[@]}"; do
        sizeField=${entry##*|}
        case "$sizeField" in
            ''|*[!0-9]*) ;;                              # skip non-numeric/unknown
            *) neededBytes=$(( neededBytes + sizeField )) ;;
        esac
    done

    [ "$neededBytes" -eq 0 ] && return 0

    availKb=$(df -k "$destinationFolder" 2>/dev/null | awk 'NR==2 {print $4}')
    case "$availKb" in
        ''|*[!0-9]*) return 0 ;;                         # couldn't read df; skip
        *) ;;                                            # valid number; continue
    esac

    neededKb=$(( neededBytes / 1024 ))

    if [ "$availKb" -lt "$neededKb" ]; then
        echo "WARNING: the queued downloads need about $(( neededKb / 1024 )) MB,"
        echo "but the destination volume has only about $(( availKb / 1024 )) MB free."
        echo "Free up space before continuing, or some downloads will fail."
        echo ""
    fi

    return 0
}


# ------------------------------------------------------------------------------
# download_queued_ipsws
# Downloads each IPSW file in queuedUnifiedList to its appropriate subfolder,
# then verifies the SHA256 hash. Returns the number of failed downloads.
# ------------------------------------------------------------------------------
download_queued_ipsws() {
    downloadFailureCount=0
    local idToDL fileToDL URLtoDL shaToCompare
    local downloadCount downloadTargetPath totalCount remaining curlResult i

    totalCount=${#queuedUnifiedList[@]}

    for (( i = 0; i < totalCount; i++ )); do
        IFS='|' read -r idToDL fileToDL URLtoDL shaToCompare _ <<< "${queuedUnifiedList[$i]}"
        downloadCount=$(( i + 1 ))
        remaining=$(( totalCount - downloadCount ))
        downloadTargetPath=$(get_subfolder_for_file "$idToDL")

        disp_print_header
        echo "Downloading IPSW $downloadCount of $totalCount"
        echo ""
        echo "  Device:  $idToDL"
        echo "  File:    $fileToDL"
        echo "  To:      $downloadTargetPath"
        echo ""

        # -C - resumes a partial transfer; --retry rides out transient network
        # drops, resuming between attempts rather than restarting from zero.
        # (Resume requires the server to honor byte ranges; Apple's CDN does. On
        # a mirror that doesn't, curl returns 33 and flypsw re-downloads cleanly.)
        curl -L --fail --progress-bar -C - --retry 3 --retry-delay 5 \
            "$URLtoDL" -o "$downloadTargetPath/$fileToDL"
        curlResult=$?

        if [ "$curlResult" != "0" ]; then
            echo ""
            echo "Download FAILED for $fileToDL (curl error $curlResult)."
            rm -f "$downloadTargetPath/$fileToDL"
            notify_pushover_send "flypsw: Download failed for $fileToDL."
            downloadFailureCount=$(( downloadFailureCount + 1 ))
            echo ""
            continue
        fi

        # Freshly downloaded files are always fully verified, regardless of the
        # destination-check verifyMode: hash when the catalog provides one,
        # otherwise confirm the archive is structurally complete.
        echo ""
        if [[ "$shaToCompare" != "notPresent" ]]; then
            echo "Verifying SHA256 hash..."
            if ! verify_sha_hash "$downloadTargetPath/$fileToDL" "$shaToCompare"; then
                echo "Hash verification FAILED — removing corrupt file."
                rm -f "$downloadTargetPath/$fileToDL"
                notify_pushover_send "flypsw: Verification failed for $fileToDL — file removed."
                downloadFailureCount=$(( downloadFailureCount + 1 ))
                echo ""
                continue
            fi
            echo "Hash verified."
        else
            echo "Verifying archive integrity..."
            if ! verify_zip_archive "$downloadTargetPath/$fileToDL"; then
                echo "Archive check FAILED — removing incomplete file."
                rm -f "$downloadTargetPath/$fileToDL"
                notify_pushover_send "flypsw: Archive check failed for $fileToDL — file removed."
                downloadFailureCount=$(( downloadFailureCount + 1 ))
                echo ""
                continue
            fi
            echo "Archive verified."
        fi

        if [ "$remaining" -gt 0 ]; then
            notify_pushover_send "flypsw: [$downloadCount/$totalCount] $fileToDL — downloaded and verified. $remaining remaining."
        else
            notify_pushover_send "flypsw: [$downloadCount/$totalCount] $fileToDL — downloaded and verified."
        fi

        echo ""
    done

    return $(( downloadFailureCount > 0 ? 1 : 0 ))
}


# ------------------------------------------------------------------------------
# prep_folder_structure
# Creates destination subfolders if they do not already exist.
# ------------------------------------------------------------------------------
prep_folder_structure() {
    [[ -d "$destinationFolder/$AppleTVsubfolder" ]] || mkdir -p "$destinationFolder/$AppleTVsubfolder"
    [[ -d "$destinationFolder/$iPadsubfolder" ]]    || mkdir -p "$destinationFolder/$iPadsubfolder"
    [[ -d "$destinationFolder/$iPhonesubfolder" ]]  || mkdir -p "$destinationFolder/$iPhonesubfolder"
    [[ -d "$destinationFolder/$iPodsubfolder" ]]    || mkdir -p "$destinationFolder/$iPodsubfolder"
    [[ -d "$destinationFolder/$Watchsubfolder" ]]   || mkdir -p "$destinationFolder/$Watchsubfolder"
    [[ -d "$destinationFolder/$Othersubfolder" ]]   || mkdir -p "$destinationFolder/$Othersubfolder"
}


# ------------------------------------------------------------------------------
# run_download_workflow
# Orchestrates the full download process: catalog download → device filter →
# firmware lookup → destination check → download → Pushover notification.
# ------------------------------------------------------------------------------
run_download_workflow() {
    deviceModelList=()
    latestUnifiedList=()
    queuedUnifiedList=()

    get_device_list || return 1

    local filterPrefixes
    case "$deviceTypeSelection" in
    1 ) filterPrefixes="iPhone iPad iPod AppleTV" ;;
    2 ) filterPrefixes="iPhone" ;;
    3 ) filterPrefixes="iPad" ;;
    4 ) filterPrefixes="iPod" ;;
    5 ) filterPrefixes="AppleTV" ;;
    6 ) filterPrefixes="iPhone iPad" ;;
    7 ) filterPrefixes="iPhone iPad iPod" ;;
    8 ) filterPrefixes="Watch" ;;
    9 ) filterPrefixes="all" ;;
    * ) return 1 ;;
    esac

    disp_print_header
    build_device_list "$filterPrefixes" || return 1
    build_working_array                 || return 1
    if ! check_destination_contents; then return 0; fi

    download_queued_ipsws
    local dlResult=$?

    disp_print_header

    local totalQueued=${#queuedUnifiedList[@]}

    if [ "$dlResult" = "0" ]; then
        echo "All $totalQueued IPSW downloads completed and verified successfully."
        notify_pushover_send "flypsw: All $totalQueued IPSW downloads complete."
    else
        local succeeded
        succeeded=$(( totalQueued - downloadFailureCount ))
        echo "Downloads complete. $downloadFailureCount of $totalQueued file(s) failed and were removed."
        echo "Run flypsw again to retry failed downloads."
        notify_pushover_send "flypsw: $succeeded of $totalQueued downloads succeeded. $downloadFailureCount failed — run again to retry."
    fi

    echo ""
    echo "Hit enter to return to the main menu."
    read -r

    return $dlResult
}


# ==============================================================================
# MENUS
# ==============================================================================

# ------------------------------------------------------------------------------
# menu_intro
# Displays the welcome screen and requires confirmation to proceed.
# ------------------------------------------------------------------------------
menu_intro() {
    disp_print_header

    while [ "$okToRun" == "N" ]; do
        echo "Welcome to flypsw"
        echo ""
        echo "flypsw automates the download of iOS, iPadOS, tvOS, and iPod touch IPSW"
        echo "firmware files. Rather than searching for direct links elsewhere, flypsw"
        echo "looks up the latest signed firmware via the ipsw.me catalog and downloads"
        echo "it from Apple's servers to speed up your deployments and testing."
        echo ""
        echo "Though unlikely to cause data loss or other problems, flypsw is provided"
        echo "as-is. As an open source project, flypsw can be fully audited by the user."
        echo "flypsw's developers take no responsibility for events arising from its use."
        echo ""
        echo "Press 'Y' to continue or any other key to exit flypsw."

        read -rn 1 okToRun
        echo ""

        case "$okToRun" in
        Y|y )
            ;;
        * )
            bail_cleanup
            ;;
        esac
    done
}


# ------------------------------------------------------------------------------
# menu_device_type
# Prompts the user to select which device types to check and download.
# Sets $deviceTypeSelection to the chosen number, or "X" to go back.
# ------------------------------------------------------------------------------
menu_device_type() {
    deviceTypeSelection=""

    while [ "$deviceTypeSelection" == "" ]; do
        disp_print_header

        echo "Select the device types to check for new firmware:"
        echo ""
        echo "${boldText}1. iPhone, iPad, iPod touch, and Apple TV${resetText}"
        echo "   (The classic iOS device set)"
        echo ""
        echo "${boldText}2. iPhone only${resetText}"
        echo ""
        echo "${boldText}3. iPad only${resetText}"
        echo "   (Includes iPad mini, iPad Air, and iPad Pro)"
        echo ""
        echo "${boldText}4. iPod touch only${resetText}"
        echo ""
        echo "${boldText}5. Apple TV only${resetText}"
        echo ""
        echo "${boldText}6. iPhone and iPad${resetText}"
        echo ""
        echo "${boldText}7. iPhone, iPad, and iPod touch${resetText}"
        echo ""
        echo "${boldText}8. Apple Watch only${resetText}"
        echo ""
        echo "${boldText}9. All supported devices${resetText}"
        echo "   (iPhone, iPad, iPod, Apple TV, Watch, and more)"
        echo ""
        echo "${boldText}X. Return to main menu${resetText}"
        echo ""
        echo "Enter your choice and hit return: "
        read -r deviceTypeSelection

        case "$deviceTypeSelection" in
        [1-9] )
            ;;
        [Xx] )
            deviceTypeSelection="X"
            ;;
        * )
            deviceTypeSelection=""
            ;;
        esac
    done
}


# ------------------------------------------------------------------------------
# menu_destination
# Prompts the user to select where IPSW files should be saved.
# Sets $destinationFolder, or leaves it empty if the user cancels.
# ------------------------------------------------------------------------------
menu_destination() {
    local chooseYourPath=""
    destinationFolder=""

    while [ "$chooseYourPath" == "" ]; do
        disp_print_header

        echo "Choose a destination folder for downloaded IPSW files:"
        echo ""
        echo "${boldText}1. Downloads folder${resetText}"
        echo "   ($HOME/Downloads/IPSW Files)"
        echo ""
        echo "${boldText}2. Desktop${resetText}"
        echo "   ($HOME/Desktop/IPSW Files)"
        echo ""
        echo "${boldText}3. iTunes library folder${resetText}"
        echo "   ($HOME/Library/iTunes)"
        echo ""
        echo "${boldText}X. Return to main menu${resetText}"
        echo ""
        echo "If the required folder structure does not exist, flypsw will create it."
        echo ""
        echo "Enter your choice and hit return: "
        read -r chooseYourPath

        case "$chooseYourPath" in
        1 )
            destinationFolder="$HOME/Downloads/IPSW Files"
            ;;
        2 )
            destinationFolder="$HOME/Desktop/IPSW Files"
            ;;
        3 )
            destinationFolder="$HOME/Library/iTunes"
            ;;
        [Xx] )
            destinationFolder=""
            chooseYourPath="X"
            ;;
        * )
            chooseYourPath=""
            ;;
        esac
    done
}


# ------------------------------------------------------------------------------
# main_menu
# The main application loop. Routes to the download workflow, Pushover setup,
# or exit.
# ------------------------------------------------------------------------------
main_menu() {
    local trackToTake stayInMainMenu="Y"

    while [ "$stayInMainMenu" == "Y" ]; do
        trackToTake=""

        while [ "$trackToTake" == "" ]; do
            disp_print_header

            local verifyLabel
            if [ "$verifyMode" = "thorough" ]; then
                verifyLabel="Thorough (full hash of every file)"
            else
                verifyLabel="Fast (size check of existing files)"
            fi

            echo "flypsw Main Menu"
            echo ""
            echo "${boldText}1. Download latest IPSW files${resetText}"
            echo ""
            echo "${boldText}2. Configure Pushover notifications${resetText}"
            echo ""
            echo "${boldText}3. Verification mode: ${verifyLabel}${resetText}"
            echo ""
            echo "${boldText}X. Exit flypsw${resetText}"
            echo ""
            echo "Enter your choice and hit return: "
            read -r trackToTake

            case "$trackToTake" in

            1 )
                menu_device_type
                if [ "$deviceTypeSelection" != "X" ]; then
                    menu_destination
                    if [ -n "$destinationFolder" ]; then
                        prep_folder_structure
                        run_download_workflow
                    fi
                fi
                deviceTypeSelection=""
                ;;

            2 )
                notify_pushover_setup
                ;;

            3 )
                # Toggle between fast and thorough destination verification.
                if [ "$verifyMode" = "thorough" ]; then
                    verifyMode="fast"
                else
                    verifyMode="thorough"
                fi
                trackToTake=""
                ;;

            [Xx] )
                stayInMainMenu="N"
                ;;

            * )
                trackToTake=""
                ;;

            esac
        done
    done
}


# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# check_instance may exit early if another copy is already running. Arm the
# cleanup trap only after it returns, so an early exit never removes the lockfile
# or temp files belonging to that other instance.
check_instance

trap bail_cleanup EXIT INT TERM

flypswDevicesJson=$(mktemp "${TMPDIR:-/tmp}/flypsw_devices.XXXXXX.json")

preflight_check_xcode_cli_tools
menu_intro
main_menu
bail_cleanup
