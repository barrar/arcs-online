import { describe, expect, it } from 'vitest';
import { actionCard } from './action_cards';
import { createBoard } from './board';
import { applyStandardAction, placePiece } from './game_actions';
import { assignBattleHits, beginBattle, raidBattle } from './game_battle';
import { provokeOutrage, rerollSkirmish } from './game_battle';
import { createGameWithSetup } from './game_state';
import { scoringPlayers } from './game_state';
import { applyGuildPrelude, stealFromRival } from './game_guild';
import { resolveVox } from './game_vox';
import type { Lobby } from './lobby';
import { setupChoices } from './setup';

function game() {
  const seats = ['a', 'b'].map((uid, index) => ({
    uid, name: uid, color: index ? 'azure' : 'ember', ready: true,
  }));
  const lobby: Lobby = { id: '00000000-0000-4000-8000-000000000001', name: 'Rules',
    code: 'ABCDEFGH', visibility: 'private', status: 'waiting', maxPlayers: 2,
    hostId: 'a', seats, memberIds: ['a', 'b'], timer: { mode: 'async', hours: 24 },
    createdAt: 0, updatedAt: 0 };
  return createGameWithSetup(lobby, setupChoices(2)[0], 'a', 1000, () => 0);
}

describe('standard actions (base rulebook pp. 12–16)', () => {
  it('builds one ship per starport each turn and Catapults through gates', () => {
    const state = game();
    const from = setupChoices(2)[0].starting[0].b;
    const starport = state.systems[from].find((piece) => piece.owner === 'a' && piece.kind === 'starport')!;
    const before = state.systems[from].filter((piece) => piece.owner === 'a' && piece.kind === 'ship').length;
    applyStandardAction(state, 'a', { kind: 'build', piece: 'ship', systemId: from, starportId: starport.id });
    expect(state.systems[from].filter((piece) => piece.owner === 'a' && piece.kind === 'ship')).toHaveLength(before + 1);
    expect(() => applyStandardAction(state, 'a', { kind: 'build', piece: 'ship', systemId: from,
      starportId: starport.id })).toThrow('one ship per turn');
    const ships = state.systems[from].filter((piece) => piece.owner === 'a' && piece.kind === 'ship');
    const shipIds = ships.slice(0, 2).map((piece) => piece.id);
    applyStandardAction(state, 'a', { kind: 'move', from, shipIds,
      route: [{ to: '4:gate', dropShipIds: [shipIds[0]] },
        { to: '3:gate', dropShipIds: [shipIds[1]] }] });
    expect(state.systems['4:gate'].some((piece) => piece.id === shipIds[0])).toBe(true);
    expect(state.systems['3:gate'].some((piece) => piece.id === shipIds[1])).toBe(true);
  });

  it('captures a Rival agent when taxing a controlled city, even if no resource is gained', () => {
    const state = game();
    const citySystem = setupChoices(2)[0].starting[1].a;
    const city = state.systems[citySystem].find((piece) => piece.owner === 'b' && piece.kind === 'city')!;
    for (let index = 0; index < 4; index++) {
      state.systems[citySystem].push({ id: `a:extra:${index}`, owner: 'a', kind: 'ship', damaged: false });
    }
    const before = state.players.a.captiveOwners.length;
    applyStandardAction(state, 'a', { kind: 'tax', cityId: city.id });
    expect(state.players.a.captiveOwners).toHaveLength(before + 1);
    expect(() => applyStandardAction(state, 'a', { kind: 'tax', cityId: city.id })).toThrow('once per turn');
  });

  it('secures Court majority and refills the row', () => {
    const state = game();
    const firstCard = state.courtRow[0].cardId;
    applyStandardAction(state, 'a', { kind: 'influence', courtIndex: 0 });
    expect(state.courtRow[0].agents.a).toBe(1);
    applyStandardAction(state, 'a', { kind: 'secure', courtIndex: 0 });
    expect(state.courtRow[0].cardId).not.toBe(firstCard);
    expect(state.players.a.guilds.includes(firstCard) || state.pendingVox.includes(firstCard)).toBe(true);
  });
});

describe('battle and raids (base rulebook pp. 14–16)', () => {
  it('destroys a city, provokes Outrage, and Ransacks a defender-influenced Court card', () => {
    const state = game();
    const systemId = setupChoices(2)[0].starting[0].a;
    const city = { id: 'b:target-city', owner: 'b', kind: 'city' as const, damaged: true };
    state.systems[systemId].push(city);
    state.players.b.citiesOut++;
    state.courtRow[0].agents.b = 1;
    const attackingShip = state.systems[systemId].find((piece) => piece.owner === 'a' && piece.kind === 'ship')!;
    beginBattle(state, 'a', { systemId, defenderUid: 'b', dice: { assault: 1, skirmish: 0, raid: 0 } }, () => 3);
    assignBattleHits(state, 'a', { own: [attackingShip.id], ships: [city.id], buildings: [],
      ransackCourtIndexes: [0] });
    expect(state.players.a.trophies.some((piece) => piece.id === city.id)).toBe(true);
    expect(state.players.a.outrage).toContain(createBoard(state.activeClusters).planets[systemId].resource);
    expect(state.players.a.trophies.some((piece) => piece.owner === 'b' && piece.kind === 'agent')).toBe(true);
  });

  it('uses raid keys to steal a resource only while ships survive', () => {
    const state = game();
    const systemId = setupChoices(2)[0].starting[0].a;
    placePiece(state, 'b', 'city', systemId);
    beginBattle(state, 'a', { systemId, defenderUid: 'b', dice: { assault: 0, skirmish: 0, raid: 1 } }, () => 0);
    assignBattleHits(state, 'a', { own: [], ships: [], buildings: [] });
    expect(state.pendingBattle?.keys).toBe(2);
    const stolen = state.players.b.resources[1];
    raidBattle(state, 'a', { kind: 'resource', slot: 1, destinationSlot: 0 });
    expect(state.players.a.resources[0]).toBe(stolen);
    expect(state.players.b.resources[1]).toBeNull();
    expect(state.pendingBattle?.keys).toBe(1);
  });
});

describe('base Court effects (official card library)', () => {
  it('puts a Cartel resource supply on its card for Tycoon scoring', () => {
    const state = game();
    state.courtRow[0] = { cardId: 'ARCS-BC03', agents: { a: 1 } };
    applyStandardAction(state, 'a', { kind: 'secure', courtIndex: 0 });
    const held = state.heldResources['ARCS-BC03'];
    expect(held.length).toBeGreaterThan(0);
    expect(scoringPlayers(state).find((player) => player.uid === 'a')!.resources.filter((item) => item === 'material').length)
      .toBeGreaterThan(held.length);
  });

  it('keeps Loyal Guilds but discards matching ordinary Guilds when provoking Outrage', () => {
    const state = game();
    state.players.a.guilds.push('ARCS-BC01', 'ARCS-BC02');
    provokeOutrage(state, 'a', 'material');
    expect(state.players.a.guilds).toContain('ARCS-BC01');
    expect(state.players.a.guilds).not.toContain('ARCS-BC02');
    expect(state.players.a.resources).not.toContain('material');
    expect(state.players.a.outrage).toContain('material');
  });

  it('protects a Rival with Sworn Guardians until the card itself is stolen and buried', () => {
    const state = game();
    state.players.b.guilds.push('ARCS-BC22', 'ARCS-BC02');
    expect(() => stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC02' }))
      .toThrow('Sworn Guardians');
    stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC22' });
    expect(state.courtDeck.at(-1)).toBe('ARCS-BC22');
    stealFromRival(state, 'a', { kind: 'guild', rivalUid: 'b', cardId: 'ARCS-BC02' });
    expect(state.players.a.guilds).toContain('ARCS-BC02');
  });

  it('lets Skirmishers reroll no more dice than the player has Weapon icons', () => {
    const state = game();
    state.players.a.guilds.push('ARCS-BC13');
    const systemId = setupChoices(2)[0].starting[0].a;
    placePiece(state, 'b', 'city', systemId);
    beginBattle(state, 'a', { systemId, defenderUid: 'b', dice: { assault: 0, skirmish: 2, raid: 0 } }, () => 0);
    expect(() => rerollSkirmish(state, 'a', [0, 1], () => 4)).toThrow('Weapon icon');
    rerollSkirmish(state, 'a', [0], () => 4);
    expect(state.pendingBattle!.faces[0].ship).toBe(1);
    expect(() => rerollSkirmish(state, 'a', [1], () => 4)).toThrow('No skirmish reroll');
  });

  it('recovers a Union card from the face-up round play', () => {
    const state = game();
    state.players.a.guilds.push('ARCS-BC05');
    const card = actionCard('construction', 2);
    state.round.plays.push({ uid: 'a', card, mode: 'lead' });
    state.round.playedThisTurn = true;
    state.turn.preludeOpen = true;
    applyGuildPrelude(state, 'a', { kind: 'union', cardId: 'ARCS-BC05', actionCardId: card.id });
    expect(state.unionReservations).toEqual([{ uid: 'a', guildId: 'ARCS-BC05', actionCardId: card.id }]);
  });

  it('resolves every base Vox card into its printed state change', () => {
    const mass = game();
    mass.pendingVox = ['ARCS-BC26'];
    resolveVox(mass, 'a', { kind: 'mass-uprising', cluster: mass.activeClusters[0] });
    expect(mass.pendingVox).toHaveLength(0);
    expect(Object.entries(mass.systems).filter(([id, pieces]) =>
      id.startsWith(`${mass.activeClusters[0]}:`) && pieces.some((piece) => piece.owner === 'a' && piece.kind === 'ship')))
      .toHaveLength(4);

    const demands = game();
    demands.pendingVox = ['ARCS-BC27'];
    resolveVox(demands, 'a', { kind: 'populist-demands', ambition: 'tycoon' });
    expect(demands.markers[0].ambition).toBe('tycoon');

    const outrage = game();
    outrage.pendingVox = ['ARCS-BC28'];
    resolveVox(outrage, 'a', { kind: 'outrage-spreads', resource: 'fuel' });
    expect(outrage.order.every((uid) => outrage.players[uid].outrage.includes('fuel'))).toBe(true);

    const freedom = game();
    freedom.pendingVox = ['ARCS-BC29'];
    freedom.courtDiscard.push('ARCS-BC29');
    const city = freedom.systems[setupChoices(2)[0].starting[0].a].find((piece) =>
      piece.owner === 'a' && piece.kind === 'city')!;
    resolveVox(freedom, 'a', { kind: 'song-of-freedom', cityId: city.id });
    expect(freedom.players.a.citiesOut).toBe(0);
    expect(freedom.courtDeck).toContain('ARCS-BC29');

    const struggle = game();
    struggle.pendingVox = ['ARCS-BC30'];
    struggle.players.b.guilds.push('ARCS-BC02');
    struggle.courtDiscard.push('ARCS-BC04');
    resolveVox(struggle, 'a', { kind: 'guild-struggle', rivalUid: 'b', cardId: 'ARCS-BC02' });
    expect(struggle.players.a.guilds).toContain('ARCS-BC02');
    expect(struggle.courtDeck).toContain('ARCS-BC04');

    const call = game();
    call.pendingVox = ['ARCS-BC31'];
    const before = call.round.hands.a.length;
    resolveVox(call, 'a', { kind: 'call-to-action' });
    expect(call.round.hands.a).toHaveLength(before + 1);
  });
});
