#!/usr/bin/env bash
# 회차용 인증코드 생성 (운영자용, 참가자와 무관)
#
# 숫자 6자리. 진행자가 구두로 불러주고 참가자가 손으로 입력하는 값이라
# 짧고 받아적기 쉬운 쪽을 택했다. 날짜를 그대로 쓰지 않는 것이 핵심이고,
# 무작위이기만 하면 추측 경로는 닫힌다.
set -euo pipefail

ALPHABET="0123456789"
LEN=${1:-6}

code=""
while [ "${#code}" -lt "$LEN" ]; do
  # od로 난수 바이트를 읽어 알파벳 길이로 나머지 연산. 편향을 피하기 위해
  # 알파벳 크기의 배수를 넘는 값은 버린다.
  for byte in $(od -An -tu1 -N64 /dev/urandom); do
    if [ "$byte" -lt 248 ]; then
      idx=$(( byte % ${#ALPHABET} ))
      code="${code}${ALPHABET:$idx:1}"
      [ "${#code}" -ge "$LEN" ] && break
    fi
  done
done

echo "$code"
