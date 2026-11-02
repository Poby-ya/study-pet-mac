#!/bin/bash
# 공부 친구 — Mac 설치 (한 줄 설치). 같은 줄을 다시 붙여 넣으면 업데이트됩니다.
#
#   /bin/bash -c "$(curl -fsSL https://github.com/Poby-ya/study-pet-releases/releases/latest/download/install-mac.sh)"
#
# 터미널이 곧바로 받아서 설치하므로 인터넷에서 받은 파일에 붙는 격리 표시가 생기지 않고,
# 그래서 "확인되지 않은 개발자" 경고 없이 열립니다 (PDF 필기와 같은 방식).
# LF 줄바꿈이어야 합니다. CRLF면 macOS의 bash가 줄 끝의 \r까지 명령으로 읽습니다.
set -euo pipefail

CHANNEL="${STUDYPET_CHANNEL:-https://github.com/Poby-ya/study-pet-releases/releases/latest/download}"
APPS_DIR="$HOME/Applications"
APP="$APPS_DIR/StudyPet.app"
WORK="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf -- "$WORK"' EXIT

title() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
fail() {
  printf '\n\033[31m  설치하지 못했습니다: %s\033[0m\n' "$*" >&2
  printf '\033[31m  이 터미널 창을 캡처해서 보내 주세요.\033[0m\n' >&2
  exit 1
}
fetch() { /usr/bin/curl --fail --location --silent --show-error --connect-timeout 20 --max-time 600 --output "$2" "$1"; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail '이 설치 명령은 Mac 전용입니다.'
major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
[[ "$major" -ge 13 ]] || fail "macOS 13(Ventura) 이상이 필요합니다. 지금은 $(/usr/bin/sw_vers -productVersion)입니다."

title '공부 친구를 받는 중…'
fetch "$CHANNEL/StudyPet-mac.zip" "$WORK/StudyPet-mac.zip" || fail '파일을 받지 못했습니다. 인터넷 연결을 확인해 주세요.'
fetch "$CHANNEL/StudyPet-mac.zip.sha256" "$WORK/expected" || fail '확인용 파일을 받지 못했습니다.'
[[ "$(/usr/bin/shasum -a 256 "$WORK/StudyPet-mac.zip" | /usr/bin/awk '{print $1}')" == "$(/usr/bin/tr -d '[:space:]' < "$WORK/expected")" ]] \
  || fail '받은 파일이 손상되었습니다. 잠시 뒤 다시 시도해 주세요.'
/usr/bin/ditto -x -k "$WORK/StudyPet-mac.zip" "$WORK/unpacked" || fail '압축을 풀지 못했습니다.'
[[ -x "$WORK/unpacked/StudyPet.app/Contents/MacOS/StudyPet" ]] || fail '받은 파일에 앱이 없습니다.'

# Already running (an update): quit it first; quitting saves the open study segment.
if /usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet"; then
  note '실행 중인 공부 친구를 닫습니다. 공부하던 시간은 저장됩니다.'
  # SIGTERM, which the app turns into a normal quit; AppleScript would ask for permission.
  /usr/bin/pkill -TERM -f "$APP/Contents/MacOS/StudyPet" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -qf "$APP/Contents/MacOS/StudyPet" || break
    /bin/sleep 0.5
  done
fi

title '설치하는 중…'
/bin/mkdir -p "$APPS_DIR"
/bin/rm -rf -- "$APP"
/usr/bin/ditto "$WORK/unpacked/StudyPet.app" "$APP" || fail "$APPS_DIR 에 넣지 못했습니다."
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/usr/bin/open "$APP" || fail '앱을 열지 못했습니다.'

title '설치했어요!'
note '화면 맨 위 오른쪽 메뉴 막대에 펫 얼굴이 생겼어요. 눌러서 메뉴를 열어요.'
note '⌃ control + ⌥ option + S : 공부 시작 / 일시정지'
note '⌃ control + ⌥ option + X : 그만하기'
note '친구 방에 들어가려면: 펫 얼굴 → 친구와 공부하기 → 초대 코드 넣기'
note '업데이트할 때도 같은 한 줄을 다시 붙여 넣으면 돼요. 이 창은 닫아도 됩니다.'
