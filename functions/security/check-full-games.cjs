const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getFirestore, connectFirestoreEmulator, doc, getDoc } = require('firebase/firestore');

const projectId = 'arcs-online-jeremiah-2026';
async function client(label) {
  const app = initializeApp({ apiKey: 'emulator-key', projectId, appId: `full-${label}` }, `full-${label}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const functions = getFunctions(app, 'us-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  return { app, auth, db, call: (name, data) => httpsCallable(functions, name)(data).then((result) => result.data) };
}

async function fullMatch(count) {
  const clients = await Promise.all(Array.from({ length: count }, (_, index) =>
    client(`${count}-${index}-${randomUUID()}`)));
  try {
    const created = await clients[0].call('createLobby', {
      name: `Full ${count}-player integration`, displayName: 'Seat 1', visibility: 'private',
      maxPlayers: count, timer: { mode: 'async', hours: 24 },
    });
    for (let index = 1; index < count; index++) {
      await clients[index].call('joinLobby', { code: created.code, displayName: `Seat ${index + 1}` });
    }
    await Promise.all(clients.map((seat) => seat.call('setReady', { lobbyId: created.lobbyId, ready: true })));
    const start = await clients[0].call('startGame', { lobbyId: created.lobbyId });
    assert.equal(start.gameId, created.lobbyId);
    const byUid = new Map(clients.map((seat) => [seat.auth.currentUser.uid, seat]));
    const gameRef = doc(clients[0].db, 'games', created.lobbyId);
    let steps = 0;
    while (steps < 500) {
      const snapshot = (await getDoc(gameRef)).data();
      assert.ok(snapshot);
      if (snapshot.status === 'finished') {
        assert.ok(byUid.has(snapshot.winnerUid));
        assert.equal(snapshot.chapter, 5);
        assert.equal(snapshot.version, steps);
        console.log(`${count} players: full five-chapter match finished in ${steps} commands (${snapshot.setupId}).`);
        return snapshot.setupId;
      }
      assert.equal(snapshot.status, 'playing');
      const uid = snapshot.mulliganPendingUid || snapshot.actorUid;
      const actor = byUid.get(uid);
      assert.ok(actor, 'Every decision maker must be seated.');
      let command;
      if (snapshot.mulliganPendingUid) {
        command = { kind: 'mulligan', replace: false };
      } else if (snapshot.round.playedThisTurn) {
        command = { kind: 'end-turn' };
      } else {
        const handRef = doc(actor.db, 'games', created.lobbyId, 'hands', uid);
        const cards = (await getDoc(handRef)).data().cards;
        command = cards.length === 0 ? { kind: 'pass' } : {
          kind: 'play', cardId: cards[0], mode: snapshot.round.lead ? 'copy' : 'lead',
        };
      }
      await actor.call('submitGameCommand', {
        gameId: created.lobbyId, commandId: randomUUID(), command,
      });
      steps++;
    }
    throw new Error(`${count}-player match did not finish within 500 commands.`);
  } finally {
    await Promise.all(clients.map((seat) => deleteApp(seat.app)));
  }
}

(async () => {
  for (const count of [2, 3, 4]) {
    const setups = new Set();
    for (let attempt = 0; attempt < 6 && setups.size < 2; attempt++) {
      setups.add(await fullMatch(count));
    }
    assert.ok(setups.size >= 2, `${count}-player matches must exercise two distinct setup cards.`);
    console.log(`${count} players: verified setups ${[...setups].join(', ')}.`);
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
