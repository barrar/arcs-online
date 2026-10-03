// Manual production smoke test. Pass the invite code of a disposable lobby.
// This creates one anonymous guest, joins the lobby, verifies its private
// Firestore view, then leaves. Do not add this script to automated test runs.
const assert = require('node:assert/strict');
const { webConfig } = require('../../scripts/firebase-config.cjs');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, signInAnonymously } = require('firebase/auth');
const { getFunctions, httpsCallable } = require('firebase/functions');
const { getFirestore, doc, getDoc } = require('firebase/firestore');

const code = process.argv[2];
if (!/^[A-Z2-9]{8}$/.test(code ?? '')) {
  console.error('Usage: node security/smoke-production.cjs INVITE_CODE');
  process.exit(2);
}

const app = initializeApp(webConfig(), `production-smoke-${Date.now()}`);

async function run() {
  const auth = getAuth(app);
  const functions = getFunctions(app, 'us-west1');
  const db = getFirestore(app);
  let lobbyId;
  try {
    await signInAnonymously(auth);
    const joined = await httpsCallable(functions, 'joinLobby')({ code, displayName: 'Smoke test guest' });
    lobbyId = joined.data.lobbyId;
    const lobby = (await getDoc(doc(db, 'lobbies', lobbyId))).data();
    assert.equal(lobby.visibility, 'private');
    assert.equal(lobby.seats.length, 2);
    assert(lobby.memberIds.includes(auth.currentUser.uid));
    await httpsCallable(functions, 'setReady')({ lobbyId, ready: true });
    const ready = (await getDoc(doc(db, 'lobbies', lobbyId))).data();
    assert(ready.seats.find((seat) => seat.uid === auth.currentUser.uid).ready);
    console.log('Production anonymous sign-in, join, private view, and ready checks passed.');
  } finally {
    if (lobbyId) await httpsCallable(functions, 'leaveLobby')({ lobbyId });
    await deleteApp(app);
  }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
