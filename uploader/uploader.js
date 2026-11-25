// 회사 PC에서 실행: MES(MS SQL) 값을 30초마다 읽어(읽기 전용) Supabase machines_live 로 올림.
// 설정은 같은 폴더 .env (KEY=값 한 줄씩). MES 접속정보를 비워두면 MES 프로그램 설정파일(MES_CONFIG)의 접속 문자열을 그대로 씀.
//   MES_CONFIG=C:\SWIT\SUNGWOO_MES\SUNGWOO.MES.Launcher.exe.config   (또는 MES_SERVER MES_PORT MES_DB MES_USER MES_PW)
//   MES_PLANT=3공장 PLANT_CODE   SB_URL=https://...supabase.co   SB_SERVICE_KEY=(service_role 키, 이 PC에만)   POLL_SEC=30
// SB_SERVICE_KEY 가 없거나 `node uploader.js --dry` 이면 올리지 않고 조회 결과만 출력(시험용).
const sql = require('mssql'), fs = require('fs'), path = require('path');
const envFile = path.join(__dirname, '.env');
if (fs.existsSync(envFile)) for (const l of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
  const m = l.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/); if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}
const E = process.env, POLL = +(E.POLL_SEC || 30) * 1000, DRY = process.argv.includes('--dry') || !E.SB_SERVICE_KEY;
const MES_SQL = fs.readFileSync(path.join(__dirname, 'mes.sql'), 'utf8');

function mesConfig() {
  if (E.MES_SERVER) return { server: E.MES_SERVER, port: +E.MES_PORT || 1433, database: E.MES_DB, user: E.MES_USER, password: E.MES_PW };
  const xml = fs.readFileSync(E.MES_CONFIG || 'C:\\SWIT\\SUNGWOO_MES\\SUNGWOO.MES.Launcher.exe.config', 'utf8');
  const cs = (xml.match(/connectionString\s*=\s*"([^"]+)"/i) || [])[1]; if (!cs) throw new Error('MES 설정파일에서 접속 문자열을 못 찾음');
  const kv = Object.fromEntries(cs.split(';').filter(Boolean).map(p => { const i = p.indexOf('='); return [p.slice(0, i).trim().toLowerCase(), p.slice(i + 1).trim()]; }));
  const [host, port] = (kv['data source'] || kv.server || '').split(',');
  return { server: host, port: +port || 1433, database: kv['initial catalog'] || kv.database, user: kv['user id'] || kv.uid, password: kv.password || kv.pwd };
}

let pool;
async function tick() {
  try {
    pool = pool || await sql.connect({ ...mesConfig(), options: { encrypt: false, trustServerCertificate: true }, requestTimeout: 15000 });
    const rows = (await pool.request().input('PLANT', E.MES_PLANT).query(MES_SQL)).recordset
      .filter(r => r.no).map(r => ({ ...r, no: +r.no, updated_at: new Date().toISOString() }));
    if (DRY) { console.table(rows.map(({ no, status, part, mold, prod, ng, ct, std_ct }) => ({ no, status, part, mold, prod, ng, ct, std_ct }))); if (process.argv.includes('--dry')) process.exit(0); return; }
    const res = await fetch(`${E.SB_URL}/rest/v1/machines_live?on_conflict=no`, { method: 'POST',
      headers: { apikey: E.SB_SERVICE_KEY, Authorization: `Bearer ${E.SB_SERVICE_KEY}`, 'content-type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows) });
    console.log(new Date().toLocaleTimeString(), res.ok ? `올림 ${rows.length}대` : `실패 ${res.status} ${await res.text()}`);
  } catch (e) { console.error(new Date().toLocaleTimeString(), '오류', e.message); pool = null; if (process.argv.includes('--dry')) process.exit(1); }
}
tick(); if (!process.argv.includes('--dry')) setInterval(tick, POLL);
