import { describe, expect, it } from 'vitest';
import { actionCard } from './action_cards';
import { placePiece, systemController } from './game_actions';
import { beginBattle, provokeOutrage } from './game_battle';
import { applyGameCommand } from './game_commands';
import { applyGuildAction, applyGuildPrelude, stealFromRival } from './game_guild';
import { createGameWithSetup, scoringPlayers } from './game_state';
import type { Lobby } from './lobby';
import { setupChoices } from './setup';

// Printed effects: https://cards.buriedgiant.com/ (ARCS-BC01–25).
// This suite checks each Guild's distinct behavior, including shared effects
// across the five Loyal cards, four Unions, and four ship-placement cards.
function game() {
  const seats = ['a', 'b'].map((uid, index) => ({
    uid, name: uid, color: index ? 'azure' : 'ember', ready: true,
  }));
  const lobby: Lobby = {
    id: '00000000-0000-4000-8000-000000000001', name: 'Guild coverage',
    code: 'ABCDEFGH', visibility: 'private', status: 'waiting', maxPlayers: 2,
    hostId: 'a', seats, memberIds: ['a', 'b'], timer: { mode: 'async', hours: 24 },
    createdAt: 0, updatedAt: 0,
  };
  return createGameWithSetup(lobby, setupChoices(2)[0], 'a', 1000, () => 0);
}

function prelude(cardId: string) {
  const state = game();
  state.players.a.guilds.push(cardId);
  state.round.actorUid = 'a';
  state.round.playedThisTurn = true;
  state.turn.preludeOpen = true;
  return state;
}

describe('every base Guild card (official card library ARCS-BC01–25)', () => {
  it.each([
    ['ARCS-BC01', 'material'], ['ARCS-BC07', 'fuel'], ['ARCS-BC15', 'weapon'],
    ['ARCS-BC19', 'psionic'], ['ARCS-BC21', 'relic'],
  ] as const)('%s survives its matching Outrage and retains its scoring icon', (cardId, resource) => {
    const state = game();
    state.players.a.guilds.push(cardId);
    provokeOutrage(state, 'a', resource);
    expect(state.players.a.guilds).toContain(cardId);
    expect(scoringPlayers(state).find((player) => player.uid === 'a')!.guildIcons).toContain(resource);
    expect(state.players.a.outrage).toContain(resource);
  });

  it.each([
    ['ARCS-BC02', 'material', 'manufacture'],
    ['ARCS-BC09', 'fuel', 'synthesize'],
  ] as const)('%s gains its printed resource in both Build and Prelude', (cardId, resource, action) => {
    const build = game();
    build.players.a.guilds.push(cardId);
    applyGuildAction(build, 'a', { kind: action, slot: 2 });
    expect(build.players.a.resources[2]).toBe(resource);

    const state = prelude(cardId);
    state.players.a.resources[0] = null;
    state.players.a.resources[1] = null;
    applyGuildPrelude(state, 'a', { kind: 'interest', cardId, placements: [{ slot: 0 }, { slot: 1 }] });
    expect(state.players.a.resources.slice(0, 2)).toEqual([resource, resource]);
    expect(state.players.a.guilds).not.toContain(cardId);
    expect(state.courtDiscard).toContain(cardId);
  });

  it.each([
    ['ARCS-BC03', 'material'], ['ARCS-BC06', 'fuel'],
  ] as const)('%s steals only its matching resource in Prelude', (cardId, resource) => {
    const state = prelude(cardId);
    state.players.b.resources[0] = resource;
    applyGuildPrelude(state, 'a', { kind: 'cartel', cardId,
      steal: { kind: 'resource', rivalUid: 'b', rivalSlot: 0, destinationSlot: 2 } });
    expect(state.players.a.resources[2]).toBe(resource);
    expect(state.players.b.resources[0]).toBeNull();
    expect(state.players.a.guilds).not.toContain(cardId);
  });

  it.each([
    ['ARCS-BC04', 'administration'], ['ARCS-BC05', 'construction'],
    ['ARCS-BC10', 'mobilization'], ['ARCS-BC11', 'aggression'],
  ] as const)('%s reserves a face-up card of its suit, not another suit', (cardId, suit) => {
    const state = prelude(cardId);
    const matching = actionCard(suit, 2);
    const other = actionCard(suit === 'administration' ? 'construction' : 'administration', 3);
    state.round.plays.push({ uid: 'a', card: matching, mode: 'lead' },
      { uid: 'b', card: other, mode: 'pivot' });
    expect(() => applyGuildPrelude(state, 'a', { kind: 'union', cardId, actionCardId: other.id }))
      .toThrow('face-up');
    applyGuildPrelude(state, 'a', { kind: 'union', cardId, actionCardId: matching.id });
    expect(state.unionReservations).toEqual([{ uid: 'a', guildId: cardId, actionCardId: matching.id }]);
  });

  it('Gatekeepers places one ship per active gate and grants two extra gate battle dice', () => {
    const state = prelude('ARCS-BC08');
    const gates = state.activeClusters.map((cluster) => `${cluster}:gate` as const);
    const before = gates.map((gate) => state.systems[gate].filter((piece) => piece.owner === 'a' && piece.kind === 'ship').length);
    applyGuildPrelude(state, 'a', { kind: 'gatekeepers', gateIds: gates });
    for (const [index, gate] of gates.entries()) {
      expect(state.systems[gate].filter((piece) => piece.owner === 'a' && piece.kind === 'ship')).toHaveLength(before[index] + 1);
    }
    const battle = game();
    battle.players.a.guilds.push('ARCS-BC08');
    placePiece(battle, 'a', 'ship', gates[0]);
    placePiece(battle, 'b', 'ship', gates[0]);
    beginBattle(battle, 'a', { systemId: gates[0], defenderUid: 'b',
      dice: { assault: 3, skirmish: 0, raid: 0 } }, () => 0);
    expect(battle.pendingBattle?.faces).toHaveLength(3);
  });

  it.each(['ARCS-BC12', 'ARCS-BC13', 'ARCS-BC14', 'ARCS-BC15'] as const)(
    '%s places three ships in a controlled system', (cardId) => {
      const state = prelude(cardId);
      const systemId = setupChoices(2)[0].starting[0].a;
      expect(systemController(state, systemId)).toBe('a');
      const before = state.systems[systemId].filter((piece) => piece.owner === 'a' && piece.kind === 'ship').length;
      applyGuildPrelude(state, 'a', { kind: 'place-ships', cardId, systemId });
      expect(state.systems[systemId].filter((piece) => piece.owner === 'a' && piece.kind === 'ship')).toHaveLength(before + 3);
      expect(state.players.a.guilds).not.toContain(cardId);
    });

  it('Prison Wardens Pressgang returns Captives for resources and Execute turns them into Trophies', () => {
    const state = game();
    state.players.a.guilds.push('ARCS-BC12');
    state.players.a.captiveOwners.push('b', 'b');
    applyGuildAction(state, 'a', { kind: 'pressgang', captiveOwners: ['b'],
      gains: [{ resource: 'relic', slot: 2 }] });
    expect(state.players.a.resources[2]).toBe('relic');
    expect(state.players.a.captiveOwners).toEqual(['b']);
    applyGuildAction(state, 'a', { kind: 'execute', captiveOwners: ['b'] });
    expect(state.players.a.captiveOwners).toHaveLength(0);
    expect(state.players.a.trophies.at(-1)).toMatchObject({ owner: 'b', kind: 'agent' });
  });

  it('Court Enforcers abducts only when Weapon icons exceed Rival agents', () => {
    const state = game();
    state.players.a.guilds.push('ARCS-BC14');
    state.courtRow[0].agents.b = 1;
    expect(() => applyGuildAction(state, 'a', { kind: 'abduct', courtIndex: 0 })).toThrow('fewer');
    state.players.a.resources[2] = 'weapon';
    applyGuildAction(state, 'a', { kind: 'abduct', courtIndex: 0 });
    expect(state.players.a.captiveOwners).toContain('b');
    expect(state.courtRow[0].agents.b).toBeUndefined();
  });

  it('Lattice Spies seizes only before any other Prelude action', () => {
    const state = prelude('ARCS-BC16');
    state.round.initiativeUid = 'b';
    applyGuildPrelude(state, 'a', { kind: 'lattice-spies' });
    expect(state.round.initiativeUid).toBe('a');
    expect(state.players.a.guilds).not.toContain('ARCS-BC16');
    const late = prelude('ARCS-BC16');
    late.round.initiativeUid = 'b';
    late.turn.spentResources.push('fuel');
    expect(() => applyGuildPrelude(late, 'a', { kind: 'lattice-spies' })).toThrow('before any other action');
  });

  it('Farseers draws from the bottom after discarding action cards', () => {
    const state = prelude('ARCS-BC17');
    const discardId = state.round.hands.a[0].id;
    const bottom = actionCard('administration', 2);
    const next = actionCard('construction', 3);
    state.actionDiscard = [bottom, next, actionCard('aggression', 4)];
    applyGuildPrelude(state, 'a', { kind: 'farseers', discardActionCardIds: [discardId] });
    expect(state.round.hands.a.slice(-2).map((card) => card.id)).toEqual([bottom.id, next.id]);
    expect(state.actionDiscard.at(-1)?.id).toBe(discardId);
  });

  it('Secret Order keeps the declared Keeper or Empath card rank', () => {
    for (const [rank, ambition] of [[5, 'keeper'], [6, 'empath']] as const) {
      const state = game();
      state.mulliganPendingUid = null;
      state.players.a.guilds.push('ARCS-BC18');
      const card = actionCard('administration', rank);
      state.round.hands.a = [card];
      const next = applyGameCommand(state, 'a', `secret-${rank}`,
        { kind: 'play', cardId: card.id, mode: 'lead', declare: ambition }, 1001).state;
      expect(next.round.lead?.retainRank).toBe(true);
    }
  });

  it('Silver-Tongues discards to steal a Rival Guild card', () => {
    const state = prelude('ARCS-BC20');
    state.players.b.guilds.push('ARCS-BC02');
    applyGuildPrelude(state, 'a', { kind: 'silver-tongues',
      steal: { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC02' } });
    expect(state.players.a.guilds).toContain('ARCS-BC02');
    expect(state.players.a.guilds).not.toContain('ARCS-BC20');
  });

  it('Sworn Guardians blocks theft until the Guardians themselves are buried', () => {
    const state = game();
    state.players.b.guilds.push('ARCS-BC22', 'ARCS-BC02');
    expect(() => stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC02' }))
      .toThrow('Sworn Guardians');
    stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC22' });
    expect(state.courtDeck.at(-1)).toBe('ARCS-BC22');
    stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC02' });
    expect(state.players.a.guilds).toContain('ARCS-BC02');
  });

  it('Elder Broker gains three different resources and trades at a controlled Rival city', () => {
    const state = prelude('ARCS-BC23');
    state.players.a.citiesOut = 3;
    applyGuildPrelude(state, 'a', { kind: 'elder-broker', slots: [2, 3, 4] });
    expect(state.players.a.resources.slice(2, 5)).toEqual(['material', 'fuel', 'weapon']);

    const trade = game();
    trade.players.a.guilds.push('ARCS-BC23');
    trade.players.a.resources[2] = 'psionic';
    const citySystem = setupChoices(2)[0].starting[1].a;
    const city = trade.systems[citySystem].find((piece) => piece.owner === 'b' && piece.kind === 'city')!;
    for (let index = 0; index < 4; index++) placePiece(trade, 'a', 'ship', citySystem);
    expect(systemController(trade, citySystem)).toBe('a');
    const taken = trade.players.b.resources[0];
    applyGuildAction(trade, 'a', { kind: 'trade', cityId: city.id, giveSlot: 2, takeSlot: 0 });
    expect(trade.players.a.resources[2]).toBe(taken);
    expect(trade.players.b.resources[0]).toBe('psionic');
  });

  it('Relic Fence converts one resource to a Relic only once per turn', () => {
    const state = prelude('ARCS-BC24');
    applyGuildPrelude(state, 'a', { kind: 'relic-fence', discardSlot: 0, destinationSlot: 0 });
    expect(state.players.a.resources[0]).toBe('relic');
    expect(() => applyGuildPrelude(state, 'a', { kind: 'relic-fence', discardSlot: 1 }))
      .toThrow('once per turn');
  });

  it('Galactic Bards declares on a Surpass before taking any action', () => {
    const state = game();
    state.mulliganPendingUid = null;
    state.players.a.guilds.push('ARCS-BC25');
    const lead = actionCard('administration', 2);
    state.round.lead = { uid: 'b', card: lead, mode: 'lead' };
    state.round.plays = [state.round.lead];
    state.round.actorUid = 'a';
    const card = actionCard('administration', 3);
    state.round.hands.a = [card];
    const next = applyGameCommand(state, 'a', 'bard',
      { kind: 'play', cardId: card.id, mode: 'surpass', bardDeclare: 'tyrant' }, 1001).state;
    expect(next.markers.at(-1)?.ambition).toBe('tyrant');
    expect(next.declaredThisRound).toBe(true);
  });
});
