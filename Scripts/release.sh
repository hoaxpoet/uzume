#!/usr/bin/env bash
# release.sh — cut a signed, notarized, stapled Uzume DMG (CLEAN.2.5b, D-261).
#
# One command: verify weights → bump build number (committed, never reused) →
# archive (Release) → Developer ID export → notarize + staple the app → DMG →
# sign + notarize + staple the DMG → self-verify. Output:
#   build/release/Uzume-<version>-<build>.dmg  (+ .sha256)
#   build/release/Uzume-<version>-<build>/     (archive, exported app, logs)
#
# Credentials: notarytool reads the Keychain profile "uzume-notary" (created
# once with `xcrun notarytool store-credentials`, RUNBOOK §Release build).
# This script never reads, prints or stores the secret behind it.
#
# Nothing is published. Uploading the DMG anywhere is a separate decision.
#
# Usage: Scripts/release.sh [--allow-branch]
#   --allow-branch  run from a branch other than main (dry runs).

set -euo pipefail

TEAM_ID="TYK3BXQ5D4"
NOTARY_PROFILE="uzume-notary"
SCHEME="UzumeApp"
APP_NAME="Uzume"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
VERSION_FILE="UzumeApp/Version.xcconfig"
EXPORT_OPTIONS="Scripts/ExportOptions.plist"

step() { printf '\n==> release: %s\n' "$*"; }
die()  { printf '\nrelease: FAILED — %s\n' "$*" >&2; exit 1; }
trap 'printf "release: FAILED — command at line %d exited non-zero\n" "$LINENO" >&2' ERR

ALLOW_BRANCH=0
for arg in "$@"; do
  case "$arg" in
    --allow-branch) ALLOW_BRANCH=1 ;;
    *) die "unknown argument: $arg (usage: Scripts/release.sh [--allow-branch])" ;;
  esac
done

# --- 1. Tree + branch ----------------------------------------------------------
step "1/9 checking tree and branch"
# ponytail: untracked files are ignored — only tracked, pbxproj-registered sources build.
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "working tree has uncommitted changes — commit or discard them first"
BRANCH="$(git symbolic-ref --short -q HEAD || echo DETACHED)"
if [ "$BRANCH" != "main" ] && [ "$ALLOW_BRANCH" -ne 1 ]; then
  die "on '$BRANCH', not main — release from main, or pass --allow-branch for a dry run"
fi
echo "branch: $BRANCH @ $(git rev-parse --short HEAD)"

IDENTITY_LINE="$(security find-identity -v -p codesigning | grep "Developer ID Application:.*($TEAM_ID)" | head -1 || true)"
[ -n "$IDENTITY_LINE" ] || die "no 'Developer ID Application … ($TEAM_ID)' identity in the Keychain"
IDENTITY_HASH="$(awk '{print $2}' <<< "$IDENTITY_LINE")"
IDENTITY_NAME="$(sed -E 's/^[^"]*"(.*)"$/\1/' <<< "$IDENTITY_LINE")"
echo "signing identity: $IDENTITY_NAME"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null \
  || die "notarytool cannot use Keychain profile '$NOTARY_PROFILE' (RUNBOOK §Release build)"

# --- 2. Weights -----------------------------------------------------------------
step "2/9 verifying ML weights"
Scripts/fetch_weights.sh || die "weights missing or failed verification"

# --- 3. Build number -----------------------------------------------------------
step "3/9 bumping build number"
OLD_BUILD="$(sed -nE 's/^CURRENT_PROJECT_VERSION = ([0-9]+)$/\1/p' "$VERSION_FILE")"
VERSION="$(sed -nE 's/^MARKETING_VERSION = ([0-9.]+)$/\1/p' "$VERSION_FILE")"
[ -n "$OLD_BUILD" ] && [ -n "$VERSION" ] || die "cannot read MARKETING_VERSION / CURRENT_PROJECT_VERSION from $VERSION_FILE"
BUILD=$((OLD_BUILD + 1))
sed -i '' -E "s/^CURRENT_PROJECT_VERSION = [0-9]+$/CURRENT_PROJECT_VERSION = $BUILD/" "$VERSION_FILE"
# Committed before archiving so a number is never reused, even if a later step fails.
git commit -q -m "[release] Build: build number $BUILD" -- "$VERSION_FILE" || die "could not commit the build-number bump"
echo "version $VERSION, build $BUILD"

NAME="$APP_NAME-$VERSION-$BUILD"
OUT="build/release/$NAME"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
APP="$OUT/$APP_NAME.app"
DMG="build/release/$NAME.dmg"
rm -rf "$OUT" "$DMG" "$DMG.sha256"
mkdir -p "$OUT"

# --- 4. Archive ----------------------------------------------------------------
step "4/9 archiving (Release) — log: $OUT/archive.log"
xcodebuild -scheme "$SCHEME" -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive > "$OUT/archive.log" 2>&1 \
  || { tail -40 "$OUT/archive.log" >&2; die "xcodebuild archive"; }
echo "archived: $ARCHIVE"

# --- 5. Developer ID export ----------------------------------------------------
step "5/9 exporting with Developer ID — log: $OUT/export.log"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$OUT" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
  || { tail -40 "$OUT/export.log" >&2; die "xcodebuild -exportArchive"; }
[ -d "$APP" ] || die "export produced no $APP"
echo "exported: $APP"

# notarize <file> <label>: submit, wait, print the log's issues on rejection.
notarize() {
  local file="$1" label="$2" result id status
  result="$OUT/notary-$label.json"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json > "$result" || true
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  echo "notarization $label: id=${id:-?} status=${status:-?}"
  if [ "$status" != "Accepted" ]; then
    cat "$result" >&2
    if [ -n "$id" ]; then
      echo "--- notarytool log $id ---" >&2
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    die "notarization of $label was not accepted"
  fi
}

# --- 6. Notarize + staple the app ----------------------------------------------
step "6/9 notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
notarize "$OUT/$APP_NAME.zip" app
rm -f "$OUT/$APP_NAME.zip"
xcrun stapler staple "$APP" || die "stapling the app"

# --- 7. DMG ----------------------------------------------------------------------
step "7/9 building the DMG"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" \
  || die "hdiutil create"
rm -rf "$STAGE"

# --- 8. Sign + notarize + staple the DMG ---------------------------------------
step "8/9 signing and notarizing the DMG"
codesign --sign "$IDENTITY_HASH" --timestamp "$DMG" || die "signing the DMG"
notarize "$DMG" dmg
xcrun stapler staple "$DMG" || die "stapling the DMG"
(cd build/release && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")

# --- 9. Verify -----------------------------------------------------------------
step "9/9 verifying the artifact"
FAILS=0
check() { # check <description> <command...>: run, print output verbatim, record pass/fail
  local desc="$1"; shift
  echo "--- $desc: \$ $*"
  if "$@"; then echo "PASS: $desc"; else echo "FAIL: $desc"; FAILS=$((FAILS + 1)); fi
}
expect() { # expect <description> <haystack> <regex>
  if grep -qE "$3" <<< "$2"; then echo "PASS: $1"; else echo "FAIL: $1 (wanted /$3/)"; FAILS=$((FAILS + 1)); fi
}

check "deep strict signature" codesign --verify --deep --strict --verbose=2 "$APP"

SIG="$(codesign -dv "$APP" 2>&1)"; echo "--- \$ codesign -dv $APP"; echo "$SIG"
expect "Developer ID authority" "$SIG" "^Authority=Developer ID Application: .*\($TEAM_ID\)$"
expect "team identifier" "$SIG" "^TeamIdentifier=$TEAM_ID$"
expect "hardened runtime flag" "$SIG" "flags=0x[0-9a-f]+\(.*runtime.*\)"

ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
echo "--- \$ codesign -d --entitlements - $APP"; codesign -d --entitlements - "$APP" 2>&1
KEYS="$(grep -oE '<key>[^<]+</key>' <<< "$ENT" | sed -E 's/<\/?key>//g' | sort | tr '\n' ' ')"
if [ "$KEYS" = "com.apple.security.app-sandbox com.apple.security.automation.apple-events " ]; then
  echo "PASS: entitlements are exactly app-sandbox + automation.apple-events (no get-task-allow)"
else
  echo "FAIL: unexpected entitlement set: $KEYS"; FAILS=$((FAILS + 1))
fi
expect "app-sandbox is false" "$(tr -d '\n\t ' <<< "$ENT")" "<key>com.apple.security.app-sandbox</key><false/>"

GK="$(spctl -a -vvv -t exec "$APP" 2>&1 || true)"; echo "--- \$ spctl -a -vvv -t exec $APP"; echo "$GK"
expect "Gatekeeper accepts the app as notarized" "$GK" "accepted"
expect "Gatekeeper source" "$GK" "source=Notarized Developer ID"

GKD="$(spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 || true)"
echo "--- \$ spctl -a -vvv -t open --context context:primary-signature $DMG"; echo "$GKD"
expect "Gatekeeper accepts the DMG" "$GKD" "accepted"

check "stapled ticket on the app" xcrun stapler validate "$APP"
check "stapled ticket on the DMG" xcrun stapler validate "$DMG"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"; echo "--- lipo -archs: $ARCHS"
expect "arm64 only" "$ARCHS" "^arm64$"
echo "--- Info.plist:"; plutil -p "$APP/Contents/Info.plist" \
  | grep -E 'CFBundleShortVersionString|CFBundleVersion|LSMinimumSystemVersion|NSHumanReadableCopyright|NSAudioCaptureUsageDescription'

[ "$FAILS" -eq 0 ] || die "$FAILS verification check(s) failed"
printf '\nrelease: OK — %s\n' "$DMG"
cat "$DMG.sha256"
