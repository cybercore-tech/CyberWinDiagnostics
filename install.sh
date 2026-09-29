#!/bin/sh
# Install/update the source-only CyberWinDiagnostics folder on a USB or disk.
set -eu

REPO_BASE='https://raw.githubusercontent.com/cybercore-tech/CyberWinDiagnostics/main'
DESTINATION='./CyberWinDiagnostics'
UPDATE=0

usage() {
    cat <<'EOF'
Usage: install.sh [--dest PATH] [--update]

Downloads and verifies the CyberWinDiagnostics source ZIP, then installs it to
PATH (default: ./CyberWinDiagnostics). No root privileges are used.

Options:
  --dest PATH   Destination folder; use the path to a mounted USB if desired.
  --update      Overlay project files onto an existing CyberWinDiagnostics
                install. Existing reports and unrelated files are preserved.
  -h, --help    Show this help.
EOF
}

fail() {
    printf 'CyberWinDiagnostics installer: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dest)
            [ "$#" -ge 2 ] || fail '--dest requires a path'
            DESTINATION=$2
            shift 2
            ;;
        --update)
            UPDATE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1 (try --help)"
            ;;
    esac
done

[ -n "$DESTINATION" ] || fail 'destination path cannot be empty'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v unzip >/dev/null 2>&1 || fail 'unzip is required'
if command -v sha256sum >/dev/null 2>&1; then
    HASH_COMMAND=sha256sum
elif command -v shasum >/dev/null 2>&1; then
    HASH_COMMAND='shasum -a 256'
else
    fail 'sha256sum (Linux) or shasum (macOS) is required'
fi

if [ -e "$DESTINATION" ] && [ ! -d "$DESTINATION" ]; then
    fail "destination exists and is not a directory: $DESTINATION"
fi
if [ -d "$DESTINATION" ] && [ -n "$(ls -A "$DESTINATION")" ]; then
    if [ "$UPDATE" -ne 1 ]; then
        fail "destination is not empty; choose another path or pass --update: $DESTINATION"
    fi
    [ -f "$DESTINATION/CyberWinDiag.cmd" ] ||
        fail '--update is allowed only for an existing CyberWinDiagnostics install'
fi

TMP_ROOT=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_ROOT/cyberwindiag.XXXXXXXX") || fail 'could not create a temporary directory'
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

ARCHIVE="$WORK_DIR/CyberWinDiagnostics.zip"
CHECKSUM="$WORK_DIR/CyberWinDiagnostics.zip.sha256"
EXTRACTED="$WORK_DIR/extracted"
mkdir -p "$EXTRACTED"

printf 'Downloading CyberWinDiagnostics source bundle...\n'
curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' \
    --output "$ARCHIVE" "$REPO_BASE/CyberWinDiagnostics.zip" ||
    fail 'could not download the source ZIP'
curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' \
    --output "$CHECKSUM" "$REPO_BASE/CyberWinDiagnostics.zip.sha256" ||
    fail 'could not download the ZIP checksum'

EXPECTED=$(awk 'NR == 1 { print tolower($1); exit }' "$CHECKSUM")
case "$EXPECTED" in
    ''|*[!0-9a-f]*) fail 'checksum file is malformed' ;;
esac
[ "${#EXPECTED}" -eq 64 ] || fail 'checksum must contain 64 hexadecimal characters'

if [ "$HASH_COMMAND" = sha256sum ]; then
    ACTUAL=$(sha256sum "$ARCHIVE" | awk '{ print tolower($1) }')
else
    ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{ print tolower($1) }')
fi
[ "$ACTUAL" = "$EXPECTED" ] || fail 'source ZIP SHA-256 verification failed'

unzip -tqq "$ARCHIVE" || fail 'source ZIP is invalid'
unzip -q "$ARCHIVE" -d "$EXTRACTED" || fail 'could not extract source ZIP'
PACKAGE="$EXTRACTED/CyberWinDiagnostics"
[ -f "$PACKAGE/CyberWinDiag.cmd" ] || fail 'source ZIP is missing CyberWinDiag.cmd'
[ -f "$PACKAGE/Scripts/Invoke-CyberWinDiag.ps1" ] || fail 'source ZIP is missing the PowerShell collector'

mkdir -p "$DESTINATION" || fail "could not create destination: $DESTINATION"
cp -R "$PACKAGE/." "$DESTINATION/" || fail "could not copy files to: $DESTINATION"
printf '\nInstalled CyberWinDiagnostics to: %s\n' "$DESTINATION"
printf 'This is the source-only bundle. Windows PowerShell runs the collector; third-party utilities are not included.\n'
