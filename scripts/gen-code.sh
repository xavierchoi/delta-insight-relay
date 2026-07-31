#!/usr/bin/env bash
# 회차용 인증코드 생성 (운영자용, 참가자와 무관)
#
# 헷갈리기 쉬운 글자(0/O, 1/I/L)를 뺀 알파벳을 쓴다. 참가자가 구두로 듣고 손으로
# 입력하는 값이라, 엔트로피를 조금 줄이더라도 잘못 받아적는 쪽을 막는 게 낫다.
# 남은 31글자 6자리 = 약 8.9억 조합으로, 추측 방어에는 충분하다.
set -euo pipefail

ALPHABET="23456789ABCDEFGHJKMNPQRSTUVWXYZ"
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
