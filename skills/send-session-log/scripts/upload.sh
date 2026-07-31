#!/usr/bin/env bash
# Delta Society 세션 로그 업로드 스크립트
# 사용법: upload.sh <code> <participant_name> <session_title> <round>
set -uo pipefail

if [ "$#" -ne 4 ]; then
  echo "사용법: upload.sh <code> <participant_name> <session_title> <round>" >&2
  exit 1
fi

CODE="$1"
PARTICIPANT="$2"
TITLE="$3"
ROUND="$4"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPOINT="${DELTA_RELAY_ENDPOINT:-$(tr -d '[:space:]' < "$SCRIPT_DIR/../endpoint.txt")}"
TODAY=$(date +%F)

RESPONSE=$(curl -sS -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -F "code=$CODE" \
  -F "participant_name=$PARTICIPANT" \
  -F "session_title=$TITLE" \
  -F "round=$ROUND" \
  -F "date=$TODAY" \
  -F "file=@$TRANSCRIPT;type=application/jsonl")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "전송 완료: $BODY"
  exit 0
else
  echo "전송 실패 (HTTP $HTTP_CODE): $BODY" >&2
  exit 1
fi
