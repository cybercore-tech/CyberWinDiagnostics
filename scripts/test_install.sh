#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cyberwindiag-install-test.XXXXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MOCK_BIN="$TEST_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/curl" <<'MOCK_CURL'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output=$2; shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
[ -n "$output" ] && [ -n "$url" ] || exit 2
case "$url" in
    */CyberWinDiagnostics.zip) cp "$CYBERWIN_TEST_ZIP" "$output" ;;
    */CyberWinDiagnostics.zip.sha256) cp "$CYBERWIN_TEST_SHA" "$output" ;;
    *) exit 2 ;;
esac
MOCK_CURL
chmod +x "$MOCK_BIN/curl"

make_fixture() {
    version=$1
    package="$TEST_ROOT/package/CyberWinDiagnostics"
    rm -rf "$TEST_ROOT/package"
    mkdir -p "$package/Scripts" "$package/Reports"
    printf 'launcher %s\n' "$version" > "$package/CyberWinDiag.cmd"
    printf 'collector %s\n' "$version" > "$package/Scripts/Invoke-CyberWinDiag.ps1"
    printf 'output notes\n' > "$package/Reports/README.txt"
    (cd "$TEST_ROOT/package" && zip -qr "$TEST_ROOT/source.zip" CyberWinDiagnostics)
    sha256sum "$TEST_ROOT/source.zip" > "$TEST_ROOT/source.sha256"
}

make_fixture v1
export PATH="$MOCK_BIN:$PATH"
export CYBERWIN_TEST_ZIP="$TEST_ROOT/source.zip"
export CYBERWIN_TEST_SHA="$TEST_ROOT/source.sha256"
DESTINATION="$TEST_ROOT/USB/CyberWinDiagnostics"

sh -n "$ROOT/install.sh"
sh "$ROOT/install.sh" --help >/dev/null
sh "$ROOT/install.sh" --dest "$DESTINATION" >/dev/null
grep -q 'launcher v1' "$DESTINATION/CyberWinDiag.cmd"

mkdir -p "$DESTINATION/Reports"
printf 'private report\n' > "$DESTINATION/Reports/customer-data.txt"
if sh "$ROOT/install.sh" --dest "$DESTINATION" >/dev/null 2>&1; then
    echo 'FAIL: non-empty install destination was overwritten without --update' >&2
    exit 1
fi

make_fixture v2
sh "$ROOT/install.sh" --dest "$DESTINATION" --update >/dev/null
grep -q 'launcher v2' "$DESTINATION/CyberWinDiag.cmd"
grep -q 'private report' "$DESTINATION/Reports/customer-data.txt"

printf '%064d  CyberWinDiagnostics.zip\n' 0 > "$TEST_ROOT/source.sha256"
BAD_DESTINATION="$TEST_ROOT/USB/should-not-exist"
if sh "$ROOT/install.sh" --dest "$BAD_DESTINATION" >/dev/null 2>&1; then
    echo 'FAIL: installer accepted an invalid SHA-256 checksum' >&2
    exit 1
fi
[ ! -e "$BAD_DESTINATION" ] || {
    echo 'FAIL: checksum failure created the destination' >&2
    exit 1
}

echo 'PASS: installer checksum, safe destination, update, and data-preservation checks'
