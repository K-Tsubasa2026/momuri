import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { openDatabase, createApp } from './index.js'

// 앱이 보내는 것과 같은 모양의 루틴 정의
const routine = name => ({
  name, kind: 'daily', category: 'other', intervalValue: 1, intervalUnit: 'month', reminderHour: 9, reminderMinute: 0,
  reminderTimes: [], remindDaysBefore: 3, parts: [], weekendOnly: false, targetValue: 0, targetUnit: '회',
  windowStart: 720, windowEnd: 1200, goalMinutes: 120, eventDate: '2026-10-13T00:00:00Z', allDay: false,
  location: '', remindOffsets: [],
})

async function start() {
  const server = createServer(createApp(openDatabase(':memory:')))
  await new Promise(r => server.listen(0, r))
  const base = `http://localhost:${server.address().port}`
  const call = async (method, path, body, token) => {
    const res = await fetch(base + path, {
      method,
      headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
      body: body && JSON.stringify(body),
    })
    return { status: res.status, data: res.status === 204 ? null : await res.json() }
  }
  return { server, call }
}

test('공유 → 참여 → 각자 기록 → 서로 보기 → 나가기', async () => {
  const { server, call } = await start()
  const a = (await call('POST', '/members', { name: '림' })).data
  const b = (await call('POST', '/members', { name: '유진' })).data

  const share = (await call('POST', '/shares', { routine: routine('샴푸') }, a.token)).data
  assert.match(share.code, /^[A-Z2-9]{6}$/)

  assert.equal((await call('POST', '/shares/join', { code: 'nope00' }, b.token)).status, 404)
  const joined = await call('POST', '/shares/join', { code: share.code.toLowerCase() }, b.token)
  assert.equal(joined.data.routine.name, '샴푸')
  assert.deepEqual(joined.data.members.map(m => m.name), ['림', '유진'])

  await call('PUT', `/shares/${share.id}/days`, { days: ['2026-10-12', 'bad', '2026-10-12', '2026-10-13'] }, b.token)
  const view = (await call('GET', `/shares/${share.id}`, null, a.token)).data
  assert.deepEqual(view.members.find(m => m.name === '유진').days, ['2026-10-12', '2026-10-13'])

  assert.equal((await call('PUT', `/shares/${share.id}/routine`, { routine: { ...routine('x'), name: '' } }, b.token)).status, 403)
  assert.equal((await call('GET', `/shares/${share.id}`, null, 'wrong')).status, 401)

  await call('DELETE', `/shares/${share.id}/members/me`, null, b.token)
  assert.equal((await call('GET', `/shares/${share.id}`, null, b.token)).status, 404)
  await call('DELETE', `/shares/${share.id}/members/me`, null, a.token)
  assert.equal((await call('POST', '/shares/join', { code: share.code }, b.token)).status, 404)
  server.close()
})

test('같이 공부: 진행량과 공부 중 상태', async () => {
  const { server, call } = await start()
  const a = (await call('POST', '/members', { name: '림' })).data
  const b = (await call('POST', '/members', { name: '유진' })).data
  const share = (await call('POST', '/shares', { routine: routine('정보처리기사') }, a.token)).data
  await call('POST', '/shares/join', { code: share.code }, b.token)

  await call('PUT', `/shares/${share.id}/days`, { days: ['2026-10-13'], progress: { '2026-10-13': 18, bad: 3, '2026-10-12': 'x' } }, b.token)
  await call('PUT', `/shares/${share.id}/status`, { studyingSince: '2026-10-13T12:00:00Z' }, b.token)
  let yujin = (await call('GET', `/shares/${share.id}`, null, a.token)).data.members.find(m => m.name === '유진')
  assert.deepEqual(yujin.progress, { '2026-10-13': 18 })
  assert.equal(yujin.studyingSince, '2026-10-13T12:00:00.000Z')

  assert.equal((await call('PUT', `/shares/${share.id}/status`, { studyingSince: 'nope' }, b.token)).status, 400)
  await call('PUT', `/shares/${share.id}/status`, { studyingSince: null }, b.token)
  yujin = (await call('GET', `/shares/${share.id}`, null, a.token)).data.members.find(m => m.name === '유진')
  assert.equal(yujin.studyingSince, null)
  server.close()
})

test('응원: 상대에게만 보이고 1분에 한 번', async () => {
  const { server, call } = await start()
  const a = (await call('POST', '/members', { name: '림' })).data
  const b = (await call('POST', '/members', { name: '유진' })).data
  const share = (await call('POST', '/shares', { routine: routine('정보처리기사') }, a.token)).data
  await call('POST', '/shares/join', { code: share.code }, b.token)

  assert.equal((await call('POST', `/shares/${share.id}/cheers`, { to: a.id }, a.token)).status, 404)
  assert.equal((await call('POST', `/shares/${share.id}/cheers`, { to: a.id }, b.token)).status, 201)
  assert.equal((await call('POST', `/shares/${share.id}/cheers`, { to: a.id }, b.token)).status, 429)

  const forA = (await call('GET', `/shares/${share.id}`, null, a.token)).data
  assert.equal(forA.cheers.length, 1)
  assert.equal(forA.cheers[0].fromName, '유진')
  const forB = (await call('GET', `/shares/${share.id}`, null, b.token)).data
  assert.equal(forB.cheers.length, 0)
  server.close()
})

test('잘못된 루틴 정의와 코드 대입을 막는다', async () => {
  const { server, call } = await start()
  const a = (await call('POST', '/members', { name: '림' })).data
  assert.equal((await call('POST', '/shares', { routine: {} }, a.token)).status, 400)
  assert.equal((await call('POST', '/shares', { routine: { ...routine('x'), kind: 3 } }, a.token)).status, 400)
  const share = (await call('POST', '/shares', { routine: routine('토익') }, a.token)).data
  assert.equal((await call('PUT', `/shares/${share.id}/routine`, { routine: {} }, a.token)).status, 400)

  const b = (await call('POST', '/members', { name: '유진' })).data
  let last
  for (let i = 0; i < 11; i++) last = (await call('POST', '/shares/join', { code: 'ZZZZZZ' }, b.token)).status
  assert.equal(last, 429)
  server.close()
})
