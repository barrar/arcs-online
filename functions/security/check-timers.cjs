const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp: initializeClient, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getFirestore: getClientFirestore, connectFirestoreEmulator, doc, getDoc } = require('firebase/firestore');
const { initializeApp: initializeAdmin } = require('firebase-admin/app');
const { getFirestore: getAdminFirestore } = require('firebase-admin/firestore');

const projectId = 'arcs-online-jeremiah-2026';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const admin = getAdminFirestore(initializeAdmin({ projectId }, `timer-${randomUUID()}`));

async function seat() {
  const name = randomUUID();
  const app = initializeClient({ apiKey: 'emulator-key', projectId, appId: name }, name);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const functions = getFunctions(app, 'us-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  const db = getClientFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  return { app, auth, db, call: (name, data) => httpsCallable(functions, name)(data).then((result) => result.data) };
}

async function verify(timer, count) {
  const seats = await Promise.all(Array.from({ length: count }, seat));
  try {
    const created = await seats[0].call('createLobby', {
      name: 'Timer integration', displayName: 'Seat 1', visibility: 'private', maxPlayers: count, timer,
    });
    for (let index = 1; index < count; index++) {
      await seats[index].call('joinLobby', { code: created.code, displayName: `Seat ${index + 1}` });
    }
    await Promise.all(seats.map((player) => player.call('setReady', { lobbyId: created.lobbyId, ready: true })));
    await seats[0].call('startGame', { lobbyId: created.lobbyId });
    const gameRef = doc(seats[0].db, 'games', created.lobbyId);
    const before = (await getDoc(gameRef)).data();
    const targetUid = before.actorUid;
    const voters = seats.filter((player) => player.auth.currentUser.uid !== targetUid);
    const vote = (player) => player.call('submitGameCommand', {
      gameId: created.lobbyId, commandId: randomUUID(), command: { kind: 'vote-kick', targetUid },
    });
    await assert.rejects(vote(voters[0]), /not overdue/);

    // Advance only the emulator's server-owned clock field; no game pieces change.
    const stateRef = admin.doc(`games/${created.lobbyId}/private/state`);
    const stored = (await stateRef.get()).data();
    const state = JSON.parse(stored.payload);
    state.deadlineMs = Date.now() - 1000;
    await stateRef.update({ payload: JSON.stringify(state) });

    for (let index = 0; index < voters.length; index++) {
      await vote(voters[index]);
      const current = (await getDoc(gameRef)).data();
      if (index < voters.length - 1) {
        assert.equal(current.status, 'playing');
        assert.equal(current.vote.approvals.length, index + 1);
      } else {
        assert.equal(current.status, 'terminated');
        assert.equal(current.winnerUid, null);
        assert.equal(current.termination.reason, 'kick');
        assert.equal(current.termination.targetUid, targetUid);
        assert.deepEqual(current.systems, before.systems);
      }
    }
    console.log(`${timer.mode} ${count}-player timer: early vote rejected; all rival approvals required; no winner or piece changes.`);
  } finally {
    await Promise.all(seats.map((player) => deleteApp(player.app)));
  }
}

(async () => {
  await verify({ mode: 'live', minutes: 2 }, 3);
  await verify({ mode: 'async', hours: 24 }, 4);
  await verify({ mode: 'async', hours: 48 }, 2);
})().catch((error) => { console.error(error); process.exitCode = 1; });
