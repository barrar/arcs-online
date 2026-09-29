import { createBoard, type Resource, type SystemId } from './board';
import { cardById } from './court';
import { discardResource, gainResource, pieceLocation, placePiece, resourceSupply,
  supplyOf, systemController } from './game_actions';
import { resourceCapacity, type GameState } from './game_state';

export type StealChoice =
  | { kind: 'resource'; rivalUid: string; rivalSlot: number; destinationSlot?: number }
  | { kind: 'guild'; rivalUid: string; cardId: string };
export type GuildPrelude =
  | { kind: 'interest'; cardId: 'ARCS-BC02' | 'ARCS-BC09'; placements: { slot: number; stealFrom?: { uid: string; slot: number } }[] }
  | { kind: 'cartel'; cardId: 'ARCS-BC03' | 'ARCS-BC06'; steal?: StealChoice }
  | { kind: 'union'; cardId: 'ARCS-BC04' | 'ARCS-BC05' | 'ARCS-BC10' | 'ARCS-BC11'; actionCardId: string }
  | { kind: 'gatekeepers'; gateIds?: SystemId[] }
  | { kind: 'place-ships'; cardId: 'ARCS-BC12' | 'ARCS-BC13' | 'ARCS-BC14' | 'ARCS-BC15'; systemId: SystemId }
  | { kind: 'lattice-spies' }
  | { kind: 'farseers'; discardActionCardIds: string[] }
  | { kind: 'silver-tongues'; steal?: StealChoice }
  | { kind: 'elder-broker'; slots: (number | null)[] }
  | { kind: 'relic-fence'; discardSlot: number; destinationSlot?: number };

export type GuildAction =
  | { kind: 'manufacture'; slot?: number }
  | { kind: 'synthesize'; slot?: number }
  | { kind: 'pressgang'; captiveOwners: string[]; gains: { resource: Resource; slot?: number }[] }
  | { kind: 'execute'; captiveOwners: string[] }
  | { kind: 'abduct'; courtIndex: number }
  | { kind: 'trade'; cityId: string; giveSlot: number; takeSlot: number; destinationSlot?: number };

const shipPreludeCards = new Set(['ARCS-BC12', 'ARCS-BC13', 'ARCS-BC14', 'ARCS-BC15']);
const unionSuits: Record<string, string> = {
  'ARCS-BC04': 'administration', 'ARCS-BC05': 'construction',
  'ARCS-BC10': 'mobilization', 'ARCS-BC11': 'aggression',
};

function requireHeld(state: GameState, uid: string, cardId: string, preludeOnly = false): void {
  if (!state.players[uid]?.guilds.includes(cardId)) throw new Error('You do not hold that Guild card.');
  if (preludeOnly && state.turn.securedThisPrelude.includes(cardId)) {
    throw new Error('A newly secured card cannot use its Prelude action in the same Prelude.');
  }
}

function discardGuild(state: GameState, uid: string, cardId: string): void {
  requireHeld(state, uid, cardId, true);
  state.players[uid].guilds.splice(state.players[uid].guilds.indexOf(cardId), 1);
  state.courtDiscard.push(cardId);
  delete state.heldResources[cardId];
}

export function stealFromRival(state: GameState, uid: string, choice: StealChoice): void {
  const rival = state.players[choice.rivalUid];
  if (!rival || rival.uid === uid) throw new Error('Choose a Rival.');
  if (rival.guilds.includes('ARCS-BC22') && (choice.kind === 'resource' || choice.cardId !== 'ARCS-BC22')) {
    throw new Error('Sworn Guardians protects resources and other Guild cards.');
  }
  if (choice.kind === 'resource') {
    const resource = rival.resources[choice.rivalSlot];
    if (!resource) throw new Error('Choose a Rival resource.');
    discardResource(state, rival.uid, choice.rivalSlot);
    gainResource(state, uid, resource, choice.destinationSlot);
  } else {
    if (!rival.guilds.includes(choice.cardId) || cardById[choice.cardId]?.kind !== 'guild') {
      throw new Error('Choose a Rival Guild card.');
    }
    rival.guilds.splice(rival.guilds.indexOf(choice.cardId), 1);
    if (choice.cardId === 'ARCS-BC22') state.courtDeck.push(choice.cardId);
    else state.players[uid].guilds.push(choice.cardId);
  }
}

export function applyGuildPrelude(state: GameState, uid: string, command: GuildPrelude): void {
  if (state.round.actorUid !== uid || !state.round.playedThisTurn || !state.turn.preludeOpen) {
    throw new Error('Guild Prelude actions require your open Prelude.');
  }
  const player = state.players[uid];
  const cardId = 'cardId' in command ? command.cardId : ({
    gatekeepers: 'ARCS-BC08', 'lattice-spies': 'ARCS-BC16', farseers: 'ARCS-BC17',
    'silver-tongues': 'ARCS-BC20', 'elder-broker': 'ARCS-BC23', 'relic-fence': 'ARCS-BC24',
  } as Record<string, string>)[command.kind];
  requireHeld(state, uid, cardId, true);
  if (command.kind === 'relic-fence') {
    if (state.turn.usedGuilds.includes(cardId)) throw new Error('Relic Fence can be used once per turn.');
    discardResource(state, uid, command.discardSlot);
    gainResource(state, uid, 'relic', command.destinationSlot);
    state.turn.usedGuilds.push(cardId);
    return;
  }
  switch (command.kind) {
    case 'interest': {
      const resource: Resource = command.cardId === 'ARCS-BC02' ? 'material' : 'fuel';
      const empty = player.resources.slice(0, resourceCapacity(player.citiesOut)).filter((item) => item === null).length;
      if (command.placements.length > empty ||
        new Set(command.placements.map((item) => item.slot)).size !== command.placements.length ||
        command.placements.some((item) => !Number.isInteger(item.slot) || item.slot < 0 ||
          item.slot >= resourceCapacity(player.citiesOut) || player.resources[item.slot] !== null)) {
        throw new Error('Interest may gain at most one resource per empty slot.');
      }
      discardGuild(state, uid, cardId);
      for (const placement of command.placements) {
        if (resourceSupply(state, resource) > 0) {
          if (placement.stealFrom) throw new Error('Use the supply until it empties.');
          gainResource(state, uid, resource, placement.slot);
        } else {
          const from = placement.stealFrom;
          if (!from || state.players[from.uid]?.resources[from.slot] !== resource) throw new Error('Choose a Rival holding the exhausted resource.');
          stealFromRival(state, uid, { kind: 'resource', rivalUid: from.uid, rivalSlot: from.slot, destinationSlot: placement.slot });
        }
      }
      break;
    }
    case 'cartel': {
      const resource: Resource = command.cardId === 'ARCS-BC03' ? 'material' : 'fuel';
      discardGuild(state, uid, cardId);
      if (command.steal) {
        if (command.steal.kind !== 'resource' || state.players[command.steal.rivalUid]?.resources[command.steal.rivalSlot] !== resource) {
          throw new Error('Cartel steals one matching resource.');
        }
        stealFromRival(state, uid, command.steal);
      }
      break;
    }
    case 'union': {
      const play = state.round.plays.find((item) => item.card.id === command.actionCardId && item.mode !== 'copy');
      if (!play || play.card.suit !== unionSuits[cardId] ||
        state.unionReservations.some((item) => item.actionCardId === command.actionCardId || item.guildId === cardId)) {
        throw new Error('Choose an unclaimed face-up played card of the Union’s suit.');
      }
      state.unionReservations.push({ uid, guildId: cardId, actionCardId: play.card.id });
      state.turn.usedGuilds.push(cardId);
      break;
    }
    case 'gatekeepers': {
      const available = state.activeClusters.map((cluster): SystemId => `${cluster}:gate`);
      const count = Math.min(available.length, supplyOf(state, uid, 'ship'));
      const chosen = command.gateIds ?? available.slice(0, count);
      if (chosen.length !== count || new Set(chosen).size !== count ||
        chosen.some((gate) => !available.includes(gate))) {
        throw new Error('Choose a distinct active gate for each available ship.');
      }
      discardGuild(state, uid, cardId);
      for (const gate of chosen) placePiece(state, uid, 'ship', gate);
      break;
    }
    case 'place-ships': {
      if (!shipPreludeCards.has(cardId) || systemController(state, command.systemId) !== uid) {
        throw new Error('Choose a system you control.');
      }
      discardGuild(state, uid, cardId);
      for (let index = 0; index < 3; index++) placePiece(state, uid, 'ship', command.systemId);
      break;
    }
    case 'lattice-spies': {
      if (state.round.initiativeUid === uid || state.round.seizedUid || state.turn.usedGuilds.length > 0 ||
        state.turn.spentResources.length > 0 || state.turn.securedThisPrelude.length > 0) {
        throw new Error('Lattice Spies must seize before any other action, if initiative is available.');
      }
      discardGuild(state, uid, cardId);
      state.round.seizedUid = uid;
      state.round.initiativeUid = uid;
      break;
    }
    case 'farseers': {
      if (new Set(command.discardActionCardIds).size !== command.discardActionCardIds.length ||
        command.discardActionCardIds.some((id) => !state.round.hands[uid].some((card) => card.id === id))) {
        throw new Error('Choose distinct action cards from your hand to discard.');
      }
      discardGuild(state, uid, cardId);
      for (const id of command.discardActionCardIds) {
        const hand = state.round.hands[uid];
        const index = hand.findIndex((card) => card.id === id);
        state.actionDiscard.push(hand.splice(index, 1)[0]);
      }
      for (let index = 0; index <= command.discardActionCardIds.length; index++) {
        const drawn = state.actionDiscard.shift();
        if (drawn) state.round.hands[uid].push(drawn);
      }
      break;
    }
    case 'silver-tongues':
      discardGuild(state, uid, cardId);
      if (command.steal) stealFromRival(state, uid, command.steal);
      break;
    case 'elder-broker': {
      if (command.slots.length !== 3) throw new Error('Choose slots for Material, Fuel and Weapon.');
      discardGuild(state, uid, cardId);
      (['material', 'fuel', 'weapon'] as Resource[]).forEach((resource, index) => {
        gainResource(state, uid, resource, command.slots[index] ?? undefined);
      });
      break;
    }
  }
  if (!['union', 'relic-fence'].includes(command.kind)) state.turn.usedGuilds.push(cardId);
}

export function guildBaseAction(command: GuildAction): 'build' | 'influence' | 'battle' | 'tax' {
  switch (command.kind) {
    case 'manufacture': case 'synthesize': case 'pressgang': return 'build';
    case 'execute': return 'influence';
    case 'abduct': return 'battle';
    case 'trade': return 'tax';
  }
}

export function applyGuildAction(state: GameState, uid: string, command: GuildAction): void {
  const required: Record<GuildAction['kind'], string> = {
    manufacture: 'ARCS-BC02', synthesize: 'ARCS-BC09', pressgang: 'ARCS-BC12',
    execute: 'ARCS-BC12', abduct: 'ARCS-BC14', trade: 'ARCS-BC23',
  };
  requireHeld(state, uid, required[command.kind]);
  const player = state.players[uid];
  switch (command.kind) {
    case 'manufacture': gainResource(state, uid, 'material', command.slot); break;
    case 'synthesize': gainResource(state, uid, 'fuel', command.slot); break;
    case 'pressgang': {
      if (command.captiveOwners.length !== command.gains.length) throw new Error('Gain one resource per returned Captive.');
      for (const owner of command.captiveOwners) {
        const index = player.captiveOwners.indexOf(owner);
        if (index < 0) throw new Error('You do not hold that Captive.');
        player.captiveOwners.splice(index, 1);
      }
      for (const gain of command.gains) gainResource(state, uid, gain.resource, gain.slot);
      break;
    }
    case 'execute': {
      for (const owner of command.captiveOwners) {
        const index = player.captiveOwners.indexOf(owner);
        if (index < 0) throw new Error('You do not hold that Captive.');
        player.captiveOwners.splice(index, 1);
        player.trophies.push({ id: `agent:${owner}:${state.nextPieceId++}`, owner, kind: 'agent', damaged: false });
      }
      break;
    }
    case 'abduct': {
      const slot = state.courtRow[command.courtIndex];
      if (!slot) throw new Error('Choose a Court card.');
      const rivalAgents = Object.entries(slot.agents).filter(([owner]) => owner !== uid).reduce((sum, [, count]) => sum + count, 0);
      const weaponIcons = player.resources.filter((resource) => resource === 'weapon').length +
        player.guilds.filter((id) => cardById[id]?.suit === 'weapon').length;
      if (rivalAgents >= weaponIcons) throw new Error('The Court card must have fewer Rival agents than your Weapon icons.');
      for (const [owner, count] of Object.entries(slot.agents)) {
        if (owner === uid) continue;
        for (let index = 0; index < count; index++) player.captiveOwners.push(owner);
        delete slot.agents[owner];
      }
      break;
    }
    case 'trade': {
      const location = pieceLocation(state, command.cityId);
      if (!location || location.piece.kind !== 'city' || location.piece.owner === uid ||
        systemController(state, location.systemId) !== uid) throw new Error('Choose a Rival city you control.');
      const rival = state.players[location.piece.owner];
      const cityResource = createBoard(state.activeClusters).planets[location.systemId].resource;
      const giving = player.resources[command.giveSlot];
      if (!giving || rival.resources.includes(giving) || rival.resources[command.takeSlot] !== cityResource) {
        throw new Error('Trade a resource the Rival lacks for their city-type resource.');
      }
      discardResource(state, uid, command.giveSlot);
      discardResource(state, rival.uid, command.takeSlot);
      gainResource(state, rival.uid, giving, command.takeSlot);
      gainResource(state, uid, cityResource, command.destinationSlot ?? command.giveSlot);
      break;
    }
  }
}
