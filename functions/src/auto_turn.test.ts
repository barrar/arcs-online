import { describe, expect, it } from 'vitest';
import { actionCard } from './action_cards';
import { applyGameCommand } from './game_commands';
import { createGameWithSetup } from './game_state';
import type { Lobby } from './lobby';
import { setupChoices } from './setup';

function turn(suit: 'administration' | 'aggression') {
  const lobby: Lobby = {
    id: '00000000-0000-4000-8000-000000000001', name: 'Turn flow', code: 'ABCDEFGH',
    visibility: 'private', status: 'waiting', maxPlayers: 2, hostId: 'a',
    seats: ['a', 'b'].map((uid, index) => ({ uid, name: uid, color: index ? 'azure' : 'ember', ready: true })),
    memberIds: ['a', 'b'], timer: { mode: 'async', hours: 24 }, createdAt: 0, updatedAt: 0,
  };
  const state = createGameWithSetup(lobby, setupChoices(2)[0], 'a', 1000, () => 0);
  const play = { uid: 'a', card: actionCard(suit, 2), mode: 'lead' as const };
  state.mulliganPendingUid = null;
  state.round.lead = play;
  state.round.plays = [play];
  state.round.playedThisTurn = true;
  state.round.remainingPips = 1;
  return state;
}

describe('automatic turn completion', () => {
  it('still allows a player to end early with unused pips', () => {
    const state = turn('administration');
    state.round.remainingPips = 2;
    const usedOne = applyGameCommand(state, 'a', 'first-pip',
      { kind: 'pip', action: { kind: 'influence', courtIndex: 0 } }, 1001).state;
    expect(usedOne.round.actorUid).toBe('a');
    expect(usedOne.round.remainingPips).toBe(1);
    const ended = applyGameCommand(usedOne, 'a', 'early-end', { kind: 'end-turn' }, 1002).state;
    expect(ended.round.actorUid).toBe('b');
  });

  it('advances after the last pip is spent', () => {
    const state = turn('administration');
    const result = applyGameCommand(state, 'a', 'last-pip',
      { kind: 'pip', action: { kind: 'influence', courtIndex: 0 } }, 1001);
    expect(result.state.round.actorUid).toBe('b');
    expect(result.state.round.playedThisTurn).toBe(false);
    expect(result.summary).toContain('ended their turn');
  });

  it('waits for battle resolution after the last pip', () => {
    const state = turn('aggression');
    const systemId = setupChoices(2)[0].starting[0].a;
    state.systems[systemId].push({ id: 'b:test-city', owner: 'b', kind: 'city', damaged: false });
    const rolled = applyGameCommand(state, 'a', 'battle', { kind: 'pip', action: {
      kind: 'battle', systemId, defenderUid: 'b', dice: { assault: 0, skirmish: 1, raid: 0 },
    } }, 1001, () => 0).state;
    expect(rolled.round.actorUid).toBe('a');
    expect(rolled.pendingBattle?.phase).toBe('assign');
    const resolved = applyGameCommand(rolled, 'a', 'hits', { kind: 'assign-hits',
      assignment: { own: [], ships: [], buildings: [] } }, 1002).state;
    expect(resolved.pendingBattle).toBeUndefined();
    expect(resolved.round.actorUid).toBe('b');
  });

  it('offers resource rearrangement before advancing', () => {
    const state = turn('administration');
    state.players.a.citiesOut = 2;
    const systemId = setupChoices(2)[0].starting[0].a;
    const city = state.systems[systemId].find((piece) => piece.owner === 'a' && piece.kind === 'city')!;
    const taxed = applyGameCommand(state, 'a', 'tax',
      { kind: 'pip', action: { kind: 'tax', cityId: city.id } }, 1001).state;
    expect(taxed.turn.canRearrange).toBe(true);
    expect(taxed.round.actorUid).toBe('a');
    const arranged = applyGameCommand(taxed, 'a', 'rearrange',
      { kind: 'rearrange-resources', slots: taxed.players.a.resources.slice(0, 4) }, 1002).state;
    expect(arranged.round.actorUid).toBe('b');
  });
});
