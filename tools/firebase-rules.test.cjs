const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { ref, get, set, update, serverTimestamp } = require('firebase/database');
const fs = require('node:fs');

test('multi-room access, shared presence, private approvals and owner boundaries', async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-study-pet', database: {
    host: '127.0.0.1', port: 19000, rules: fs.readFileSync('../firebase-rules.json', 'utf8') } });
  const db = uid => env.authenticatedContext(uid).database();
  const host = db('host'), guest = db('guest'), other = db('other'), outsider = db('outsider');
  const first = 'firstroom0000000001', second = 'secondroom000000001', foreign = 'foreignroom00000001';
  const create = (uid, room, name, sit = false) => ({
    [`rooms/${room}/owner`]: uid, [`rooms/${room}/name`]: name,
    [`rooms/${room}/approved/${uid}`]: true, [`owned/${uid}/${room}`]: serverTimestamp(), [`access/${uid}/${room}`]: true,
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
      'seats/guest': first, [`access/guest/${first}`]: true, [`requests/${first}/guest`]: null
    };
    await assertFails(update(ref(host), { ...approve, [`rooms/${first}/names/guest`]: '가'.repeat(13) }));
    assert.equal((await get(ref(guest, `requests/${first}/guest`))).exists(), true);
    assert.equal((await get(ref(guest, 'seats/guest'))).exists(), false);
    await assertSucceeds(update(ref(host), approve));
    assert.equal((await get(ref(guest, `requests/${first}/guest`))).exists(), false);
    await assertFails(get(ref(guest, `rooms/${second}`)));
    const grant = { [`rooms/${second}/approved/guest`]: true, [`rooms/${second}/names/guest`]: '친구', [`access/guest/${second}`]: true };
    await assertFails(update(ref(host), { ...grant, [`rooms/${second}/name`]: '가'.repeat(21) }));
    assert.equal((await get(ref(guest, `access/guest/${second}`))).exists(), false);
    await assertSucceeds(update(ref(host), grant));
    assert.deepEqual((await get(ref(guest, 'access/guest'))).val(), { [first]: true, [second]: true });
    await assertSucceeds(get(ref(guest, `rooms/${first}`)));
    await assertSucceeds(get(ref(guest, `rooms/${second}`)));
    const status = { name: '친구', look: 'girl', style: 'g213402', state: 'studying', subject: '수학', minutes: 3, updated: serverTimestamp() };
    await assertSucceeds(update(ref(guest), { [`rooms/${first}/members/guest`]: status, [`rooms/${second}/members/guest`]: status }));
    assert.equal((await get(ref(host, `rooms/${first}/members/guest/minutes`))).val(), 3);
    await assertSucceeds(set(ref(guest, `rooms/${first}/wardrobe/guest`), '1323133'));
    await assertFails(set(ref(guest, `rooms/${first}/wardrobe/host`), '1323133'));
    await assertFails(set(ref(guest, `rooms/${first}/wardrobe/guest`), '9999999'));
    const custom={version:1,slots:{hat:{enabled:true,value:12},documentSticker:{enabled:false,value:4},deskStickers:{enabled:true,value:1}}};
    const customPath='rooms/'+first+'/customization/guest';
    await assertSucceeds(set(ref(guest,customPath),custom));
    await assertFails(set(ref(outsider,customPath),custom));
    await assertFails(set(ref(host,customPath),custom));
    await assertFails(set(ref(guest,customPath+'/slots/hat/value'),13));
    await assertFails(set(ref(guest,customPath+'/slots/hat/value'),1.5));
    await assertFails(set(ref(guest,customPath+'/slots/hat/enabled'),'yes'));
    await assertFails(set(ref(guest,customPath+'/slots/floor'),{enabled:true,value:1}));
    await assertFails(set(ref(guest,customPath+'/slots/hat/locked'),true));
    await assertFails(set(ref(guest,customPath+'/version'),2));
    assert.equal((await get(ref(host,customPath+'/slots/hat/value'))).val(),12);

    await assertSucceeds(set(ref(guest, `rooms/${first}/versions/guest`), '0.5.1'));
    await assertFails(set(ref(guest, `rooms/${first}/versions/host`), '0.5.1'));
    await assertFails(set(ref(outsider, `rooms/${first}/versions/outsider`), '0.5.1'));
    await assertFails(set(ref(guest, `rooms/${first}/versions/guest`), 'https://example.com'));
    await assertFails(set(ref(guest, `rooms/${first}/versions/guest`), '1'.repeat(40) + '.0.0'));
    await assertFails(set(ref(outsider, 'releaseChannel/stable'), 'v9.0.0'));
    await assertSucceeds(get(ref(env.unauthenticatedContext().database(), 'releaseChannel/stable')));
    const channelRule = JSON.parse(fs.readFileSync('../firebase-rules.json', 'utf8')).rules.releaseChannel.stable['.write'];
    const publisherUid = channelRule.match(/auth.uid == '([^']+)'/)[1];
    const publisher = db(publisherUid);
    await assertSucceeds(set(ref(publisher, 'releaseChannel/stable'), 'v0.5.0'));
    await assertFails(set(ref(publisher, 'releaseChannel/stable'), 'not-a-version'));
    await assertFails(get(ref(publisher, `rooms/${first}`)));

    assert.equal((await get(ref(host, `rooms/${second}/members/guest/minutes`))).val(), 3);
    await assertSucceeds(update(ref(host), { [`rooms/${first}/members/host`]: { ...status, name: '방장' }, [`rooms/${second}/members/host`]: { ...status, name: '방장' } }));
    await assertFails(update(ref(other), { [`rooms/${foreign}/approved/guest`]: true, [`access/guest/${foreign}`]: true }));
    await assertFails(set(ref(guest, 'seats/guest'), second));
    await assertFails(set(ref(guest, `access/guest/${foreign}`), true));
    await assertFails(get(ref(outsider, 'access/guest')));
    await assertFails(set(ref(host, `rooms/${first}/approved/host`), null));
    await assertFails(set(ref(guest, `rooms/${second}/members/host`), status));
    // The desk (drink + 10 for a laptop): my own, a small number, and never as part of members/.
    await assertSucceeds(set(ref(guest, `rooms/${first}/desks/guest`), 15));
    assert.equal((await get(ref(host, `rooms/${first}/desks/guest`))).val(), 15);
    await assertFails(set(ref(guest, `rooms/${first}/desks/host`), 1));
    await assertFails(set(ref(guest, `rooms/${first}/desks/guest`), 'beer'));
    await assertFails(set(ref(guest, `rooms/${first}/desks/guest`), 100));
    await assertFails(set(ref(outsider, `rooms/${first}/desks/outsider`), 1));
    await assertFails(set(ref(guest, `rooms/${first}/members/guest`), { ...status, desk: 1 }));
    const poke = { from: 'guest', name: '친구', look: 'girl', message: '같이 공부하자 !', at: serverTimestamp() };
    await assertSucceeds(set(ref(guest, `rooms/${second}/pokes/host`), poke));
    await assertFails(set(ref(guest, `rooms/${second}/pokes/outsider`), poke));
    await assertFails(set(ref(guest, `rooms/${second}/pokes/host`), null));
    await assertSucceeds(set(ref(host, `rooms/${second}/pokes/host`), null));
    await assertFails(set(ref(guest, `rooms/${first}/entry`), second));
    await assertFails(set(ref(host, `rooms/${first}/entry`), foreign));
    await assertSucceeds(set(ref(host, `rooms/${first}/entry`), second));
    await assertSucceeds(set(ref(host, `rooms/${first}/name`), '이름 바꾼 첫 방'));
    await assertSucceeds(update(ref(host), { [`rooms/${second}/approved/guest`]: null, [`rooms/${second}/names/guest`]: null,
      [`rooms/${second}/members/guest`]: null, [`access/guest/${second}`]: null }));
    await assertFails(get(ref(guest, `rooms/${second}`)));
    await assertFails(set(ref(guest, `rooms/${second}/members/guest`), status));
    await assertSucceeds(get(ref(guest, `rooms/${first}`)));
    await assertFails(set(ref(outsider, `requests/${first}/guest`), { name: '사칭' }));
  } finally { await env.cleanup(); }
});
