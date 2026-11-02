#!/bin/bash
# Integration test on the disposable CI account, never on a person's Mac.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'CI only'; exit 2; }
APP="$HOME/Applications/StudyPet.app"
ZIP="$PWD/mac/build/StudyPet-mac.zip"
HASH="$(tr -d '[:space:]' < mac/build/StudyPet-mac.zip.sha256)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DATA="$HOME/Library/Application Support/StudyPet"
mkdir -p "$DATA"
for mode in studying paused; do
  printf 'updateResume={"state":"%s","subject":"updater-fixture","seconds":1234.5}\n' "$mode" > "$DATA/settings.txt"
  open "$APP"
  sleep 2
  before="$(pgrep -f "$APP/Contents/MacOS/StudyPet")"
  test -n "$before"
  if [[ "$mode" == studying ]]; then test -f "$DATA/open.txt"; else test ! -f "$DATA/open.txt"; fi
  ! grep -q 'updateResume={' "$DATA/settings.txt"
  bash mac/install-mac.sh --prepare-update "$ZIP" "$HASH" "$APP" "$VERSION"
  # Mirror the button's session handoff after saving the active segment.
  kill -TERM "$before"
  for _ in {1..20}; do kill -0 "$before" 2>/dev/null || break; sleep 0.2; done
  printf 'updateResume={"state":"%s","subject":"updater-fixture","seconds":1234.5}\n' "$mode" > "$DATA/settings.txt"
  bash mac/install-mac.sh --apply-update "$ZIP" "$HASH" "$APP" "$before" "$DATA/update-error.txt"
  after="$(pgrep -f "$APP/Contents/MacOS/StudyPet")"
  test -n "$after" && test "$before" != "$after"
  if [[ "$mode" == studying ]]; then test -f "$DATA/open.txt"; else test ! -f "$DATA/open.txt"; fi
  ! grep -q 'updateResume={' "$DATA/settings.txt"
  kill -TERM "$after"
  sleep 2
done
# A damaged download must be refused before the installed bundle or process changes.
open "$APP"
sleep 2
before="$(pgrep -f "$APP/Contents/MacOS/StudyPet")"
if bash mac/install-mac.sh --prepare-update "$ZIP" "$(printf '%064d' 0)" "$APP" "$VERSION"; then exit 1; fi
test "$(pgrep -f "$APP/Contents/MacOS/StudyPet")" = "$before"
# A bundle that cannot start rolls back and reopens the previous working app.
bash mac/install-mac.sh --prepare-update "$ZIP" "$HASH" "$APP" "$VERSION"
next="$APP.update-${HASH:0:16}.app"
printf 'int main(void) { return 7; }\n' | clang -x c - -o "$next/Contents/MacOS/StudyPet"
codesign --force --sign - "$next"
kill -TERM "$before"
sleep 2
if bash mac/install-mac.sh --apply-update "$ZIP" "$HASH" "$APP" "$before" "$DATA/update-error.txt"; then echo 'broken app was accepted'; exit 1; fi
sleep 2
pgrep -f "$APP/Contents/MacOS/StudyPet"
codesign --verify --strict "$APP"
test "$(shasum -a 256 "$APP/Contents/MacOS/StudyPet" | awk '{print $1}')" = "$(shasum -a 256 mac/build/StudyPet.app/Contents/MacOS/StudyPet | awk '{print $1}')"
pkill -TERM -f "$APP/Contents/MacOS/StudyPet"
echo 'PASS: update handoff, studying/paused restoration, damaged download, rollback and restart'
