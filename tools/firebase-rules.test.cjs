const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { ref, get, set, update, serverTimestamp } = require('firebase/database');
const fs = require('node:fs');

test('room creation, approval and movement are atomic and isolated by owner', async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-study-pet', database: {
    host: '127.0.0.1', port: 19000, rules: fs.readFileSync('../firebase-rules.json', 'utf8') } });
  const db = uid => env.authenticatedContext(uid).database();
  const host = db('host'), guest = db('guest'), other = db('other'), outsider = db('outsider');
  const first = 'firstroom0000000001', second = 'secondroom000000001', foreign = 'foreignroom00000001';
  const create = (uid, room, name, sit = false) => ({
    [`rooms/${room}/owner`]: uid, [`rooms/${room}/name`]: name,
    [`rooms/${room}/approved/${uid}`]: true, [`owned/${uid}/${room}`]: serverTimestamp(),
    ...(sit ? { [`seats/${uid}`]: room } : {})
  });
  try {
    await env.clearDatabase();
    await assertSucceeds(update(ref(host), create('host', first, '첫 방', true)));
    await assertSucceeds(update(ref(host), create('host', second, '2반')));
    await assertSucceeds(update(ref(other), create('other', foreign, '다른 방', true)));
    await assertFails(get(ref(outsider, `rooms/${first}`)));
    await assertFails(set(ref(guest, `rooms/${first}/name`), '무단 변경'));
    await assertSucceeds(set(ref(guest, `requests/${first}/guest`), {
      name: '친구', realName: '테스트 이름', referrer: '방장', look: 'boy', at: serverTimestamp()
    }));
    const approve = {
      [`rooms/${first}/approved/guest`]: true, [`rooms/${first}/names/guest`]: '친구',
      'seats/guest': first, [`requests/${first}/guest`]: null
    };
    await assertFails(update(ref(host), { ...approve, [`rooms/${first}/names/guest`]: '가'.repeat(13) }));
    assert.equal((await get(ref(guest, `requests/${first}/guest`))).exists(), true);
    assert.equal((await get(ref(guest, 'seats/guest'))).exists(), false);
    await assertSucceeds(update(ref(host), approve));
    assert.equal((await get(ref(guest, `requests/${first}/guest`))).exists(), false);
    await assertFails(get(ref(guest, `rooms/${second}`)));
    const move = {
      [`rooms/${second}/approved/guest`]: true, [`rooms/${second}/names/guest`]: '친구',
      'seats/guest': second, [`rooms/${first}/approved/guest`]: null,
      [`rooms/${first}/members/guest`]: null, [`rooms/${first}/names/guest`]: null
    };
    await assertFails(update(ref(host), { ...move, [`rooms/${second}/name`]: '가'.repeat(21) }));
    assert.equal((await get(ref(guest, 'seats/guest'))).val(), first);
    await assertSucceeds(update(ref(host), move));
    await assertFails(get(ref(guest, `rooms/${first}`)));
    await assertSucceeds(get(ref(guest, `rooms/${second}`)));
    const status = { name: '새 이름', look: 'girl', state: 'studying', subject: '수학', minutes: 3, updated: serverTimestamp() };
    await assertSucceeds(update(ref(guest), { [`rooms/${second}/members/guest`]: status, [`rooms/${second}/names/guest`]: '새 이름' }));
    await assertFails(set(ref(guest, `rooms/${first}/members/guest`), status));
    await assertFails(set(ref(guest, 'seats/guest'), first));
    await assertFails(update(ref(other), { [`rooms/${foreign}/approved/guest`]: true, 'seats/guest': foreign }));
    assert.equal((await get(ref(guest, 'seats/guest'))).val(), second);
    await assertFails(set(ref(guest, `rooms/${second}/name`), '무단 변경'));
    await assertSucceeds(set(ref(host, `rooms/${second}/name`), '영어반'));
    await assertSucceeds(update(ref(host), { 'seats/host': second, [`rooms/${first}/members/host`]: null }));
    await assertSucceeds(get(ref(host, `rooms/${first}`)));
    await assertSucceeds(get(ref(host, `rooms/${second}`)));
    await assertFails(set(ref(outsider, `requests/${first}/guest`), { name: '사칭' }));
  } finally { await env.cleanup(); }
});
