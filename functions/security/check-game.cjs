const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc, collection, getDocs } = require('firebase/firestore');

const projectId = 'arcs-online-jeremiah-2026';
async function client(name) {
  const app = initializeApp({ apiKey: 'emulator-key', projectId, appId: `match-${name}` }, `match-${name}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const functions = getFunctions(app, 'us-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  return { app, auth, db, call: (name, data) => httpsCallable(functions, name)(data).then((result) => result.data) };
}

async function check() {
  const [a, b, outsider] = await Promise.all([client('a'), client('b'), client('outsider')]);
  try {
    const created = await a.call('createLobby', {
      name: 'Match integration', displayName: 'A', visibility: 'private', maxPlayers: 2,
      timer: { mode: 'live', minutes: 5 },
    });
    await b.call('joinLobby', { code: created.code, displayName: 'B' });
    await Promise.all([a.call('setReady', { lobbyId: created.lobbyId, ready: true }),
      b.call('setReady', { lobbyId: created.lobbyId, ready: true })]);
    const start = await a.call('startGame', { lobbyId: created.lobbyId });
    assert.equal(start.gameId, created.lobbyId);
    const gameRef = doc(a.db, 'games', start.gameId);
    const game = (await getDoc(gameRef)).data();
    assert.equal(game.status, 'playing');
    assert.equal(game.rulesVersion, 'arcs-base-2025-08-27');
    assert.equal(game.round.hands[a.auth.currentUser.uid], 6);
    assert.equal(game.round.hands[b.auth.currentUser.uid], 6);
    assert.equal(game.actionDiscard, undefined);
    assert.equal(game.courtDeck, undefined);
    assert.equal(game.round.hands[a.auth.currentUser.uid] instanceof Array, false);
    const aHand = doc(a.db, 'games', start.gameId, 'hands', a.auth.currentUser.uid);
    const bHand = doc(b.db, 'games', start.gameId, 'hands', b.auth.currentUser.uid);
    assert.equal((await getDoc(aHand)).data().cards.length, 6);
    assert.equal((await getDoc(bHand)).data().cards.length, 6);
    await assert.rejects(getDoc(doc(a.db, 'games', start.gameId, 'hands', b.auth.currentUser.uid)));
    await assert.rejects(getDoc(doc(outsider.db, 'games', start.gameId)));
    await assert.rejects(setDoc(gameRef, { status: 'finished' }));
    await assert.rejects(getDoc(doc(a.db, 'games', start.gameId, 'private', 'state')));

    const actor = game.actorUid === a.auth.currentUser.uid ? a : b;
    const commandId = randomUUID();
    const command = { gameId: start.gameId, commandId, command: { kind: 'mulligan', replace: false } };
    const simultaneous = await Promise.all([
      actor.call('submitGameCommand', command), actor.call('submitGameCommand', command),
    ]);
    assert.equal(simultaneous.filter((result) => result.duplicate === true).length, 1);
    const updated = (await getDoc(gameRef)).data();
    assert.equal(updated.version, 1);
    assert.equal(updated.mulliganPendingUid, null);
    const events = await getDocs(collection(a.db, 'games', start.gameId, 'events'));
    assert.equal(events.size, 2);
    console.log('Match start, hidden information, atomic duplicate command, and event checks passed.');
  } finally {
    await Promise.all([a.app, b.app, outsider.app].map(deleteApp));
  }
}

check().catch((error) => { console.error(error); process.exitCode = 1; });
