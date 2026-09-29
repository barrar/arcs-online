import { randomInt } from 'node:crypto';
import { createBoard, type Resource, type SystemId } from './board';
import { cardById } from './court';
import { discardResource, gainResource, resourceSupply, systemController } from './game_actions';
import { raidCosts, type BattleFace, type GamePiece, type GameState } from './game_state';

// Printed six-face distributions: Base Rulebook p. 14, cross-checked against
// the six numbered faces for each die in the user's offline reference.
type Face = Omit<BattleFace, 'die'>;
const blank: Face = { own: 0, intercept: false, ship: 0, building: 0, keys: 0 };
const face = (own: number, intercept: boolean, ship: number, building: number, keys: number): Face =>
  ({ own, intercept, ship, building, keys });
export const dieFaces: Record<BattleFace['die'], readonly Face[]> = {
  skirmish: [blank, blank, blank, face(0, false, 1, 0, 0), face(0, false, 1, 0, 0), face(0, false, 1, 0, 0)],
  assault: [blank, face(1, false, 1, 0, 0), face(0, true, 1, 0, 0),
    face(1, false, 2, 0, 0), face(0, false, 2, 0, 0), face(1, false, 1, 0, 0)],
  raid: [face(0, true, 0, 0, 2), face(1, false, 0, 0, 1), face(0, true, 0, 0, 0),
    face(1, false, 0, 1, 0), face(0, false, 0, 1, 1), face(1, false, 0, 1, 0)],
};

export type BattleRoll = { systemId: SystemId; defenderUid: string;
  dice: { assault: number; skirmish: number; raid: number } };
export type HitAssignment = { own: string[]; ships: string[]; buildings: string[]; ransackCourtIndexes?: number[] };
export type RaidTarget = { kind: 'resource'; slot: number; destinationSlot?: number } | { kind: 'guild'; cardId: string };

export function beginBattle(state: GameState, uid: string, command: BattleRoll,
  random: (max: number) => number = randomInt): void {
  if (state.pendingBattle) throw new Error('Finish the previous battle first.');
  const pieces = state.systems[command.systemId];
  if (!pieces) throw new Error('That system is out of play.');
  const attackingShips = pieces.filter((piece) => piece.owner === uid && piece.kind === 'ship');
  if (attackingShips.length === 0) throw new Error('Battle in a system with Loyal ships.');
  if (command.defenderUid === uid || !state.players[command.defenderUid] ||
    !pieces.some((piece) => piece.owner === command.defenderUid)) {
    throw new Error('Choose a Rival with pieces in the battle system.');
  }
  const { assault, skirmish, raid } = command.dice;
  if ([assault, skirmish, raid].some((count) => !Number.isInteger(count) || count < 0 || count > 6)) {
    throw new Error('Choose zero to six dice of each type.');
  }
  const extra = command.systemId.endsWith(':gate') && state.players[uid].guilds.includes('ARCS-BC08') ? 2 : 0;
  if (assault + skirmish + raid < 1 || assault + skirmish + raid > attackingShips.length + extra) {
    throw new Error('You cannot roll more dice than your attacking ships allow.');
  }
  const defenderBuildingsHere = pieces.some((piece) => piece.owner === command.defenderUid && piece.kind !== 'ship');
  const defenderBuildingsAnywhere = Object.values(state.systems).some((system) => system.some((piece) =>
    piece.owner === command.defenderUid && (piece.kind === 'city' || piece.kind === 'starport')));
  if (raid > 0 && !defenderBuildingsHere && defenderBuildingsAnywhere) {
    throw new Error('Raid dice require defending buildings here, unless the defender has no buildings anywhere.');
  }
  const faces: BattleFace[] = [];
  for (const die of ['assault', 'skirmish', 'raid'] as const) {
    for (let index = 0; index < command.dice[die]; index++) {
      faces.push({ die, ...dieFaces[die][random(6)] });
    }
  }
  state.pendingBattle = { systemId: command.systemId, attackerUid: uid,
    defenderUid: command.defenderUid, faces, phase: 'assign', keys: 0, rerolled: false };
}

export function rerollSkirmish(state: GameState, uid: string, faceIndexes: number[],
  random: (max: number) => number = randomInt): void {
  const battle = state.pendingBattle;
  if (!battle || battle.phase !== 'assign' || battle.attackerUid !== uid || battle.rerolled) throw new Error('No skirmish reroll is available.');
  const player = state.players[uid];
  if (!player.guilds.includes('ARCS-BC13')) throw new Error('Skirmishers is required to reroll skirmish dice.');
  const weaponIcons = player.resources.filter((resource) => resource === 'weapon').length +
    player.guilds.filter((cardId) => cardById[cardId]?.suit === 'weapon').length;
  if (faceIndexes.length < 1 || faceIndexes.length > weaponIcons || new Set(faceIndexes).size !== faceIndexes.length ||
    faceIndexes.some((index) => !Number.isInteger(index) || battle.faces[index]?.die !== 'skirmish')) {
    throw new Error('Reroll at most one skirmish die per Weapon icon.');
  }
  for (const index of faceIndexes) battle.faces[index] = { die: 'skirmish', ...dieFaces.skirmish[random(6)] };
  battle.rerolled = true;
}

function hit(state: GameState, systemId: SystemId, piece: GamePiece, trophyUid: string): boolean {
  if (!piece.damaged) {
    piece.damaged = true;
    return false;
  }
  const pieces = state.systems[systemId];
  pieces.splice(pieces.findIndex((item) => item.id === piece.id), 1);
  state.players[trophyUid].trophies.push(piece);
  return true;
}

function ransack(state: GameState, attackerUid: string, defenderUid: string, courtIndex: number | undefined): void {
  const choices = state.courtRow.map((slot, index) => slot.agents[defenderUid] ? index : -1).filter((index) => index >= 0);
  if (choices.length === 0) return;
  if (courtIndex === undefined || !choices.includes(courtIndex)) throw new Error('Choose a Court card with the defender’s agents to ransack.');
  const slot = state.courtRow[courtIndex];
  for (const [owner, count] of Object.entries(slot.agents)) {
    if (owner !== attackerUid) {
      for (let index = 0; index < count; index++) {
        state.players[attackerUid].trophies.push({ id: `agent:${owner}:${state.nextPieceId++}`, owner, kind: 'agent', damaged: false });
      }
    }
  }
  const card = cardById[slot.cardId];
  if (!card) throw new Error('Unknown Court card.');
  if (card.kind === 'guild') {
    state.players[attackerUid].guilds.push(card.id);
    if (card.id === 'ARCS-BC03' || card.id === 'ARCS-BC06') {
      state.heldResources[card.id] = Array(resourceSupply(state, card.suit!)).fill(card.suit!);
    }
  }
  else { state.courtDiscard.push(card.id); state.pendingVox.push(card.id); }
  if (state.courtDeck.length > 0) state.courtRow[courtIndex] = { cardId: state.courtDeck.shift()!, agents: {} };
  else state.courtRow.splice(courtIndex, 1);
}

export function provokeOutrage(state: GameState, uid: string, resource: Resource): void {
  const player = state.players[uid];
  for (let slot = 0; slot < player.resources.length; slot++) {
    if (player.resources[slot] === resource) player.resources[slot] = null;
  }
  const loyalGuilds = new Set(['ARCS-BC01', 'ARCS-BC07', 'ARCS-BC15', 'ARCS-BC19', 'ARCS-BC21']);
  const discarded = player.guilds.filter((id) => cardById[id]?.suit === resource && !loyalGuilds.has(id));
  player.guilds = player.guilds.filter((id) => !discarded.includes(id));
  for (const cardId of discarded) {
    state.courtDiscard.push(cardId);
    delete state.heldResources[cardId];
  }
  if (!player.outrage.includes(resource)) player.outrage.push(resource);
}

export function assignBattleHits(state: GameState, uid: string, command: HitAssignment): void {
  const battle = state.pendingBattle;
  if (!battle || battle.phase !== 'assign' || battle.attackerUid !== uid) throw new Error('There are no battle hits to assign.');
  const pieces = state.systems[battle.systemId];
  const freshDefenders = pieces.filter((piece) => piece.owner === battle.defenderUid && piece.kind === 'ship' && !piece.damaged).length;
  const ownHits = battle.faces.reduce((sum, result) => sum + result.own, 0) + (battle.faces.some((result) => result.intercept) ? freshDefenders : 0);
  const shipHits = battle.faces.reduce((sum, result) => sum + result.ship, 0);
  const buildingHits = battle.faces.reduce((sum, result) => sum + result.building, 0);
  const ransackIndexes = [...(command.ransackCourtIndexes ?? [])];
  const apply = (targets: string[], count: number, eligible: () => GamePiece[], trophyUid: string) => {
    let applied = 0;
    for (const targetId of targets) {
      if (applied >= count) throw new Error('More targets were given than hits rolled.');
      const piece = eligible().find((candidate) => candidate.id === targetId);
      if (!piece) throw new Error('Choose an eligible piece for each hit.');
      applied++;
      const destroyed = hit(state, battle.systemId, piece, trophyUid);
      if (destroyed && piece.kind === 'city') {
        const planet = createBoard(state.activeClusters).planets[battle.systemId];
        provokeOutrage(state, uid, planet.resource);
        ransack(state, uid, battle.defenderUid, ransackIndexes.shift());
      }
    }
    if (applied < count && eligible().length > 0) throw new Error('Assign every hit while eligible pieces remain.');
  };
  apply(command.own, ownHits, () => pieces.filter((piece) => piece.owner === uid && piece.kind === 'ship'), battle.defenderUid);
  apply(command.ships, shipHits, () => {
    const ships = pieces.filter((piece) => piece.owner === battle.defenderUid && piece.kind === 'ship');
    return ships.length > 0 ? ships : pieces.filter((piece) => piece.owner === battle.defenderUid && (piece.kind === 'city' || piece.kind === 'starport'));
  }, uid);
  apply(command.buildings, buildingHits, () => pieces.filter((piece) => piece.owner === battle.defenderUid && (piece.kind === 'city' || piece.kind === 'starport')), uid);
  if (ransackIndexes.length > 0) throw new Error('Unused Court ransack choices.');
  const survivingShips = pieces.some((piece) => piece.owner === uid && piece.kind === 'ship');
  const keys = survivingShips ? battle.faces.reduce((sum, result) => sum + result.keys, 0) : 0;
  if (keys > 0) { battle.phase = 'raid'; battle.keys = keys; }
  else state.pendingBattle = undefined;
}

export function raidBattle(state: GameState, uid: string, target: RaidTarget): void {
  const battle = state.pendingBattle;
  if (!battle || battle.phase !== 'raid' || battle.attackerUid !== uid) throw new Error('There are no raid keys to spend.');
  const defender = state.players[battle.defenderUid];
  const attacker = state.players[uid];
  const guardians = defender.guilds.includes('ARCS-BC22');
  if (target.kind === 'resource') {
    if (guardians) throw new Error('Sworn Guardians protects the defender’s resources.');
    if (!Number.isInteger(target.slot) || !defender.resources[target.slot]) throw new Error('Choose a defender resource slot.');
    const cost = raidCosts[target.slot];
    if (cost === undefined || cost > battle.keys) throw new Error('Insufficient raid keys.');
    const stolen = discardResource(state, defender.uid, target.slot);
    gainResource(state, uid, stolen, target.destinationSlot);
    battle.keys -= cost;
  } else {
    const card = cardById[target.cardId];
    if (card?.kind !== 'guild' || !defender.guilds.includes(card.id)) throw new Error('Choose a defender Guild card.');
    if (guardians && card.id !== 'ARCS-BC22') throw new Error('Sworn Guardians must be stolen first.');
    if (card.raidCost! > battle.keys) throw new Error('Insufficient raid keys.');
    defender.guilds.splice(defender.guilds.indexOf(card.id), 1);
    if (card.id === 'ARCS-BC22') state.courtDeck.push(card.id);
    else attacker.guilds.push(card.id);
    battle.keys -= card.raidCost!;
  }
  if (battle.keys === 0) state.pendingBattle = undefined;
}

export function finishBattleRaid(state: GameState, uid: string): void {
  if (!state.pendingBattle || state.pendingBattle.phase !== 'raid' || state.pendingBattle.attackerUid !== uid) {
    throw new Error('No raid is pending.');
  }
  state.pendingBattle = undefined;
}
