import { describe, expect, it } from 'vitest';
import { createBoard } from './board';
import { applyGameCommand, type GameCommand } from './game_commands';
import { createGameWithSetup, privateHand, publicGame } from './game_state';
import type { Lobby } from './lobby';
import { setupVariants, type SetupVariant } from './setup';

function lobby(count: number): Lobby {
  const seats = Array.from({ length: count }, (_, index) => ({
    uid: `player-${index + 1}`, name: `Player ${index + 1}`,
    color: ['ember', 'azure', 'gold', 'violet'][index], ready: true,
  }));
  return {
    id: '00000000-0000-4000-8000-000000000001', name: 'Rules verification',
    code: 'ABCDEFGH', visibility: 'private', status: 'waiting',
    maxPlayers: count, hostId: seats[0].uid, seats, memberIds: seats.map((seat) => seat.uid),
    timer: { mode: 'async', hours: 24 }, createdAt: 0, updatedAt: 0,
  };
}

function create(variant: SetupVariant) {
  return createGameWithSetup(lobby(variant.playerCount), variant, 'player-1', 1000, () => 0);
}

describe('authoritative base-game state', () => {
  it('uses all twelve setup cards for exact starting placements and planet resources', () => {
    for (const variant of setupVariants) {
      const state = create(variant);
      const board = createBoard(variant.activeClusters);
      expect(state.setupId).toBe(variant.id);
      for (const [index, position] of variant.starting.entries()) {
        const uid = `player-${index + 1}`;
        const at = (systemId: keyof typeof state.systems, kind: string) =>
          state.systems[systemId].filter((piece) => piece.owner === uid && piece.kind === kind).length;
        expect(at(position.a, 'city')).toBe(1);
        expect(at(position.a, 'ship')).toBeGreaterThanOrEqual(3);
        expect(at(position.b, 'starport')).toBe(1);
        expect(at(position.b, 'ship')).toBeGreaterThanOrEqual(3);
        for (const systemId of position.c) expect(at(systemId, 'ship')).toBeGreaterThanOrEqual(2);
        expect(state.players[uid].resources.slice(0, 2)).toEqual([
          board.planets[position.a].resource, board.planets[position.b].resource,
        ]);
        expect(state.round.hands[uid]).toHaveLength(6);
      }
      expect(state.courtRow).toHaveLength(variant.playerCount === 2 ? 3 : 4);
    }
  });

  it('keeps hands, deck order and Farseers inspection out of public state', () => {
    const state = create(setupVariants[0]);
    state.pendingFarseers = { uid: 'player-1', targetUid: 'player-2' };
    const publicView = publicGame(state);
    const text = JSON.stringify(publicView);
    expect(Object.hasOwn(publicView, 'actionDiscard')).toBe(false);
    expect(Object.hasOwn(publicView, 'courtDeck')).toBe(false);
    expect(text).not.toContain('pendingFarseers');
    expect(text).not.toContain('recentCommands');
    expect((publicView.round as { hands: Record<string, number> }).hands['player-2']).toBe(6);
    expect(privateHand(state, 'player-1').farseersReveal).toEqual({
      targetUid: 'player-2', cards: state.round.hands['player-2'].map((card) => card.id),
    });
    expect(privateHand(state, 'player-2').farseersReveal).toBeNull();
  });

  it('ends an overdue match only after every other seat approves, without a winner', () => {
    let state = create(setupVariants.find((variant) => variant.playerCount === 3)!);
    state.mulliganPendingUid = null;
    const overdue = state.round.actorUid!;
    const voters = state.order.filter((uid) => uid !== overdue);
    expect(() => applyGameCommand(state, voters[0], 'early-vote',
      { kind: 'vote-kick', targetUid: overdue }, state.deadlineMs - 1)).toThrow('not overdue');
    state = applyGameCommand(state, voters[0], 'first-vote',
      { kind: 'vote-kick', targetUid: overdue }, state.deadlineMs).state;
    expect(state.status).toBe('playing');
    expect(state.vote?.approvals).toEqual([voters[0]]);
    state = applyGameCommand(state, voters[1], 'second-vote',
      { kind: 'vote-kick', targetUid: overdue }, state.deadlineMs + 1).state;
    expect(state.status).toBe('terminated');
    expect(state.winnerUid).toBeNull();
    expect(state.termination?.targetUid).toBe(overdue);
    expect(state.systems).toEqual(create(setupVariants.find((variant) => variant.playerCount === 3)!).systems);
  });

  for (const count of [2, 3, 4] as const) {
    it(`finishes a legal ${count}-player match after five chapters without scored ambitions`, () => {
      let state = create(setupVariants.find((variant) => variant.playerCount === count)!);
      let step = 0;
      while (state.status === 'playing' && step < 400) {
        let uid: string;
        let command: GameCommand;
        if (state.mulliganPendingUid) {
          uid = state.mulliganPendingUid;
          command = { kind: 'mulligan', replace: false };
        } else {
          uid = state.round.actorUid!;
          if (!uid) throw new Error('A playing game must have a decision maker.');
          const cards = state.round.hands[uid];
          if (state.round.playedThisTurn) command = { kind: 'end-turn' };
          else if (cards.length === 0) command = { kind: 'pass' };
          else {
            command = { kind: 'play', cardId: cards[0].id,
              mode: state.round.lead ? 'copy' : 'lead' };
          }
        }
        state = applyGameCommand(state, uid, `step-${step}`, command, 1001 + step, () => 0).state;
        step++;
      }
      expect(step).toBeLessThan(400);
      expect(state.chapter).toBe(5);
      expect(state.status).toBe('finished');
      expect(state.winnerUid).toBeTruthy();
      expect(state.order.map((uid) => state.players[uid].power)).toEqual(Array(count).fill(0));
    });

    it(`scores ambitions through a complete ${count}-player match`, () => {
      let state = create(setupVariants.find((variant) => variant.playerCount === count)!);
      // A reachable midgame position with each ambition represented ensures
      // chapter scoring is exercised regardless of the deterministic hand order.
      const scorer = state.players[state.order[0]];
      scorer.guilds.push('ARCS-BC01', 'ARCS-BC07', 'ARCS-BC19', 'ARCS-BC21');
      scorer.trophies.push({ id: 'scoring-trophy', owner: state.order[1], kind: 'ship', damaged: true });
      scorer.captiveOwners.push(state.order[1]);
      const ambitions: Record<number, 'tycoon' | 'tyrant' | 'warlord' | 'keeper' | 'empath'> = {
        2: 'tycoon', 3: 'tyrant', 4: 'warlord', 5: 'keeper', 6: 'empath', 7: 'tycoon',
      };
      let step = 0;
      while (state.status === 'playing' && step < 400) {
        const uid = state.mulliganPendingUid ?? state.round.actorUid;
        if (!uid) throw new Error('A playing game must have a decision maker.');
        let command: GameCommand;
        if (state.mulliganPendingUid) command = { kind: 'mulligan', replace: false };
        else if (state.round.playedThisTurn) command = { kind: 'end-turn' };
        else if (state.round.hands[uid].length === 0) command = { kind: 'pass' };
        else {
          const card = state.round.hands[uid][0];
          const lead = !state.round.lead;
          command = { kind: 'play', cardId: card.id, mode: lead ? 'lead' : 'copy',
            ...(lead && state.round.availableAmbitions > 0 && ambitions[card.rank]
              ? { declare: ambitions[card.rank] } : {}) };
        }
        state = applyGameCommand(state, uid, `scored-${count}-${step}`, command, 2000 + step, () => 0).state;
        step++;
      }
      expect(step).toBeLessThan(400);
      expect(state.status).toBe('finished');
      expect(state.winnerUid).toBeTruthy();
      expect(state.order.some((uid) => state.players[uid].power > 0)).toBe(true);
      expect(state.lastScoring?.details).toBeDefined();
    });
  }
});
