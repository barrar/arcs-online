import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2';
import { z } from 'zod';
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
  const snapshot = await db.doc(`lobbies/${lobbyId}`).get();
  if (!snapshot.exists) throw new HttpsError('not-found', 'Lobby not found.');
  if (!canStart(snapshot.data() as Lobby, uid)) {
    throw new HttpsError('failed-precondition', 'The host can start once every seated player is ready.');
  }
  // A full base-game rules engine must be in place before creating authoritative games.
  throw new HttpsError('unimplemented', 'The ARCS rules engine is still being implemented.');
});
