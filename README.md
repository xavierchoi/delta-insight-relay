# delta-session-relay

Delta Society의 Claude Code 교육 회차가 끝난 뒤, 참가자가 명령 한 번으로 자기 세션 로그를 Delta에 전송하는 얇은 플러그인 + 수신 서버.

교육 회차에서 참가자가 말로 표현하지 못한 막힘, 페어코딩 중 눈으로 놓친 지점을 세션 트랜스크립트로 되짚어 다음 회차를 개선하는 것이 목적이다.

## 구성

| 경로 | 역할 |
|------|------|
| `.claude-plugin/` | 마켓플레이스 / 플러그인 메타데이터 |
| `skills/send-session-log/` | 참가자가 실행하는 스킬 (인터뷰 → 업로드) |
| `skills/send-session-log/endpoint.txt` | 업로드 목적지 URL (배포 후 반드시 수정) |
| `server/` | 수신 서버 (Express, Railway 배포용) |

## 참가자 사용법

1. 플러그인 설치 (교육 시작 시 1회):
   ```
   /plugin marketplace add xavierchoi/delta-session-relay
   /plugin install delta-session-relay
   ```
2. 회차가 끝나면 세션에서 그냥 이렇게 말하면 된다:
   ```
   세션 로그 보내줘
   ```
   Claude가 인증코드 · 이름 · 회차 제목 · 회차 번호를 물어보고 전송까지 처리한다. 날짜와 트랜스크립트 파일 위치는 자동으로 채워진다.

## 서버 배포 (Railway)

1. Railway에서 New Project → Deploy from GitHub repo → 이 레포 선택
2. **Settings → Root Directory**: `server`
3. **Settings → Volumes**: 볼륨을 추가하고 마운트 경로를 `/data`로 지정
   (볼륨 없이 배포하면 재시작마다 수집한 로그가 사라진다)
4. **Variables**:
   | 변수 | 값 |
   |------|-----|
   | `DATA_DIR` | `/data` |
   | `SESSION_CODES` | `{"1234":"고객사A","5678":"고객사B"}` |
5. **Settings → Networking → Generate Domain** 으로 공개 URL 발급
   Generate Domain은 타깃 포트를 3000으로 잡는 경우가 있는데, Railway는 `PORT=8080`을 주입한다.
   502가 나면 도메인의 타깃 포트를 **8080**으로 고친다.
6. 발급된 URL을 `skills/send-session-log/endpoint.txt`에 `https://<도메인>/upload` 형태로 반영하고 커밋·푸시
   (참가자는 이 파일을 통해 목적지를 알게 되므로, 이 커밋 전에 설치한 참가자는 재설치가 필요하다)

> 서버는 업로드 임시파일을 `$DATA_DIR/tmp`에 만든다. 저장 대상과 같은 볼륨이어야 rename이
> EXDEV로 실패하지 않기 때문이다. 별도의 `TMPDIR` 지정이나 커스텀 start command는 필요 없다.

### 인증코드 운영

`SESSION_CODES`는 `{"인증코드": "고객사명"}` 매핑이다. 인증코드가 고객사를 가리키는 유일한 키이므로, 회차마다 새 코드를 발급하고 진행자가 참가자에게 구두로 알려주는 방식으로 운영한다. 매핑에 없는 코드는 401로 거부된다.

## 저장 결과

```
/data/
└── 고객사A/
    ├── 2026-07-30_r1_Claude-Code-기초_최훈민.jsonl
    └── 2026-07-30_r1_Claude-Code-기초_최훈민.meta.json
```

같은 참가자가 같은 회차를 다시 전송하면 덮어쓰지 않고 `-2`, `-3` 접미사를 붙여 모두 보존한다.

## 로컬 테스트

```bash
cd server && npm install
DATA_DIR=./data SESSION_CODES='{"1234":"테스트고객사"}' PORT=38642 npm start

# 다른 터미널 (Claude Code 세션 안에서)
DELTA_RELAY_ENDPOINT=http://127.0.0.1:38642/upload \
  bash skills/send-session-log/scripts/upload.sh "1234" "이름" "회차 제목" "1"
```

`DELTA_RELAY_ENDPOINT` 환경변수는 `endpoint.txt`를 덮어쓴다 — 테스트 전용이다.
