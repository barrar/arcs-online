import { randomBytes } from 'node:crypto';
import { z } from 'zod';

export const timerSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('live'), minutes: z.number().int().min(2).max(10) }),
  z.object({ mode: z.literal('async'), hours: z.union([z.literal(24), z.literal(48)]) }),
]);
export type Timer = z.infer<typeof timerSchema>;

export const createLobbySchema = z.object({
  name: z.string().trim().min(1).max(60),
  visibility: z.enum(['public', 'private']),
  maxPlayers: z.number().int().min(2).max(4),
  timer: timerSchema,
  displayName: z.string().trim().min(1).max(32),
});
export const joinLobbySchema = z.object({ code: z.string().trim().toUpperCase().regex(/^[A-Z2-9]{8}$/), displayName: z.string().trim().min(1).max(32) });

export type Seat = { uid: string; name: string; color: string; ready: boolean };
export type Lobby = {
  id: string;
  name: string;
  code: string;
  visibility: 'public' | 'private';
  status: 'waiting' | 'playing' | 'closed';
  maxPlayers: number;
  hostId: string;
  seats: Seat[];
  memberIds: string[];
  timer: Timer;
  createdAt: number;
  updatedAt: number;
};

const colors = ['ember', 'azure', 'gold', 'violet'];
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function inviteCode(bytes: Uint8Array = randomBytes(8)): string {
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join('');
}
export function timerMilliseconds(timer: Timer): number {
  return timer.mode === 'live' ? timer.minutes * 60_000 : timer.hours * 3_600_000;
}
export function joinSeat(lobby: Lobby, uid: string, name: string, now: number): Lobby {
  if (lobby.status !== 'waiting') throw new Error('This lobby has already started.');
  if (lobby.memberIds.includes(uid)) return lobby;
  if (lobby.seats.length >= lobby.maxPlayers) throw new Error('This lobby is full.');
  const nextColor = colors.find((color) => !lobby.seats.some((seat) => seat.color === color));
  if (!nextColor) throw new Error('No color is available.');
  const seats = [...lobby.seats, { uid, name, color: nextColor, ready: false }];
  return { ...lobby, seats, memberIds: seats.map((seat) => seat.uid), updatedAt: now };
}
export function leaveSeat(lobby: Lobby, uid: string, now: number): Lobby {
  if (lobby.status !== 'waiting') throw new Error('A game in progress cannot be left.');
  const seats = lobby.seats.filter((seat) => seat.uid !== uid);
  if (seats.length === lobby.seats.length) throw new Error('You are not seated in this lobby.');
  return {
    ...lobby,
    seats,
    memberIds: seats.map((seat) => seat.uid),
    hostId: lobby.hostId === uid ? (seats[0]?.uid ?? '') : lobby.hostId,
    status: seats.length === 0 ? 'closed' : 'waiting',
    updatedAt: now,
  };
}
export function setSeatReady(lobby: Lobby, uid: string, ready: boolean, now: number): Lobby {
  if (lobby.status !== 'waiting') throw new Error('The game has already started.');
  if (!lobby.memberIds.includes(uid)) throw new Error('You are not seated in this lobby.');
  return { ...lobby, seats: lobby.seats.map((seat) => seat.uid === uid ? { ...seat, ready } : seat), updatedAt: now };
}
export function canStart(lobby: Lobby, uid: string): boolean {
  return lobby.status === 'waiting' && lobby.hostId === uid && lobby.seats.length >= 2 && lobby.seats.every((seat) => seat.ready);
}
