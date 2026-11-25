// 회사 PC에서 실행: MES(MS SQL) 값을 30초마다 읽어 Supabase로 올림. MES DB는 밖으로 열리지 않음.
// 준비: Node 18+ 설치 → 이 폴더에서 npm i mssql → .env 대신 아래 환경변수 설정 후 node uploader.js
// MES_SERVER MES_PORT MES_DB MES_USER MES_PW MES_PLANT(3공장 코드) SB_URL SB_SERVICE_KEY [POLL_SEC]  조회문은 mes.sql
// MES_SQL 은 컬럼 이름이 no, ton, status, part, mold, cav, std_ct, ct, target, prod, ng, worker, alarm, since 인 SELECT
const sql = require('mssql'), fs = require('fs'), path = require('path');
const MES_SQL = process.env.MES_SQL || fs.readFileSync(path.join(__dirname, 'mes.sql'), 'utf8');
const E = process.env, POLL = +(E.POLL_SEC || 30) * 1000;
let pool;
async function tick() {
  try {
    pool = pool || await sql.connect({ server: E.MES_SERVER, port: +E.MES_PORT || 1433, database: E.MES_DB, user: E.MES_USER, password: E.MES_PW,
      options: { encrypt: false, trustServerCertificate: true }, requestTimeout: 15000 });
    const rows = (await pool.request().input('PLANT', E.MES_PLANT).query(MES_SQL)).recordset.filter(r => r.no).map(r => ({ ...r, no: +r.no, updated_at: new Date().toISOString() }));
    const res = await fetch(`${E.SB_URL}/rest/v1/machines_live?on_conflict=no`, { method: 'POST',
      headers: { apikey: E.SB_SERVICE_KEY, Authorization: `Bearer ${E.SB_SERVICE_KEY}`, 'content-type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows) });
    console.log(new Date().toLocaleTimeString(), res.ok ? `올림 ${rows.length}대` : `실패 ${res.status} ${await res.text()}`);
  } catch (e) { console.error(new Date().toLocaleTimeString(), '오류', e.message); pool = null; }
}
tick(); setInterval(tick, POLL);
