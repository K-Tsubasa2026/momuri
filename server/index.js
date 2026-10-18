// momuri 공유 루틴 서버: 의존성 없이 node:http + node:sqlite
// 공유한 루틴의 정의와 멤버별 "한 날" 목록만 보관한다 (체크는 각자, 서로 보기만)
import { createServer } from 'node:http'
import { DatabaseSync } from 'node:sqlite'
import { randomBytes, randomUUID } from 'node:crypto'

const PORT = Number(process.env.PORT ?? 8787)
const DB_PATH = process.env.DB_PATH ?? new URL('./momuri.db', import.meta.url).pathname

export function openDatabase(path = DB_PATH) {
  const db = new DatabaseSync(path)
  db.exec(`
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS members (
      id TEXT PRIMARY KEY, token TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')));
    CREATE TABLE IF NOT EXISTS shares (
      id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, owner_id TEXT NOT NULL REFERENCES members(id),
      routine TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')));
    CREATE TABLE IF NOT EXISTS cheers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      share_id TEXT NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
      from_id TEXT NOT NULL REFERENCES members(id),
      to_id TEXT NOT NULL REFERENCES members(id),
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')));
    CREATE TABLE IF NOT EXISTS share_members (
      share_id TEXT NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
      member_id TEXT NOT NULL REFERENCES members(id),
      days TEXT NOT NULL DEFAULT '[]', updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (share_id, member_id));
  `)
  // 나중에 추가한 열: 날짜별 진행량(공부 문제 수 등)과 "지금 공부 중" 시작 시각
  for (const ddl of [
    "ALTER TABLE share_members ADD COLUMN progress TEXT NOT NULL DEFAULT '{}'",
    'ALTER TABLE share_members ADD COLUMN studying_since TEXT',
  ]) {
    try { db.exec(ddl) } catch { /* 이미 있음 */ }
  }
  return db
}

// 헷갈리는 글자(0/O, 1/I)를 뺀 6자리 초대 코드
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
function newCode() {
  return Array.from(randomBytes(6), b => CODE_CHARS[b % CODE_CHARS.length]).join('')
}

const DAY = /^\d{4}-\d{2}-\d{2}$/

// 앱이 읽는 루틴 정의의 필수 항목. 빠지면 모든 멤버 앱에서 공유가 깨진다.
const ROUTINE_FIELDS = {
  name: 'string', kind: 'string', category: 'string', intervalValue: 'number', intervalUnit: 'string',
  reminderHour: 'number', reminderMinute: 'number', reminderTimes: 'object', remindDaysBefore: 'number',
  parts: 'object', weekendOnly: 'boolean', targetValue: 'number', targetUnit: 'string',
  windowStart: 'number', windowEnd: 'number', goalMinutes: 'number', eventDate: 'string',
  allDay: 'boolean', location: 'string', remindOffsets: 'object',
}

function validRoutine(r) {
  if (!r || typeof r !== 'object' || Array.isArray(r)) return false
  if (JSON.stringify(r).length > 8 * 1024) return false
  return Object.entries(ROUTINE_FIELDS).every(([k, t]) => typeof r[k] === t && r[k] !== null)
    && r.name.trim().length > 0
}

// 초대 코드 대입 방지: 멤버당 10분에 10번
const joinAttempts = new Map()
function tooManyJoins(memberId) {
  const now = Date.now()
  const recent = (joinAttempts.get(memberId) ?? []).filter(t => now - t < 10 * 60 * 1000)
  recent.push(now)
  joinAttempts.set(memberId, recent)
  return recent.length > 10
}

export function createApp(db) {
  const q = {
    insertMember: db.prepare('INSERT INTO members (id, token, name) VALUES (?, ?, ?)'),
    renameMember: db.prepare('UPDATE members SET name = ? WHERE id = ?'),
    memberByToken: db.prepare('SELECT id, name FROM members WHERE token = ?'),
    insertShare: db.prepare('INSERT INTO shares (id, code, owner_id, routine) VALUES (?, ?, ?, ?)'),
    shareByCode: db.prepare('SELECT * FROM shares WHERE code = ?'),
    shareById: db.prepare('SELECT * FROM shares WHERE id = ?'),
    updateRoutine: db.prepare('UPDATE shares SET routine = ? WHERE id = ?'),
    join: db.prepare('INSERT OR IGNORE INTO share_members (share_id, member_id) VALUES (?, ?)'),
    leave: db.prepare('DELETE FROM share_members WHERE share_id = ? AND member_id = ?'),
    isMember: db.prepare('SELECT 1 FROM share_members WHERE share_id = ? AND member_id = ?'),
    setDays: db.prepare("UPDATE share_members SET days = ?, progress = ?, updated_at = datetime('now') WHERE share_id = ? AND member_id = ?"),
    setStatus: db.prepare("UPDATE share_members SET studying_since = ?, updated_at = datetime('now') WHERE share_id = ? AND member_id = ?"),
    members: db.prepare(`SELECT m.id, m.name, sm.days, sm.progress, sm.studying_since FROM share_members sm JOIN members m ON m.id = sm.member_id
                         WHERE sm.share_id = ? ORDER BY sm.rowid`),
    countMembers: db.prepare('SELECT COUNT(*) AS n FROM share_members WHERE share_id = ?'),
    deleteShare: db.prepare('DELETE FROM shares WHERE id = ?'),
    insertCheer: db.prepare('INSERT INTO cheers (share_id, from_id, to_id) VALUES (?, ?, ?)'),
    lastCheer: db.prepare("SELECT created_at FROM cheers WHERE share_id = ? AND from_id = ? AND to_id = ? ORDER BY id DESC LIMIT 1"),
    cheersFor: db.prepare(`SELECT c.id, c.from_id, m.name AS from_name, c.created_at FROM cheers c JOIN members m ON m.id = c.from_id
                           WHERE c.share_id = ? AND c.to_id = ? AND c.created_at >= ? ORDER BY c.id DESC LIMIT 20`),
  }

  function shareView(share, me) {
    const since = new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString()
    return {
      id: share.id,
      code: share.code,
      ownerId: share.owner_id,
      routine: JSON.parse(share.routine),
      members: q.members.all(share.id).map(m => ({
        id: m.id,
        name: m.name,
        days: JSON.parse(m.days),
        progress: JSON.parse(m.progress),
        studyingSince: m.studying_since ?? null,
      })),
      // 나에게 온 최근 응원 (3일)
      cheers: me ? q.cheersFor.all(share.id, me.id, since).map(c => ({ id: c.id, fromId: c.from_id, fromName: c.from_name, at: c.created_at })) : [],
    }
  }

  const routes = [
    // 처음 공유할 때 이름만으로 등록. 토큰은 기기에만 보관된다.
    ['POST', /^\/members$/, false, (_, body) => {
      const name = String(body.name ?? '').trim().slice(0, 30)
      if (!name) return [400, { error: '이름이 필요해요' }]
      const id = randomUUID()
      const token = randomBytes(24).toString('base64url')
      q.insertMember.run(id, token, name)
      return [201, { id, token, name }]
    }],
    ['PATCH', /^\/members\/me$/, true, (me, body) => {
      const name = String(body.name ?? '').trim().slice(0, 30)
      if (!name) return [400, { error: '이름이 필요해요' }]
      q.renameMember.run(name, me.id)
      return [200, { id: me.id, name }]
    }],
    ['POST', /^\/shares$/, true, (me, body) => {
      if (!validRoutine(body.routine)) return [400, { error: '루틴 정보가 올바르지 않아요' }]
      const id = randomUUID()
      let code = newCode()
      while (q.shareByCode.get(code)) code = newCode()
      q.insertShare.run(id, code, me.id, JSON.stringify(body.routine))
      q.join.run(id, me.id)
      return [201, shareView(q.shareById.get(id), me)]
    }],
    ['POST', /^\/shares\/join$/, true, (me, body) => {
      if (tooManyJoins(me.id)) return [429, { error: '잠시 뒤에 다시 시도해 주세요' }]
      const share = q.shareByCode.get(String(body.code ?? '').trim().toUpperCase())
      if (!share) return [404, { error: '초대 코드를 찾을 수 없어요' }]
      q.join.run(share.id, me.id)
      return [200, shareView(share, me)]
    }],
    ['GET', /^\/shares\/([\w-]+)$/, true, (me, _, [id]) => {
      const share = q.shareById.get(id)
      if (!share || !q.isMember.get(id, me.id)) return [404, { error: '공유를 찾을 수 없어요' }]
      return [200, shareView(share, me)]
    }],
    ['PUT', /^\/shares\/([\w-]+)\/routine$/, true, (me, body, [id]) => {
      const share = q.shareById.get(id)
      if (!share || share.owner_id !== me.id) return [403, { error: '만든 사람만 바꿀 수 있어요' }]
      if (!validRoutine(body.routine)) return [400, { error: '루틴 정보가 올바르지 않아요' }]
      q.updateRoutine.run(JSON.stringify(body.routine), id)
      return [200, shareView(q.shareById.get(id), me)]
    }],
    // 내 "한 날" 목록을 통째로 바꾼다 (최근 기록만 보내면 됨)
    ['PUT', /^\/shares\/([\w-]+)\/days$/, true, (me, body, [id]) => {
      if (!q.isMember.get(id, me.id)) return [404, { error: '공유를 찾을 수 없어요' }]
      const days = Array.isArray(body.days) ? [...new Set(body.days.filter(d => DAY.test(d)))].sort().slice(-400) : null
      if (!days) return [400, { error: 'days 배열이 필요해요' }]
      // 날짜별 진행량: 최근 120개만, 숫자만
      const progress = Object.fromEntries(
        Object.entries(body.progress && typeof body.progress === 'object' ? body.progress : {})
          .filter(([d, v]) => DAY.test(d) && Number.isFinite(v))
          .sort(([a], [b]) => a.localeCompare(b))
          .slice(-120))
      q.setDays.run(JSON.stringify(days), JSON.stringify(progress), id, me.id)
      return [200, shareView(q.shareById.get(id), me)]
    }],
    // 응원 보내기 (같은 사람에게는 1분에 한 번)
    ['POST', /^\/shares\/([\w-]+)\/cheers$/, true, (me, body, [id]) => {
      const to = String(body.to ?? '')
      if (!q.isMember.get(id, me.id) || !q.isMember.get(id, to) || to === me.id) return [404, { error: '보낼 사람을 찾을 수 없어요' }]
      const last = q.lastCheer.get(id, me.id, to)
      if (last && Date.now() - new Date(last.created_at).getTime() < 60 * 1000) return [429, { error: '조금 뒤에 다시 보내 주세요' }]
      q.insertCheer.run(id, me.id, to)
      return [201, shareView(q.shareById.get(id), me)]
    }],
    // 같이 공부: 타이머를 켜면 시작 시각, 끄면 null
    ['PUT', /^\/shares\/([\w-]+)\/status$/, true, (me, body, [id]) => {
      if (!q.isMember.get(id, me.id)) return [404, { error: '공유를 찾을 수 없어요' }]
      const since = body.studyingSince == null ? null : new Date(body.studyingSince)
      if (since && Number.isNaN(since.getTime())) return [400, { error: '시간 형식이 아니에요' }]
      q.setStatus.run(since ? since.toISOString() : null, id, me.id)
      return [200, shareView(q.shareById.get(id), me)]
    }],
    ['DELETE', /^\/shares\/([\w-]+)\/members\/me$/, true, (me, _, [id]) => {
      q.leave.run(id, me.id)
      if (q.countMembers.get(id).n === 0) q.deleteShare.run(id)
      return [204, null]
    }],
  ]

  return async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost')
    const send = (status, data) => {
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
      res.end(data == null ? '' : JSON.stringify(data))
    }
    if (url.pathname === '/health') return send(200, { ok: true })

    const route = routes.find(([m, re]) => m === req.method && re.test(url.pathname))
    if (!route) return send(404, { error: 'not found' })
    const [, re, needsAuth, fn] = route

    let me = null
    if (needsAuth) {
      const token = (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '')
      me = token ? q.memberByToken.get(token) : null
      if (!me) return send(401, { error: '인증이 필요해요' })
    }

    let body = {}
    if (req.method !== 'GET' && req.method !== 'DELETE') {
      let raw = ''
      for await (const chunk of req) {
        raw += chunk
        if (raw.length > 64 * 1024) return send(413, { error: '너무 커요' })
      }
      try { body = raw ? JSON.parse(raw) : {} } catch { return send(400, { error: 'JSON 형식이 아니에요' }) }
    }

    try {
      const [status, data] = fn(me, body, url.pathname.match(re).slice(1))
      send(status, data)
    } catch (err) {
      console.error(err)
      send(500, { error: '서버 오류' })
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const db = openDatabase()
  createServer(createApp(db)).listen(PORT, () => console.log(`momuri server on :${PORT}`))
}
