const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const app = express();

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const CODES_MAP = JSON.parse(process.env.SESSION_CODES || '{}');

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

  const base = [
    meta.date,
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

  if (!code || !participantName || !team || !sessionTitle || !req.file) {
    if (req.file) fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'missing required fields' });
  }

  const resolved = resolveUpload(code, { participantName, team, sessionTitle, date });

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
        team,
        sessionTitle,
        date,
        receivedAt: new Date().toISOString(),
      },
      null,
      2
    )
  );

  res.json({ ok: true, path: resolved.relativePath });
});

app.get('/health', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`delta-insight-relay listening on ${PORT}`));
