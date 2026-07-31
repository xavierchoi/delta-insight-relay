# delta-insight-relay

Delta Society의 Claude Code 교육 회차가 끝날 때, 참가자가 한 마디로 오늘의 학습 기록을 교육팀에 제출하는 얇은 플러그인 + 수신 서버.

참가자가 말로 표현하지 못한 막힘, 페어코딩 중 진행자가 눈으로 놓친 지점을 세션 기록으로 되짚어 다음 회차를 개선하는 것이 목적이다.

## 무엇이 제출되는가

**해당 세션의 대화 기록 원본 전체**(Claude Code가 남기는 `.jsonl` 트랜스크립트)가 그대로 전달된다.
요약하거나 가공하지 않는다 — 진행자가 놓친 지점을 찾는 것이 목적이므로 가공이 오히려 목적을 훼손한다.

즉 그 세션에서 주고받은 대화, 실행한 명령, 그 결과가 모두 포함된다.
제출은 참가자가 직접 명령했을 때만 일어나며, 자동으로 수집하지 않는다.

## 참가자 사용법

1. 플러그인 설치 (교육 시작 시 1회):
   ```
   /plugin marketplace add https://github.com/xavierchoi/delta-insight-relay.git
   /plugin install delta-insight-relay
   ```
   `owner/repo` 축약형은 SSH로 클론을 시도하므로, GitHub SSH 키가 없는 PC에서는 실패할 수 있다.
   위처럼 **HTTPS URL 전체**를 쓴다.

2. 회차가 끝나면 세션에서 이렇게 말한다:
   ```
   오늘 인사이트 제출해줘
   ```
   Claude가 인증코드 · 이름 · 팀 소속 · 회차 제목을 물어보고 제출까지 처리한다.
   날짜와 기록 파일 위치는 자동으로 채워진다. 인증코드는 진행자가 알려준다.

3. 업데이트가 필요하다는 안내를 받으면:
   ```
   /plugin marketplace update delta-insight-relay-marketplace
   ```
   재설치(`/plugin install`)는 "이미 설치됨"으로 넘어가므로, `marketplace update`가 실제 갱신 경로다.

## 구성

| 경로 | 역할 |
|------|------|
| `.claude-plugin/` | 마켓플레이스 / 플러그인 메타데이터 |
| `skills/submit-insight/` | 참가자가 실행하는 스킬 (인터뷰 → 제출) |
| `skills/submit-insight/endpoint.txt` | 제출 목적지 URL |
| `scripts/gen-code.sh` | 회차 인증코드 생성 (운영자용) |
| `server/` | 수신 서버 (Express) |

## 서버 배포 (Railway)

1. New Project → Deploy from GitHub repo → 이 레포 선택
2. **Settings → Root Directory**: `server`
3. **Settings → Volumes**: 볼륨을 추가하고 마운트 경로를 `/data`로 지정
   (볼륨 없이 배포하면 재시작마다 수집한 기록이 사라진다)
4. **Variables**:
   | 변수 | 값 |
   |------|-----|
   | `DATA_DIR` | `/data` |
   | `SESSION_CODES` | `{"<인증코드>":"<고객사 식별자>"}` |
5. **Settings → Networking → Generate Domain** 으로 공개 URL 발급
   Generate Domain은 타깃 포트를 3000으로 잡는 경우가 있는데, Railway는 `PORT=8080`을 주입한다.
   502가 나면 도메인의 타깃 포트를 **8080**으로 고친다.
6. 발급된 URL을 `skills/submit-insight/endpoint.txt`에 `https://<도메인>/upload` 형태로 반영하고 커밋·푸시.
   참가자는 이 파일로 목적지를 알게 되므로, 이 커밋 전에 설치한 참가자는 갱신이 필요하다.
   **이미 배포된 뒤에는 도메인을 바꾸지 않는다** — 설치된 플러그인이 전부 깨진다.

> 서버는 업로드 임시파일을 `$DATA_DIR/tmp`에 만든다. 저장 대상과 같은 볼륨이어야 rename이
> EXDEV로 실패하지 않기 때문이다. 별도의 `TMPDIR` 지정이나 커스텀 start command는 필요 없다.

배포 상태 확인:

```
GET /health → {"ok":true,"codesLoaded":<설정된 코드 수>}
```

`codesLoaded`가 0이면 `SESSION_CODES`가 비었거나 JSON이 깨진 것이다.
이 값이 없으면 "설정 누락"과 "참가자 오타"가 똑같이 401로 보여 회차 중에 원인을 가릴 수 없다.

## 운영 값은 이 레포에 두지 않는다

인증코드, 고객사 식별자, 계약 조건은 **어떤 형태로도 이 레포에 커밋하지 않는다.**
공개 레포이므로 한번 커밋되면 파일을 지워도 히스토리에서 계속 읽힌다.
예시가 필요하면 이 문서처럼 플레이스홀더를 쓴다.

### 플러그인 수정 시 반드시 버전을 올릴 것

플러그인 캐시는 **버전 번호로 키를 잡는다.** `plugin.json`과 `.claude-plugin/marketplace.json`의
`version`을 **둘 다** 올리지 않으면, 마켓플레이스를 갱신해도 참가자에게 변경이 전달되지 않는다.

### 인증코드 운영

`SESSION_CODES`는 `{"인증코드": "고객사 식별자"}` 매핑이다. 매핑에 없는 코드는 401로 거부된다.
회차마다 새 코드를 발급하고, 진행자가 참가자에게 **구두로만** 알려준다.

```bash
bash scripts/gen-code.sh        # 숫자 6자리
```

날짜를 그대로 코드로 쓰지 않는다. 업로드 URL이 이 공개 레포에 담겨 있어 주소는 이미 알려진 값이고,
접근 통제가 코드 하나에 걸려 있기 때문이다. 날짜형 코드는 레포를 본 사람이 추측할 수 있다.

**고객사 식별자(매핑의 값)는 `slugify`되어 저장 디렉터리명이 된다.** 나중에 바꾸면 이미 쌓인 폴더와
갈라지므로, 고객사별로 한 번 정한 문자열을 계속 쓴다. 셸·URL을 거칠 때 인코딩 문제를 줄이기 위해
소문자 ASCII를 쓴다.

프로그램이 끝나면 `SESSION_CODES`를 `{}`로 되돌린다. 서비스를 지우지 않고도 엔드포인트가 즉시 무력화된다.

## 저장 결과

```
/data/
└── <고객사 식별자>/
    ├── 2026-07-31_회차제목_팀이름_참가자이름.jsonl
    └── 2026-07-31_회차제목_팀이름_참가자이름.jsonl.meta.json
```

같은 참가자가 같은 회차를 다시 제출하면 덮어쓰지 않고 `-2`, `-3` 접미사를 붙여 모두 보존한다.

구버전 플러그인이 팀 정보 없이 제출하면 400으로 거부하지 않고 `팀미상`으로 저장한 뒤 경고를 반환한다.
회차가 끝난 뒤에야 실패를 알게 되면 기록이 영영 사라지기 때문이다.

## 로컬 테스트

```bash
cd server && npm install
DATA_DIR=./data SESSION_CODES='{"111111":"testclient"}' PORT=38642 npm start

# 다른 터미널 (Claude Code 세션 안에서)
DELTA_RELAY_ENDPOINT=http://127.0.0.1:38642/upload \
  bash skills/submit-insight/scripts/upload.sh "111111" "이름" "팀 소속" "회차 제목"
```

`DELTA_RELAY_ENDPOINT` 환경변수는 `endpoint.txt`를 덮어쓴다 — 테스트 전용이다.
