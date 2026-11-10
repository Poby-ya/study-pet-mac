const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { ref,get,set,update,serverTimestamp } = require('firebase/database');
const fs = require('node:fs');

test('one-time pairing requires original-device approval and preserves private account and room access',async () => {
  const env = await initializeTestEnvironment({ projectId:'demo-study-pet', database:{ host:'127.0.0.1',port:19000,rules:fs.readFileSync('../firebase-rules.json','utf8') } });
  const owner = env.authenticatedContext('original').database(), phone = env.authenticatedContext('phone').database(), stranger = env.authenticatedContext('stranger').database();
  const room = 'pairtestroom0000001', code = 'ABCDE23456';
  try {
    await env.withSecurityRulesDisabled(async context => { const db=context.database(); await update(ref(db),{ [`rooms/${room}/owner`]:'original',[`rooms/${room}/approved/original`]:true,[`access/original/${room}`]:true }); });
    const state = {schema:1,revision:1,profile:{name:'나'},segments:{first:{start:1000,end:2000,subject:'수학'}}};
    await assertSucceeds(set(ref(owner,'users/original'),state));
    await assertFails(get(ref(phone,'users/original')));
    await assertFails(get(ref(stranger,'users/original')));
    await assertFails(set(ref(phone,'deviceAccounts/phone'),{account:'original',pair:code}));
    await assertSucceeds(set(ref(owner,`pairings/${code}`),{issuer:'original',account:'original',created:serverTimestamp()}));
    await assertFails(set(ref(stranger,`pairings/${code}/accepted`),true));
    await assertFails(set(ref(phone,`pairings/${code}/candidate`),'stranger'));
    await assertSucceeds(set(ref(phone,`pairings/${code}/candidate`),'phone'));
    await assertFails(set(ref(stranger,`pairings/${code}/candidate`),'stranger'));
    await assertFails(get(ref(phone,'users/original')));
    await assertFails(set(ref(owner,'deviceAccounts/stranger'),{account:'original',pair:code}));
    await assertSucceeds(update(ref(owner),{ 'deviceAccounts/phone':{account:'original',pair:code},[`pairings/${code}/accepted`]:true }));
    assert.equal((await get(ref(phone,'users/original/profile/name'))).val(),'나');
    await assertSucceeds(get(ref(phone,`rooms/${room}`)));
    await assertFails(get(ref(stranger,`rooms/${room}`)));
    await assertFails(get(ref(owner,'deviceAccounts/phone')));
    await assertSucceeds(set(ref(phone,`rooms/${room}/wardrobe/original`),'00000000'));
    await assertSucceeds(set(ref(phone,`rooms/${room}/wardrobe/original`),'13231337'));
    await assertFails(set(ref(phone,`rooms/${room}/wardrobe/original`),'13231338'));
    await assertFails(set(ref(phone,'deviceAccounts/phone'),{account:'stranger',pair:code}));
    await assertSucceeds(set(ref(phone,'users/original'),{...state,revision:2,active:{id:'session',device:'phone',subject:'수학',state:'studying',start:1000}}));
    // A record fixed from the record book: shortened, then removed (v0.7 trim and drop).
    await assertSucceeds(set(ref(phone,'users/original'),{...state,revision:3,segments:{first:{start:1000,end:1500,subject:'수학'}}}));
    await assertSucceeds(set(ref(phone,'users/original'),{...state,revision:4,segments:{}}));
    const presence={name:'나',look:'boy',state:'studying',subject:'수학',minutes:1,updated:serverTimestamp()};
    await assertSucceeds(update(ref(phone),{[`rooms/${room}/members/original`]:presence,[`rooms/${room}/presenceRevisions/original`]:2}));
    await assertFails(set(ref(owner,`rooms/${room}/members/original`),{...presence,state:'off'}));
    await env.withSecurityRulesDisabled(async context => { await set(ref(context.database(),'pairings/EXPIRED123'),{issuer:'original',account:'original',candidate:'stranger',created:Date.now()-601000}); });
    await assertFails(get(ref(stranger,'pairings/EXPIRED123')));
    await assertFails(set(ref(owner,'deviceAccounts/stranger'),{account:'original',pair:'EXPIRED123'}));
    await assertSucceeds(set(ref(owner,`pairings/${code}`),null));
    await assertSucceeds(get(ref(phone,'users/original')));
  } finally { await env.cleanup(); }
});

test('a linked device can pair a second device without changing the canonical identity', async () => {
  const env = await initializeTestEnvironment({ projectId:'demo-study-pet', database:{host:'127.0.0.1',port:19000,rules:fs.readFileSync('../firebase-rules.json','utf8')} });
  const db = uid => env.authenticatedContext(uid).database();
  const original = db('chain-original'), phone = db('chain-phone'), tablet = db('chain-tablet'), stranger = db('chain-stranger');
  const first = 'CHAIN23456', second = 'CHAIN34567';
  try {
    await env.clearDatabase();
    await assertSucceeds(set(ref(original,'users/chain-original'),{schema:1,revision:1,profile:{name:'원래 자리'}}));
    await assertSucceeds(set(ref(original,`pairings/${first}`),{issuer:'chain-original',account:'chain-original',created:serverTimestamp()}));
    await assertSucceeds(set(ref(phone,`pairings/${first}/candidate`),'chain-phone'));
    await assertSucceeds(update(ref(original),{'deviceAccounts/chain-phone':{account:'chain-original',pair:first},[`pairings/${first}/accepted`]:true}));
    await assertSucceeds(set(ref(phone,`pairings/${second}`),{issuer:'chain-phone',account:'chain-original',created:serverTimestamp()}));
    await assertSucceeds(set(ref(tablet,`pairings/${second}/candidate`),'chain-tablet'));
    await assertSucceeds(update(ref(phone),{'deviceAccounts/chain-tablet':{account:'chain-original',pair:second},[`pairings/${second}/accepted`]:true}));
    assert.equal((await get(ref(tablet,'users/chain-original/profile/name'))).val(),'원래 자리');
    await assertFails(get(ref(tablet,'users/chain-phone')));
    await assertFails(get(ref(stranger,'users/chain-original')));
    await assertFails(set(ref(stranger,'deviceAccounts/chain-stranger'),{account:'chain-original',pair:second}));
    await assertFails(get(ref(stranger,'pairings')));
    await assertFails(set(ref(phone,'deviceAccounts/chain-tablet'),{account:'chain-stranger',pair:second}));
  } finally { await env.cleanup(); }
});

test('room permission revocation removes every linked device while personal records remain private', async () => {
  const env = await initializeTestEnvironment({projectId:'demo-study-pet',database:{host:'127.0.0.1',port:19000,rules:fs.readFileSync('../firebase-rules.json','utf8')}});
  const host=env.authenticatedContext('revoke-host').database(), phone=env.authenticatedContext('revoke-phone').database(), other=env.authenticatedContext('revoke-other').database();
  const room='revokeroom00000001';
  try {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async context=>{
      await update(ref(context.database()),{
        'deviceAccounts/revoke-phone':{account:'revoke-original',pair:'REVOKE2345'},
        [`rooms/${room}/owner`]:'revoke-host',
        [`rooms/${room}/approved/revoke-original`]:true,
        [`access/revoke-original/${room}`]:true,
        'users/revoke-original':{schema:1,revision:1,segments:{first:{start:0,end:60000,subject:'수학'}}}
      });
    });
    await assertSucceeds(get(ref(phone,`rooms/${room}`)));
    await assertSucceeds(get(ref(phone,'users/revoke-original')));
    await assertFails(get(ref(host,'users/revoke-original')));
    await assertFails(get(ref(other,'users/revoke-original')));
    await assertSucceeds(update(ref(host),{[`rooms/${room}/approved/revoke-original`]:null,[`access/revoke-original/${room}`]:null}));
    await assertFails(get(ref(phone,`rooms/${room}`)));
    await assertFails(set(ref(phone,`rooms/${room}/members/revoke-original`),{name:'친구',look:'boy',state:'studying',subject:'수학',minutes:1,updated:serverTimestamp()}));
    await assertSucceeds(get(ref(phone,'users/revoke-original')));
  } finally { await env.cleanup(); }
});

test('stopped linked timers reject a delayed studying heartbeat from their previous device', async () => {
  const env=await initializeTestEnvironment({projectId:'demo-study-pet',database:{host:'127.0.0.1',port:19000,rules:fs.readFileSync('../firebase-rules.json','utf8')}});
  const pc=env.authenticatedContext('stale-pc').database(), phone=env.authenticatedContext('stale-phone').database();
  const room='staleheart000000001';
  try {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async context=>{
      await update(ref(context.database()),{
        'deviceAccounts/stale-phone':{account:'stale-pc',pair:'STALE23456'},
        [`rooms/${room}/owner`]:'stale-pc',[`rooms/${room}/approved/stale-pc`]:true,
        'users/stale-pc':{schema:1,revision:1,active:{id:'running',device:'stale-phone',state:'studying',subject:'수학',start:Date.now()-60000}}
      });
    });
    const presence={name:'친구',look:'boy',state:'studying',subject:'수학',minutes:1,updated:serverTimestamp()};
    const publish=(db,value,revision)=>update(ref(db),{[`rooms/${room}/members/stale-pc`]:value,[`rooms/${room}/presenceRevisions/stale-pc`]:revision});
    await assertFails(publish(pc,presence,1));
    await assertSucceeds(publish(phone,presence,1));
    await assertSucceeds(set(ref(phone,'users/stale-pc'),{schema:1,revision:2}));
    await assertFails(publish(pc,presence,1));
    await assertSucceeds(publish(phone,{...presence,state:'off',subject:'',minutes:0},2));
  } finally { await env.cleanup(); }
});
