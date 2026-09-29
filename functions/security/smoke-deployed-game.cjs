// Manual production check. Creates a disposable two-player match, then ends it.
// Delete the printed game, lobby, and lobby-code documents with the Firebase CLI.
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, signInAnonymously } = require('firebase/auth');
const { getFunctions, httpsCallable } = require('firebase/functions');
const { getFirestore, doc, getDoc } = require('firebase/firestore');

const config = {
  apiKey: 'REMOVED_FIREBASE_API_KEY',
  authDomain: 'arcs-online-jeremiah-2026.firebaseapp.com',
  projectId: 'arcs-online-jeremiah-2026',
  appId: '1:451692891873:web:a7adc5706e454f0f0d31a0',
};

async function client(name) {
  const app = initializeApp(config, `deployed-match-${name}-${Date.now()}`);
  const auth = getAuth(app);
  await signInAnonymously(auth);
  const functions = getFunctions(app, 'us-west1');
  const db = getFirestore(app);
  return {
    app, uid: auth.currentUser.uid, db,
    call: (name, data) => httpsCallable(functions, name)(data).then((result) => result.data),
  };
}

async function run() {
  const [a, b] = await Promise.all([client('a'), client('b')]);
  try {
    const lobby = await a.call('createLobby', {
      name: 'Deployment smoke test', displayName: 'Test A', visibility: 'private', maxPlayers: 2,
      timer: { mode: 'async', hours: 24 },
    });
    console.log(`SMOKE_IDS ${JSON.stringify({ lobbyId: lobby.lobbyId, code: lobby.code })}`);
    await b.call('joinLobby', { code: lobby.code, displayName: 'Test B' });
    await Promise.all([
      a.call('setReady', { lobbyId: lobby.lobbyId, ready: true }),
      b.call('setReady', { lobbyId: lobby.lobbyId, ready: true }),
    ]);
    const started = await a.call('startGame', { lobbyId: lobby.lobbyId });
    assert.equal(started.gameId, lobby.lobbyId);
    const gameRef = doc(a.db, 'games', started.gameId);
    const game = (await getDoc(gameRef)).data();
    assert.equal(game.status, 'playing');
    assert.equal(game.rulesVersion, 'arcs-base-2025-08-27');
    assert.equal(game.round.hands[a.uid], 6);
    assert.equal(game.round.hands[b.uid], 6);
    assert.equal(game.actionDiscard, undefined);
    assert.equal(game.courtDeck, undefined);
    assert.equal((await getDoc(doc(a.db, 'games', started.gameId, 'hands', a.uid))).data().cards.length, 6);
    assert.equal((await getDoc(doc(b.db, 'games', started.gameId, 'hands', b.uid))).data().cards.length, 6);
    await assert.rejects(getDoc(doc(a.db, 'games', started.gameId, 'hands', b.uid)));
    const mulliganPlayer = game.mulliganPendingUid === a.uid ? a : b;
    const result = await mulliganPlayer.call('submitGameCommand', {
      gameId: started.gameId, commandId: randomUUID(), command: { kind: 'mulligan', replace: false },
    });
    assert.equal(result.version, 1);
    assert.equal((await getDoc(gameRef)).data().mulliganPendingUid, null);
    await a.call('submitGameCommand', {
      gameId: started.gameId, commandId: randomUUID(), command: { kind: 'concede' },
    });
    const ended = (await getDoc(gameRef)).data();
    assert.equal(ended.status, 'terminated');
    assert.equal(ended.winnerUid, null);
    console.log('Production guest auth, lobby, match start, hidden hands, command, and termination passed.');
  } finally {
    await Promise.all([a.app, b.app].map(deleteApp));
  }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
