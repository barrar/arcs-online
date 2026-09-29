const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously, EmailAuthProvider, linkWithCredential } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getFirestore, connectFirestoreEmulator, doc, getDoc,
  collection, query, where, getDocs } = require('firebase/firestore');

const projectId = 'arcs-online-jeremiah-2026';
async function client(name) {
  const app = initializeApp({ apiKey: 'emulator-key', projectId, appId: `test-${name}` }, `test-${name}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const functions = getFunctions(app, 'us-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  const call = (name, data) => httpsCallable(functions, name)(data).then(result => result.data);
  return { app, auth, db, call };
}

async function check() {
  const [a, b, c] = await Promise.all([client('a'), client('b'), client('c')]);
  try {
    const created = await a.call('createLobby', {
      name: 'Local lobby test', displayName: 'A', visibility: 'private', maxPlayers: 2,
      timer: { mode: 'live', minutes: 5 },
    });
    assert.match(created.code, /^[A-Z2-9]{8}$/);
    const guestUid = a.auth.currentUser.uid;
    await linkWithCredential(a.auth.currentUser,
      EmailAuthProvider.credential(`arcs-test-${Date.now()}@example.invalid`, 'local-test-only-password'));
    assert.equal(a.auth.currentUser.uid, guestUid);
    const joins = await Promise.allSettled([
      b.call('joinLobby', { code: created.code, displayName: 'B' }),
      c.call('joinLobby', { code: created.code, displayName: 'C' }),
    ]);
    assert.equal(joins.filter(result => result.status === 'fulfilled').length, 1);
    const winner = joins[0].status === 'fulfilled' ? b : c;
    const loser = winner === b ? c : b;
    const ref = doc(a.db, 'lobbies', created.lobbyId);
    const before = (await getDoc(ref)).data();
    assert.equal(before.seats.length, 2);
    assert.equal(before.memberIds.length, 2);
    assert.equal(before.timer.minutes, 5);
    await assert.rejects(getDoc(doc(loser.db, 'lobbies', created.lobbyId)));
    await winner.call('setReady', { lobbyId: created.lobbyId, ready: true });
    await a.call('setReady', { lobbyId: created.lobbyId, ready: true });
    const ready = (await getDoc(ref)).data();
    assert.equal(ready.seats.every(seat => seat.ready), true);
    await a.call('leaveLobby', { lobbyId: created.lobbyId });
    const after = (await getDoc(doc(winner.db, 'lobbies', created.lobbyId))).data();
    assert.equal(after.hostId, winner.auth.currentUser.uid);
    assert.equal(after.seats.length, 1);
    await a.call('joinLobby', { code: created.code, displayName: 'A returns' });
    assert.equal((await getDoc(ref)).data().seats.length, 2);

    const publicLobby = await c.call('createLobby', {
      name: 'Public discovery check', displayName: 'C', visibility: 'public', maxPlayers: 3,
      timer: { mode: 'async', hours: 48 },
    });
    const openTables = await getDocs(query(collection(a.db, 'lobbies'),
      where('visibility', '==', 'public'), where('status', '==', 'waiting')));
    assert.ok(openTables.docs.some((item) => item.id === publicLobby.lobbyId));
    assert.ok(openTables.docs.every((item) => item.id !== created.lobbyId));
    await a.call('joinLobby', { code: publicLobby.code, displayName: 'A joins public' });
    assert.equal((await getDoc(doc(a.db, 'lobbies', publicLobby.lobbyId))).data().seats.length, 2);
    console.log('Private invites, public discovery, concurrent join, ready-up, host leave, and rejoin checks passed.');
  } finally {
    await Promise.all([a.app, b.app, c.app].map(deleteApp));
  }
}

check().catch(error => { console.error(error); process.exitCode = 1; });
