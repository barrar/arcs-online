import { describe, expect, it } from 'vitest';
import { canStart, inviteCode, joinSeat, leaveSeat, setSeatReady, type Lobby } from './lobby';
import { advanceActor, castKickVote, type ActiveSession } from './session';

const lobby = (players = 2): Lobby => ({
  id: 'one', name: 'First game', code: 'ABCDEFGH', visibility: 'private', status: 'waiting',
  maxPlayers: players, hostId: 'a', seats: [{ uid: 'a', name: 'A', color: 'ember', ready: false }],
  memberIds: ['a'], timer: { mode: 'live', minutes: 5 }, createdAt: 1, updatedAt: 1,
});

describe('lobby lifecycle', () => {
  it('uses eight unambiguous invitation characters', () => {
    expect(inviteCode(new Uint8Array(8))).toMatch(/^[A-Z2-9]{8}$/);
  });
  it('never double-seats one account or overfills a lobby', () => {
    const joined = joinSeat(lobby(), 'b', 'B', 2);
    expect(joinSeat(joined, 'b', 'B', 3)).toEqual(joined);
    expect(() => joinSeat(joined, 'c', 'C', 4)).toThrow('full');
  });
  it('requires every occupied seat to be ready and the host to start', () => {
    const joined = joinSeat(lobby(), 'b', 'B', 2);
    expect(canStart(joined, 'a')).toBe(false);
    const ready = setSeatReady(setSeatReady(joined, 'a', true, 3), 'b', true, 4);
    expect(canStart(ready, 'a')).toBe(true);
    expect(canStart(ready, 'b')).toBe(false);
  });
  it('transfers hosting when the host leaves before start', () => {
    const joined = joinSeat(lobby(), 'b', 'B', 2);
    expect(leaveSeat(joined, 'a', 3).hostId).toBe('b');
  });
});

describe('overdue vote', () => {
  const session: ActiveSession = { memberIds: ['a', 'b', 'c'], actorUid: 'a', deadlineMs: 100, status: 'playing' };
  it('rejects votes before the deadline or by the overdue player', () => {
    expect(() => castKickVote(session, 'b', 'a', 99)).toThrow('not overdue');
    expect(() => castKickVote(session, 'a', 'a', 100)).toThrow('themselves');
  });
  it('requires every other seat and awards no winner', () => {
    const first = castKickVote(session, 'b', 'a', 100);
    expect(first.status).toBe('playing');
    expect(castKickVote(first, 'b', 'a', 101).vote?.approvals).toEqual(['b']);
    const last = castKickVote(first, 'c', 'a', 102);
    expect(last.status).toBe('terminated');
    expect(last.termination?.targetUid).toBe('a');
    expect(last).not.toHaveProperty('winner');
  });
  it('clears an unfinished vote when the turn advances', () => {
    const first = castKickVote(session, 'b', 'a', 100);
    const next = advanceActor(first, 'b', 110, 120_000);
    expect(next.vote).toBeUndefined();
    expect(() => castKickVote(next, 'c', 'a', 110)).toThrow('not overdue');
  });
});
