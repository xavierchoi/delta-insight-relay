const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const app = express();

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
// SESSION_CODES가 깨진 JSON이면 여기서 던져 프로세스가 죽고, Railway는 크래시 루프에 빠진다.
// 회차 당일 오타 하나로 전원이 제출 불가가 되는 것보다, 빈 맵으로 뜬 채 /health가 이를 드러내는 편이 낫다.
let CODES_MAP = {};
try {
  CODES_MAP = JSON.parse(process.env.SESSION_CODES || '{}');
} catch (err) {
  console.error('SESSION_CODES 파싱 실패 — 빈 맵으로 기동합니다:', err.message);
}

// 업로드 임시파일을 DATA_DIR 안에 두는 것이 중요하다. os.tmpdir()에 두면 컨테이너 파일시스템에
// 떨어지는데, 저장 대상인 DATA_DIR이 마운트된 볼륨이면 서로 다른 디바이스가 되어
// rename이 EXDEV로 실패한다. 같은 디바이스에 두면 rename이 원자적으로 동작한다.
const TMP_DIR = path.join(DATA_DIR, 'tmp');
fs.mkdirSync(TMP_DIR, { recursive: true });

const upload = multer({ dest: TMP_DIR, limits: { fileSize: 200 * 1024 * 1024 } });

// TMPDIR 설정이 어긋나 임시파일이 다른 디바이스에 생기더라도 업로드가 죽지 않도록,
// EXDEV일 때는 복사 후 삭제로 폴백한다.
function moveFile(from, to) {
  try {
    fs.renameSync(from, to);
  } catch (err) {
    if (err.code !== 'EXDEV') throw err;
    fs.copyFileSync(from, to);
    fs.unlinkSync(from);
  }
}

function slugify(str) {
  return (
    String(str)
      // macOS 파일시스템·일부 입력기는 한글을 자모 분리(NFD) 형태로 넘긴다. 정규화하지 않으면
      // '김철수'가 가-힣 범위에 걸리지 않아 통째로 지워지고 'unknown'이 된다.
      .normalize('NFC')
      .trim()
      .replace(/\s+/g, '-')
      .replace(/[^\w\-가-힣]/g, '')
      .slice(0, 60) || 'unknown'
  );
}

// 인증코드가 고객사를 가리키는 유일한 키다. 코드를 모르면 업로드 자체가 불가능하므로,
// 매핑에 없는 코드는 조용히 무시하지 않고 null을 반환해 401로 거부한다.
//
// 재전송은 덮어쓰지 않고 -2, -3 접미사를 붙여 모두 보존한다. 교육 회차 분석이 목적이라
// "참가자가 두 번 보냈다"는 사실 자체도 신호가 될 수 있고, 실수로 덮어써서 원본을 잃는 것보다
// 파일이 몇 개 늘어나는 편이 회복 가능하다.
function resolveUpload(code, meta) {
  const clientName = CODES_MAP[code];
  if (!clientName) return null;

  // date는 클라이언트가 보내는 값이라 그대로 경로에 넣으면 ../로 DATA_DIR을 벗어날 수 있다.
  // 형식을 강제하고, 어긋나면 서버 수신일로 대체한다. 다른 필드는 slugify가 경로 문자를 지운다.
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(meta.date || ''))
    ? meta.date
    : new Date().toISOString().slice(0, 10);

  const base = [
    date,
    slugify(meta.sessionTitle),
    slugify(meta.team),
    slugify(meta.participantName),
  ].join('_');

  const dir = slugify(clientName);
  let relativePath = path.join(dir, `${base}.jsonl`);
  let n = 1;
  while (fs.existsSync(path.join(DATA_DIR, relativePath))) {
    n += 1;
    relativePath = path.join(dir, `${base}-${n}.jsonl`);
  }

  return { clientName, relativePath };
}

app.post('/upload', upload.single('file'), (req, res) => {
  const {
    code,
    participant_name: participantName,
    team,
    session_title: sessionTitle,
    date,
  } = req.body;

  if (!code || !participantName || !sessionTitle || !req.file) {
    if (req.file) fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'missing required fields' });
  }

  // team은 1.2.0에서 추가된 필드다. 구버전 플러그인을 쓰는 참가자를 400으로 떨어뜨리면
  // 회차가 끝난 뒤에야 실패를 알게 되고 기록은 영영 사라진다. 받아서 저장하되 표시를 남긴다.
  const effectiveTeam = team || '팀미상';
  const legacyClient = !team;

  const resolved = resolveUpload(code, {
    participantName,
    team: effectiveTeam,
    sessionTitle,
    date,
  });

  if (!resolved) {
    fs.unlinkSync(req.file.path);
    return res.status(401).json({ error: 'invalid code' });
  }

  const fullPath = path.join(DATA_DIR, resolved.relativePath);
  fs.mkdirSync(path.dirname(fullPath), { recursive: true });
  moveFile(req.file.path, fullPath);
  fs.writeFileSync(
    `${fullPath}.meta.json`,
    JSON.stringify(
      {
        clientName: resolved.clientName,
        participantName,
        team: effectiveTeam,
        legacyClient,
        sessionTitle,
        date,
        receivedAt: new Date().toISOString(),
      },
      null,
      2
    )
  );

  // upload.sh가 응답 본문을 그대로 출력하므로, 이 warning은 참가자 화면에 바로 보인다.
  const body = { ok: true, path: resolved.relativePath };
  if (legacyClient) {
    body.warning = '구버전 플러그인입니다. 제출은 됐지만 팀 정보가 빠졌습니다. 진행자에게 알려주세요.';
  }
  res.json(body);
});

// codesLoaded를 함께 노출한다. 이게 없으면 "설정 누락"과 "참가자 오타"가 똑같이 401로 보여
// 회차 중에 원인을 가릴 수 없다.
app.get('/health', (req, res) => res.json({ ok: true, codesLoaded: Object.keys(CODES_MAP).length }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`delta-insight-relay listening on ${PORT}`));
