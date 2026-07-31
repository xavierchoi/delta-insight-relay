#!/usr/bin/env bash
# Delta Society 인사이트 제출 스크립트
# 사용법: upload.sh <code> <participant_name> <team> <session_title>
#         upload.sh --check                (환경 점검만, 제출하지 않음)
#
# --check는 회차 '시작' 시점에 돌리기 위한 것이다. 제출은 회차가 끝난 뒤에 일어나는데,
# 그때 환경 문제로 실패하면 고칠 시간이 없고 기록도 사라진다. 실패를 앞으로 당긴다.
set -uo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
  CODE=""; PARTICIPANT=""; TEAM=""; TITLE=""
elif [ "$#" -ne 4 ]; then
  echo "사용법: upload.sh <code> <participant_name> <team> <session_title>" >&2
  echo "        upload.sh --check" >&2
  exit 1
else
  CODE="$1"
  PARTICIPANT="$2"
  TEAM="$3"
  TITLE="$4"
fi

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  echo "오류: CLAUDE_CODE_SESSION_ID 환경변수를 찾을 수 없습니다. Claude Code 세션 안에서 실행해주세요." >&2
  exit 1
fi

# 트랜스크립트는 ~/.claude/projects/<슬러그화된-cwd>/<session-id>.jsonl 에 있다.
# 슬러그 규칙(어떤 문자가 '-'로 바뀌는지)은 Claude Code 내부 구현이라 버전에 따라 달라질 수 있으므로,
# 규칙으로 먼저 시도한 뒤 실패하면 session-id 파일명으로 직접 찾는다. session-id는 전역 유일하다.
SLUG=$(pwd | sed 's/[\/.]/-/g')
TRANSCRIPT="$HOME/.claude/projects/$SLUG/$CLAUDE_CODE_SESSION_ID.jsonl"

if [ ! -f "$TRANSCRIPT" ]; then
  TRANSCRIPT=$(find "$HOME/.claude/projects" -name "$CLAUDE_CODE_SESSION_ID.jsonl" -type f 2>/dev/null | head -n1)
fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "오류: 세션 트랜스크립트를 찾을 수 없습니다 (session id: $CLAUDE_CODE_SESSION_ID)" >&2
  exit 1
fi

# 회차 중 Claude Code를 재시작하면 세션 ID가 바뀌어 트랜스크립트가 여러 개로 쪼개진다.
# 이 스크립트는 현재 세션 것만 보내므로, 앞부분이 조용히 누락된 채 "제출 완료"가 뜬다.
# 같은 프로젝트에서 최근 6시간 내에 수정된 다른 세션 기록이 있으면 알려준다.
# -mmin은 GNU/BSD find 모두 지원한다 (-newermt는 그렇지 않다).
TRANSCRIPT_DIR="$(dirname "$TRANSCRIPT")"
OTHER_SESSIONS=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -type f -name '*.jsonl' -mmin -360 \
  ! -name "$CLAUDE_CODE_SESSION_ID.jsonl" 2>/dev/null | wc -l | tr -d '[:space:]')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPOINT="${DELTA_RELAY_ENDPOINT:-$(tr -d '[:space:]' < "$SCRIPT_DIR/../endpoint.txt")}"
TODAY=$(date +%F)

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "제출 환경 점검"
  echo "─────────────────────────────"
  echo "세션 ID     : $CLAUDE_CODE_SESSION_ID"
  echo "기록 파일   : $TRANSCRIPT"
  SIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d '[:space:]')
  echo "현재 크기   : ${SIZE:-?} bytes"
  echo "제출 주소   : $ENDPOINT"
  if [ "${OTHER_SESSIONS:-0}" -gt 0 ]; then
    echo "다른 기록   : ${OTHER_SESSIONS}개 (회차 중 재시작했다면 분할된 것)"
  fi
  echo "─────────────────────────────"

  HEALTH_URL="${ENDPOINT%/upload}/health"
  HEALTH=$(curl -sS --max-time 20 -w "\n%{http_code}" "$HEALTH_URL" 2>&1)
  HEALTH_CODE=$(echo "$HEALTH" | tail -n1)
  if [ "$HEALTH_CODE" = "200" ]; then
    echo "서버 연결   : 정상"
    echo ""
    echo "점검 완료. 회차가 끝나면 제출하실 수 있습니다."
    exit 0
  else
    echo "서버 연결   : 실패"
    echo ""
    echo "서버에 연결하지 못했습니다. 진행자에게 알려주세요." >&2
    exit 1
  fi
fi

# 값 전달에 -F 대신 --form-string을 쓴다. -F는 값이 '@'로 시작하면 파일을 읽으려 하고
# ';'를 파라미터 구분자로 해석한다. 이름이 '@'로 시작하거나 회차 제목에 ';'가 들어가면
# 값이 조용히 잘리거나 제출 자체가 실패한다 — 회차가 끝난 뒤라 복구가 안 되는 종류의 실패다.
RESPONSE=$(curl -sS --max-time 300 -w "\n%{http_code}" -X POST "$ENDPOINT" \
  --form-string "code=$CODE" \
  --form-string "participant_name=$PARTICIPANT" \
  --form-string "team=$TEAM" \
  --form-string "session_title=$TITLE" \
  --form-string "date=$TODAY" \
  -F "file=@$TRANSCRIPT;type=application/jsonl")
CURL_EXIT=$?

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# 연결 자체가 안 되면 HTTP_CODE가 000이고 본문이 비어, 참가자는 아무 단서도 못 받는다.
if [ "$CURL_EXIT" -eq 28 ]; then
  echo "제출 실패: 시간이 초과됐습니다. 네트워크를 확인한 뒤 다시 시도하거나 진행자에게 알려주세요." >&2
  exit 1
elif [ "$CURL_EXIT" -ne 0 ] || [ "$HTTP_CODE" = "000" ]; then
  echo "제출 실패: 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하거나 진행자에게 알려주세요." >&2
  exit 1
fi

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "제출 완료: $BODY"
  if [ "${OTHER_SESSIONS:-0}" -gt 0 ]; then
    echo ""
    echo "참고: 이 프로젝트에 최근 다른 세션 기록이 ${OTHER_SESSIONS}개 더 있습니다."
    echo "회차 중 Claude Code를 재시작하셨다면 앞부분이 이번 제출에 포함되지 않았습니다."
    echo "해당된다면 진행자에게 알려주세요."
  fi
  exit 0
elif [ "$HTTP_CODE" = "401" ]; then
  echo "제출 실패: 인증코드가 맞지 않습니다. 진행자가 알려준 숫자 6자리를 다시 확인해주세요." >&2
  exit 1
else
  echo "제출 실패 (HTTP $HTTP_CODE): $BODY" >&2
  exit 1
fi
