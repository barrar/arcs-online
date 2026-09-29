const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously, signOut,
  linkWithCredential, signInWithCredential, signInWithEmailAndPassword,
  GoogleAuthProvider, EmailAuthProvider } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getFirestore, connectFirestoreEmulator, doc, getDoc } = require('firebase/firestore');

const projectId = 'arcs-online-jeremiah-2026';
async function client(label) {
  const app = initializeApp({ apiKey: 'emulator-key', projectId, appId: `auth-${label}` }, `auth-${label}`);
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
  const suffix = randomUUID();
  const [host, rival, outsider, emailUser] = await Promise.all([
    client(`google-${suffix}`), client(`rival-${suffix}`),
    client(`outsider-${suffix}`), client(`email-${suffix}`),
  ]);
  const returners = [];
  try {
    const originalUid = host.auth.currentUser.uid;
    const created = await host.call('createLobby', {
      name: 'Account-link check', displayName: 'Host', visibility: 'private', maxPlayers: 2,
      timer: { mode: 'async', hours: 24 },
    });
    await rival.call('joinLobby', { code: created.code, displayName: 'Rival' });
    await Promise.all([
      host.call('setReady', { lobbyId: created.lobbyId, ready: true }),
      rival.call('setReady', { lobbyId: created.lobbyId, ready: true }),
    ]);
    await host.call('startGame', { lobbyId: created.lobbyId });
    const gameRef = doc(host.db, 'games', created.lobbyId);
    const handRef = doc(host.db, 'games', created.lobbyId, 'hands', originalUid);
    assert.equal((await getDoc(handRef)).data().cards.length, 6);

    // The Auth emulator accepts a mock Google ID token documented for local IDP tests.
    const google = GoogleAuthProvider.credential(JSON.stringify({
      sub: `arcs-${suffix}`, email: `arcs-${suffix}@example.test`, email_verified: true,
    }));
    await linkWithCredential(host.auth.currentUser, google);
    assert.equal(host.auth.currentUser.uid, originalUid);
    await signOut(host.auth);
    const googleReturn = await client(`google-return-${suffix}`);
    returners.push(googleReturn);
    await signOut(googleReturn.auth);
    await signInWithCredential(googleReturn.auth, google);
    assert.equal(googleReturn.auth.currentUser.uid, originalUid);
    assert.equal((await getDoc(doc(googleReturn.db, 'games', created.lobbyId))).data().id, created.lobbyId);
    assert.equal((await getDoc(doc(googleReturn.db, 'games', created.lobbyId, 'hands', originalUid))).data().cards.length, 6);
    await assert.rejects(getDoc(doc(outsider.db, 'games', created.lobbyId, 'hands', originalUid)));

    const emailUid = emailUser.auth.currentUser.uid;
    const email = `arcs-email-${suffix}@example.test`;
    const password = `Local-only-${suffix}`;
    const emailGame = await emailUser.call('createLobby', {
      name: 'Email return check', displayName: 'Email guest', visibility: 'private', maxPlayers: 2,
      timer: { mode: 'async', hours: 24 },
    });
    await outsider.call('joinLobby', { code: emailGame.code, displayName: 'Rival' });
    await Promise.all([emailUser.call('setReady', { lobbyId: emailGame.lobbyId, ready: true }),
      outsider.call('setReady', { lobbyId: emailGame.lobbyId, ready: true })]);
    await emailUser.call('startGame', { lobbyId: emailGame.lobbyId });
    await linkWithCredential(emailUser.auth.currentUser, EmailAuthProvider.credential(email, password));
    await signOut(emailUser.auth);
    const emailReturn = await client(`email-return-${suffix}`);
    returners.push(emailReturn);
    await signOut(emailReturn.auth);
    await signInWithEmailAndPassword(emailReturn.auth, email, password);
    assert.equal(emailReturn.auth.currentUser.uid, emailUid);
    assert.equal((await getDoc(doc(emailReturn.db, 'games', emailGame.lobbyId))).data().id, emailGame.lobbyId);
    assert.equal((await getDoc(doc(emailReturn.db, 'games', emailGame.lobbyId, 'hands', emailUid))).data().cards.length, 6);
    await assert.rejects(getDoc(doc(googleReturn.db, 'games', emailGame.lobbyId, 'hands', emailUid)));
    console.log('Google and email guest linking, fresh-client sign-in, saved-game access, and hidden-hand isolation passed.');
  } finally {
    await Promise.all([host, rival, outsider, emailUser, ...returners].map((item) => deleteApp(item.app)));
  }
}

check().catch((error) => { console.error(error); process.exitCode = 1; });
