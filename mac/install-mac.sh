#!/bin/bash
# 공부 친구 설치. 앱 안에서는 같은 도우미가 검증된 파일을 설치하고 재실행합니다.
set -euo pipefail
CHANNEL="${STUDYPET_CHANNEL:-https://github.com/Poby-ya/study-pet-releases/releases/latest/download}"
APP="$HOME/Applications/StudyPet.app"
WORK="$(/usr/bin/mktemp -d)"
MODE=manual
NEXT=""
BACKUP=""
OLD_PID=""
ERROR_FILE=""
REPLACED=0
REASON='설치를 완료하지 못했어요. 설정에서 다시 시도해 주세요.'

title() { printf '\n%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
fail() { REASON="$*"; printf '\n설치하지 못했습니다: %s\n' "$*" >&2; exit 1; }
fetch() { /usr/bin/curl --fail --location --silent --show-error --connect-timeout 20 --max-time 600 --output "$2" "$1"; }
cleanup() {
  result=$?
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then
    if [[ "$REPLACED" == 1 && -d "$BACKUP" ]]; then
      /bin/rm -rf -- "$APP"
      /bin/mv -- "$BACKUP" "$APP" || true
    fi
    if [[ "$MODE" == apply ]]; then
      printf '%s\n' "$REASON" > "$ERROR_FILE" || true
      if ! /bin/kill -0 "$OLD_PID" 2>/dev/null; then /usr/bin/open "$APP" || true; fi
    fi
  fi
  if [[ "$MODE" != prepare || "$result" -ne 0 ]]; then
    [[ -z "$NEXT" || ! -d "$NEXT" ]] || /bin/rm -rf -- "$NEXT"
  fi
  /bin/rm -rf -- "$WORK"
  exit "$result"
}
trap cleanup EXIT

[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail '이 설치 명령은 Mac 전용입니다.'
major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
[[ "$major" -ge 13 ]] || fail 'macOS 13(Ventura) 이상이 필요합니다.'

if [[ "${1:-}" == --prepare-update || "${1:-}" == --apply-update ]]; then
  [[ "$#" -ge 5 ]] || fail '업데이트 인수가 올바르지 않아요.'
  ZIP="$2"
  HASH="$3"
  APP="$4"
  [[ "$APP" == /*/StudyPet.app && ! -L "$APP" && "$ZIP" == /* && "$HASH" =~ ^[a-fA-F0-9]{64}$ ]] || fail '업데이트 경로가 올바르지 않아요.'
  NEXT="$APP.update-${HASH:0:16}.app"
  if [[ "$1" == --prepare-update ]]; then
    MODE=prepare
    EXPECTED_VERSION="$5"
  else
    [[ "$#" == 6 && "$5" =~ ^[1-9][0-9]*$ && "$6" == /* ]] || fail '업데이트 인수가 올바르지 않아요.'
    MODE=apply
    OLD_PID="$5"
    ERROR_FILE="$6"
    [[ -d "$NEXT" ]] || fail '준비한 업데이트 파일이 없어요. 다시 받아 주세요.'
  fi
  [[ -f "$ZIP" && "$(/usr/bin/shasum -a 256 "$ZIP" | /usr/bin/awk '{print $1}')" == "$HASH" ]] || fail '받은 파일이 손상되었습니다.'
else
  [[ "$#" == 0 ]] || fail '알 수 없는 설치 옵션입니다.'
  title '공부 친구를 받는 중…'
  ZIP="$WORK/StudyPet-mac.zip"
  fetch "$CHANNEL/StudyPet-mac.zip" "$ZIP" || fail '파일을 받지 못했습니다. 인터넷 연결을 확인해 주세요.'
  fetch "$CHANNEL/StudyPet-mac.zip.sha256" "$WORK/expected" || fail '확인용 파일을 받지 못했습니다.'
  HASH="$(/usr/bin/tr -d '[:space:]' < "$WORK/expected")"
  [[ "$HASH" =~ ^[a-fA-F0-9]{64}$ && "$(/usr/bin/shasum -a 256 "$ZIP" | /usr/bin/awk '{print $1}')" == "$HASH" ]] || fail '받은 파일이 손상되었습니다. 잠시 뒤 다시 시도해 주세요.'
  NEXT="$APP.update-${HASH:0:16}.app"
fi

APPS_DIR="$(/usr/bin/dirname "$APP")"
/bin/mkdir -p "$APPS_DIR"
if [[ "$MODE" != apply ]]; then
  /usr/bin/ditto -x -k "$ZIP" "$WORK/unpacked" || fail '압축을 풀지 못했습니다.'
  [[ -x "$WORK/unpacked/StudyPet.app/Contents/MacOS/StudyPet" ]] || fail '받은 파일에 앱이 없습니다.'
  /bin/rm -rf -- "$NEXT"
  /usr/bin/ditto "$WORK/unpacked/StudyPet.app" "$NEXT" || fail '앱 폴더에 쓸 수 없습니다. 읽기 전용 디스크가 아닌 Applications 폴더에 설치해 주세요.'
fi
/usr/bin/codesign --verify --strict "$NEXT" || fail '앱 서명을 확인하지 못했습니다.'
if [[ "$MODE" == prepare ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NEXT/Contents/Info.plist")" == "$EXPECTED_VERSION" ]] || fail '받은 앱의 버전이 맞지 않아요.'
  exit 0
fi

if [[ "$MODE" == apply ]]; then
  # The parent saves the study segment and exits normally. Never force it to quit.
  for _ in {1..120}; do
    /bin/kill -0 "$OLD_PID" 2>/dev/null || break
    /bin/sleep 0.5
  done
  if /bin/kill -0 "$OLD_PID" 2>/dev/null; then fail '앱이 종료되지 않아 업데이트를 중단했어요.'; fi
elif /usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet"; then
  note '실행 중인 공부 친구를 닫습니다. 공부하던 시간은 저장됩니다.'
  /usr/bin/pkill -TERM -f "$APP/Contents/MacOS/StudyPet" || true
  for _ in {1..10}; do
    /usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet" || break
    /bin/sleep 0.5
  done
  if /usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet"; then fail '앱이 아직 종료되지 않았습니다. 메뉴에서 종료한 뒤 다시 시도해 주세요.'; fi
fi

title '설치하는 중…'
BACKUP="$APP.previous-$(/usr/bin/uuidgen).app"
if [[ -d "$APP" ]]; then /bin/mv -- "$APP" "$BACKUP" || fail '기존 앱을 보관하지 못했습니다.'; REPLACED=1; fi
/bin/mv -- "$NEXT" "$APP" || fail '앱을 교체하지 못해 이전 버전을 복원합니다.'
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/usr/bin/open "$APP" || fail '앱을 열지 못해 이전 버전을 복원합니다.'
/bin/sleep 2
/usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet" || fail '새 앱을 실행하지 못해 이전 버전을 복원합니다.'
[[ ! -d "$BACKUP" ]] || /bin/rm -rf -- "$BACKUP"
REPLACED=0
[[ -z "$ERROR_FILE" ]] || /bin/rm -f -- "$ERROR_FILE"
title '설치했어요!'
note '메뉴 막대의 펫 얼굴 → 설정에서 업데이트를 확인할 수 있어요.'
note '⌃ control + ⌥ option + S : 공부 시작 / 일시정지'
note '⌃ control + ⌥ option + X : 그만하기'
