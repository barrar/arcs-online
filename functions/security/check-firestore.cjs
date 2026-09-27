const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator.');
async function check() {
const environment = await initializeTestEnvironment({
  projectId: 'arcs-rules-test',
  firestore: { rules: readFileSync(join(__dirname, '../../firestore.rules'), 'utf8') },
});
try {
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await firestore.doc('lobbies/public').set({
      visibility: 'public', status: 'waiting', memberIds: ['alice'], createdAt: 2,
    });
    await firestore.doc('lobbies/private').set({
      visibility: 'private', status: 'waiting', memberIds: ['alice'], createdAt: 1,
    });
    await firestore.doc('games/match').set({ memberIds: ['alice', 'bob'], updatedAt: 1 });
    await firestore.doc('games/match/hands/alice').set({ cards: ['secret-alice'] });
    await firestore.doc('games/match/hands/bob').set({ cards: ['secret-bob'] });
    await firestore.doc('lobbyCodes/SECRET11').set({ lobbyId: 'private' });
  });
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const outsider = environment.authenticatedContext('outsider').firestore();
  const anonymous = environment.unauthenticatedContext().firestore();

  assert.equal((await assertSucceeds(alice.doc('lobbies/private').get())).exists, true);
  await assertFails(outsider.doc('lobbies/private').get());
  await assertFails(anonymous.doc('lobbies/public').get());
  assert.equal((await assertSucceeds(bob.collection('lobbies')
    .where('visibility', '==', 'public').where('status', '==', 'waiting').get())).size, 1);
  await assertFails(bob.collection('lobbies').get());
  await assertFails(alice.doc('lobbyCodes/SECRET11').get());
  assert.equal((await assertSucceeds(alice.doc('games/match/hands/alice').get())).data().cards[0], 'secret-alice');
  await assertFails(alice.doc('games/match/hands/bob').get());
  await assertFails(outsider.doc('games/match').get());
  await assertFails(alice.doc('games/match/hands/alice').set({ cards: ['forged'] }));
  await assertFails(alice.doc('lobbies/private').set({ visibility: 'public' }));
  console.log('Firestore authorization checks passed.');
} finally {
  await environment.cleanup();
}
}
check().catch(error => { console.error(error); process.exitCode = 1; });
