import { createHash, randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { z } from 'zod';
import { applyGameCommand, type GameCommand } from './game_commands';
import { createGameState, privateHand, publicGame, type GameState } from './game_state';
import { submitGameCommandSchema } from './game_wire';
import {
  canStart,
  createLobbySchema,
  inviteCode,
  joinLobbySchema,
  joinSeat,
  leaveSeat,
  setSeatReady,
  type Lobby,
} from './lobby';

initializeApp();
setGlobalOptions({ region: 'us-west1', maxInstances: 20, memory: '256MiB' });
const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

function authenticated(uid: string | undefined): string {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in before joining a game.');
  return uid;
}
function parse<T>(schema: z.ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) throw new HttpsError('invalid-argument', 'Check the submitted fields.');
  return result.data;
}
function asCallError(error: unknown): never {
  if (error instanceof HttpsError) throw error;
  if (error instanceof Error) throw new HttpsError('failed-precondition', error.message);
  throw new HttpsError('internal', 'The operation could not be completed.');
}

export const createLobby = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const input = parse(createLobbySchema, request.data);
  const lobbyId = randomUUID();
  const now = Date.now();
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = inviteCode();
    const lobby: Lobby = {
      id: lobbyId, name: input.name, code, visibility: input.visibility, status: 'waiting',
      maxPlayers: input.maxPlayers, hostId: uid,
      seats: [{ uid, name: input.displayName, color: 'ember', ready: false }],
      memberIds: [uid], timer: input.timer, createdAt: now, updatedAt: now,
    };
    const codeRef = db.doc(`lobbyCodes/${code}`);
    const lobbyRef = db.doc(`lobbies/${lobbyId}`);
    const created = await db.runTransaction(async (transaction) => {
      if ((await transaction.get(codeRef)).exists) return false;
      transaction.create(codeRef, { lobbyId });
      transaction.create(lobbyRef, lobby);
      return true;
    });
    if (created) return { lobbyId, code };
  }
  throw new HttpsError('resource-exhausted', 'Could not create a unique invite code.');
});

export const joinLobby = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const input = parse(joinLobbySchema, request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      const lookup = await transaction.get(db.doc(`lobbyCodes/${input.code}`));
      if (!lookup.exists) throw new HttpsError('not-found', 'Invite code not found.');
      const lobbyRef = db.doc(`lobbies/${lookup.data()!.lobbyId as string}`);
      const snapshot = await transaction.get(lobbyRef);
      if (!snapshot.exists) throw new HttpsError('not-found', 'This lobby no longer exists.');
      const lobby = snapshot.data() as Lobby;
      const updated = joinSeat(lobby, uid, input.displayName, Date.now());
      if (updated !== lobby) transaction.update(lobbyRef, { seats: updated.seats, memberIds: updated.memberIds, updatedAt: updated.updatedAt });
      return { lobbyId: lobby.id };
    });
  } catch (error) { return asCallError(error); }
});

export const leaveLobby = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const { lobbyId } = parse(z.object({ lobbyId: z.string().uuid() }), request.data);
  try {
    await db.runTransaction(async (transaction) => {
      const ref = db.doc(`lobbies/${lobbyId}`);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Lobby not found.');
      const next = leaveSeat(snapshot.data() as Lobby, uid, Date.now());
      transaction.update(ref, next);
      if (next.status === 'closed') transaction.delete(db.doc(`lobbyCodes/${next.code}`));
    });
    return { ok: true };
  } catch (error) { return asCallError(error); }
});

export const setReady = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const { lobbyId, ready } = parse(z.object({ lobbyId: z.string().uuid(), ready: z.boolean() }), request.data);
  try {
    await db.runTransaction(async (transaction) => {
      const ref = db.doc(`lobbies/${lobbyId}`);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Lobby not found.');
      const next = setSeatReady(snapshot.data() as Lobby, uid, ready, Date.now());
      transaction.update(ref, { seats: next.seats, updatedAt: next.updatedAt });
    });
    return { ok: true };
  } catch (error) { return asCallError(error); }
});

export const startGame = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const { lobbyId } = parse(z.object({ lobbyId: z.string().uuid() }), request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      const lobbyRef = db.doc(`lobbies/${lobbyId}`);
      const gameRef = db.doc(`games/${lobbyId}`);
      const stateRef = db.doc(`games/${lobbyId}/private/state`);
      const snapshot = await transaction.get(lobbyRef);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Lobby not found.');
      const lobby = snapshot.data() as Lobby;
      if (!canStart(lobby, uid)) {
        throw new HttpsError('failed-precondition', 'The host can start once every seated player is ready.');
      }
      if ((await transaction.get(gameRef)).exists) throw new HttpsError('already-exists', 'This match has already started.');
      const state = createGameState(lobby, Date.now());
      transaction.create(gameRef, publicGame(state));
      transaction.create(stateRef, { payload: JSON.stringify(state) });
      for (const memberUid of state.order) {
        transaction.create(db.doc(`games/${lobbyId}/hands/${memberUid}`), privateHand(state, memberUid));
      }
      transaction.update(lobbyRef, { status: 'playing', gameId: lobbyId, updatedAt: state.updatedAt });
      transaction.create(db.doc(`games/${lobbyId}/events/000000`), {
        uid, at: state.updatedAt, version: 0, summary: 'The match began.',
      });
      return { gameId: lobbyId };
    });
  } catch (error) { return asCallError(error); }
});

export const submitGameCommand = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const input = parse(submitGameCommandSchema, request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      const gameRef = db.doc(`games/${input.gameId}`);
      const stateRef = db.doc(`games/${input.gameId}/private/state`);
      const commandRef = db.doc(`games/${input.gameId}/commands/${input.commandId}`);
      const appliedCommand = await transaction.get(commandRef);
      if (appliedCommand.exists) {
        if (appliedCommand.data()?.uid !== uid) throw new HttpsError('permission-denied', 'Command ID belongs to another player.');
        return { version: appliedCommand.data()?.version, duplicate: true };
      }
      const snapshot = await transaction.get(stateRef);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Match not found.');
      const stored = snapshot.data()?.payload;
      if (typeof stored !== 'string') throw new HttpsError('internal', 'Match state is unavailable.');
      const state = JSON.parse(stored) as GameState;
      const result = applyGameCommand(state, uid, input.commandId, input.command as GameCommand, Date.now());
      if (!result.changed) return { version: state.version, duplicate: true };
      transaction.set(stateRef, { payload: JSON.stringify(result.state) });
      transaction.create(commandRef, { uid, version: result.state.version, at: result.state.updatedAt });
      transaction.set(gameRef, publicGame(result.state));
      for (const memberUid of result.state.order) {
        transaction.set(db.doc(`games/${input.gameId}/hands/${memberUid}`), privateHand(result.state, memberUid));
      }
      transaction.create(db.doc(`games/${input.gameId}/events/${String(result.state.version).padStart(6, '0')}`), {
        uid, at: result.state.updatedAt, version: result.state.version, summary: result.summary,
      });
      return { version: result.state.version };
    });
  } catch (error) { return asCallError(error); }
});

export const registerPushToken = onCall(async (request) => {
  const uid = authenticated(request.auth?.uid);
  const { token } = parse(z.object({ token: z.string().min(20).max(4096) }), request.data);
  const tokenId = createHash('sha256').update(token).digest('hex');
  await db.doc(`pushTokens/${uid}/devices/${tokenId}`).set({ token, updatedAt: Date.now() });
  return { ok: true };
});

export const notifyTurn = onDocumentWritten('games/{gameId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || after.status !== 'playing' || !after.actorUid ||
    (before?.actorUid === after.actorUid && before?.chapter === after.chapter)) return;
  const uid = after.actorUid as string;
  const devices = await db.collection(`pushTokens/${uid}/devices`).get();
  if (devices.empty) return;
  const tokens = devices.docs.map((device) => device.data().token as string);
  for (let index = 0; index < tokens.length; index += 500) {
    const batch = tokens.slice(index, index + 500);
    try {
      const result = await getMessaging().sendEachForMulticast({
        tokens: batch,
        notification: { title: 'ARCS · Your turn', body: `It is your turn in ${after.name as string}.` },
        data: { gameId: event.params.gameId },
        webpush: { fcmOptions: { link: `https://arcs-online-jeremiah-2026.web.app/game/${event.params.gameId}` } },
      });
      await Promise.all(result.responses.map(async (response, offset) => {
        if (!response.success && ['messaging/registration-token-not-registered',
          'messaging/invalid-registration-token'].includes(response.error?.code ?? '')) {
          const tokenId = createHash('sha256').update(batch[offset]).digest('hex');
          await db.doc(`pushTokens/${uid}/devices/${tokenId}`).delete();
        }
      }));
    } catch (error) {
      // Notifications are best-effort; a delivery outage cannot affect the match.
      console.error('Could not send turn notification', error);
    }
  }
});
