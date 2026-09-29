import { createBoard, type Resource, type SystemId } from './board';
import { cardById } from './court';
import { placePiece, pieceLocation, supplyOf, systemController } from './game_actions';
import { provokeOutrage } from './game_battle';
import { availableMarker, resourceCapacity, shuffled, type GameState } from './game_state';
import type { Ambition } from './rules';

export type VoxChoice =
  | { kind: 'mass-uprising'; cluster: number; systemIds?: SystemId[] }
  | { kind: 'populist-demands'; ambition?: Ambition }
  | { kind: 'outrage-spreads'; resource?: Resource }
  | { kind: 'song-of-freedom'; cityId?: string; seize?: boolean }
  | { kind: 'guild-struggle'; rivalUid?: string; cardId?: string }
  | { kind: 'call-to-action' };

function queueAfterCityReturn(state: GameState, uid: string): void {
  const player = state.players[uid];
  const capacity = resourceCapacity(player.citiesOut);
  const all = player.resources.filter((item): item is Resource => item !== null);
  if (all.length > capacity && !state.pendingResourceChoices.includes(uid)) state.pendingResourceChoices.push(uid);
  else player.resources = [...all, ...Array<null>(6 - all.length).fill(null)];
}

export function resolveVox(state: GameState, uid: string, choice: VoxChoice): void {
  const cardId = state.pendingVox[0];
  if (!cardId) throw new Error('No Vox effect is pending.');
  if (state.round.actorUid !== uid) throw new Error('Only the active player resolves a secured Vox.');
  switch (cardId) {
    case 'ARCS-BC26': {
      if (choice.kind !== 'mass-uprising' || !state.activeClusters.includes(choice.cluster)) throw new Error('Choose an active cluster.');
      const board = createBoard(state.activeClusters);
      const systems = (Object.keys(board.adjacency) as SystemId[]).filter((systemId) =>
        Number(systemId.split(':')[0]) === choice.cluster);
      const count = Math.min(systems.length, supplyOf(state, uid, 'ship'));
      const chosen = choice.systemIds ?? systems.slice(0, count);
      if (chosen.length !== count || new Set(chosen).size !== count || chosen.some((id) => !systems.includes(id))) {
        throw new Error('Choose distinct systems in that cluster for the available ships.');
      }
      for (const systemId of chosen) placePiece(state, uid, 'ship', systemId);
      break;
    }
    case 'ARCS-BC27': {
      if (choice.kind !== 'populist-demands') throw new Error('Choose whether to declare an ambition.');
      if (choice.ambition) {
        const marker = availableMarker(state, choice.ambition);
        state.markers.push(marker);
        state.round.availableAmbitions--;
        state.round.declaredAmbitions.push(choice.ambition);
        state.declaredThisRound = true;
        if (state.players[uid].guilds.includes('ARCS-BC17')) state.pendingFarseers = { uid };
      }
      break;
    }
    case 'ARCS-BC28': {
      if (choice.kind !== 'outrage-spreads') throw new Error('Choose an Outrage type or skip.');
      if (choice.resource) {
        for (const playerUid of state.order) provokeOutrage(state, playerUid, choice.resource);
      }
      break;
    }
    case 'ARCS-BC29': {
      if (choice.kind !== 'song-of-freedom') throw new Error('Choose a city to return or skip.');
      if (choice.cityId) {
        const location = pieceLocation(state, choice.cityId);
        if (!location || location.piece.kind !== 'city' || systemController(state, location.systemId) !== uid) {
          throw new Error('Choose a city in a system you control.');
        }
        const owner = location.piece.owner;
        state.systems[location.systemId].splice(state.systems[location.systemId].findIndex((piece) => piece.id === choice.cityId), 1);
        state.players[owner].citiesOut--;
        queueAfterCityReturn(state, owner);
        if (choice.seize) {
          if (state.round.initiativeUid === uid || state.round.seizedUid) throw new Error('The initiative cannot be seized now.');
          state.round.seizedUid = uid;
          state.round.initiativeUid = uid;
        }
      } else if (choice.seize) throw new Error('Return a city before seizing the initiative.');
      state.courtDiscard.splice(state.courtDiscard.indexOf(cardId), 1);
      state.courtDeck = shuffled([...state.courtDeck, cardId]);
      break;
    }
    case 'ARCS-BC30': {
      if (choice.kind !== 'guild-struggle') throw new Error('Choose a Guild card to steal or skip.');
      if (choice.cardId) {
        const rival = choice.rivalUid && state.players[choice.rivalUid];
        if (!rival || rival.uid === uid || !rival.guilds.includes(choice.cardId) || cardById[choice.cardId]?.kind !== 'guild') {
          throw new Error('Choose a Rival Guild card.');
        }
        if (rival.guilds.includes('ARCS-BC22') && choice.cardId !== 'ARCS-BC22') throw new Error('Sworn Guardians protects other Guild cards.');
        rival.guilds.splice(rival.guilds.indexOf(choice.cardId), 1);
        if (choice.cardId === 'ARCS-BC22') state.courtDeck.push(choice.cardId);
        else state.players[uid].guilds.push(choice.cardId);
      }
      const guildDiscard = state.courtDiscard.filter((id) => cardById[id]?.kind === 'guild');
      state.courtDiscard = state.courtDiscard.filter((id) => cardById[id]?.kind !== 'guild');
      state.courtDeck = shuffled([...state.courtDeck, ...guildDiscard]);
      break;
    }
    case 'ARCS-BC31': {
      if (choice.kind !== 'call-to-action') throw new Error('Draw the action card.');
      const drawn = state.actionDiscard.shift();
      if (drawn) state.round.hands[uid].push(drawn);
      break;
    }
    default: throw new Error('Unknown Vox card.');
  }
  state.pendingVox.shift();
}
