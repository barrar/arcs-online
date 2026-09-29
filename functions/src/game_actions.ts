import { createBoard, isAdjacent, type Resource, type SystemId } from './board';
import { cardById } from './court';
import { resourceCapacity, type GamePiece, type GameState } from './game_state';
import { controller } from './rules';

// Pure, mutable operations on a cloned authoritative state. The command
// reducer owns the clone and only commits it if every validation succeeds.
export type TaxAction = { kind: 'tax'; cityId: string; slot?: number };
export type BuildAction = { kind: 'build'; piece: 'city' | 'starport' | 'ship'; systemId: SystemId; starportId?: string };
export type MoveAction = { kind: 'move'; from: SystemId; shipIds: string[]; route: { to: SystemId; dropShipIds: string[] }[] };
export type RepairAction = { kind: 'repair'; pieceId: string };
export type InfluenceAction = { kind: 'influence'; courtIndex: number };
export type SecureAction = { kind: 'secure'; courtIndex: number };
export type StandardActionInput = TaxAction | BuildAction | MoveAction | RepairAction | InfluenceAction | SecureAction;

function requirePlayer(state: GameState, uid: string) {
  if (!state.players[uid]) throw new Error('You are not seated in this match.');
  return state.players[uid];
}

export function pieceLocation(state: GameState, pieceId: string): { systemId: SystemId; piece: GamePiece } | null {
  for (const [systemId, pieces] of Object.entries(state.systems) as [SystemId, GamePiece[]][]) {
    const piece = pieces.find((item) => item.id === pieceId);
    if (piece) return { systemId, piece };
  }
  return null;
}

export function systemController(state: GameState, systemId: SystemId): string | null {
  const pieces = state.systems[systemId];
  if (!pieces) throw new Error('That system is out of play.');
  return controller({ id: systemId, pieces: pieces.filter((piece) => piece.kind !== 'agent') as
    Array<GamePiece & { kind: 'ship' | 'city' | 'starport' }> });
}

export function supplyOf(state: GameState, uid: string, kind: GamePiece['kind']): number {
  requirePlayer(state, uid);
  if (kind === 'city') return 5 - state.players[uid].citiesOut;
  if (kind === 'agent') {
    const inCourt = state.courtRow.reduce((sum, slot) => sum + (slot.agents[uid] ?? 0), 0);
    const captive = Object.values(state.players).reduce((sum, player) => sum + player.captiveOwners.filter((owner) => owner === uid).length, 0);
    const trophies = Object.values(state.players).reduce((sum, player) => sum + player.trophies.filter((piece) => piece.owner === uid && piece.kind === 'agent').length, 0);
    return Math.max(0, 10 - inCourt - captive - trophies - state.players[uid].outrage.length);
  }
  const onMap = Object.values(state.systems).reduce((sum, pieces) => sum + pieces.filter((piece) => piece.owner === uid && piece.kind === kind).length, 0);
  const trophies = Object.values(state.players).reduce((sum, player) => sum + player.trophies.filter((piece) => piece.owner === uid && piece.kind === kind).length, 0);
  return Math.max(0, (kind === 'ship' ? 15 : 5) - onMap - trophies);
}

export function resourceSupply(state: GameState, resource: Resource): number {
  const inSlots = Object.values(state.players).reduce((sum, player) => sum + player.resources.filter((item) => item === resource).length, 0);
  const held = Object.values(state.heldResources).reduce((sum, items) => sum + items.filter((item) => item === resource).length, 0);
  return Math.max(0, 5 - inSlots - held - state.turn.spentResources.filter((item) => item === resource).length
    - state.phantomResources.filter((item) => item === resource).length);
}

export function gainResource(state: GameState, uid: string, resource: Resource, slot?: number): boolean {
  const player = requirePlayer(state, uid);
  const capacity = resourceCapacity(player.citiesOut);
  if (slot !== undefined && (!Number.isInteger(slot) || slot < 0 || slot >= capacity)) {
    throw new Error('Choose an available resource slot.');
  }
  if (resourceSupply(state, resource) === 0) return false;
  const target = slot ?? player.resources.findIndex((item, index) => index < capacity && item === null);
  if (target < 0) return false; // Gained resource is immediately discarded if no slot is available.
  player.resources[target] = resource; // The previous token, if any, is discarded to the supply.
  if (uid === state.round.actorUid) state.turn.canRearrange = true;
  return true;
}

export function discardResource(state: GameState, uid: string, slot: number): Resource {
  const player = requirePlayer(state, uid);
  if (!Number.isInteger(slot) || slot < 0 || slot >= resourceCapacity(player.citiesOut)) throw new Error('Invalid resource slot.');
  const resource = player.resources[slot];
  if (!resource) throw new Error('That slot is empty.');
  player.resources[slot] = null;
  return resource;
}

export function placePiece(state: GameState, uid: string, kind: 'ship' | 'city' | 'starport', systemId: SystemId,
  damaged = false): GamePiece | null {
  requirePlayer(state, uid);
  if (!state.systems[systemId]) throw new Error('That system is out of play.');
  if (supplyOf(state, uid, kind) < 1) return null;
  if (kind !== 'ship') {
    const board = createBoard(state.activeClusters);
    const planet = board.planets[systemId];
    if (!planet || state.systems[systemId].filter((piece) => piece.kind === 'city' || piece.kind === 'starport').length >= planet.slots) {
      throw new Error('There is no empty building slot in that system.');
    }
    if (kind === 'city') state.players[uid].citiesOut++;
  }
  const piece: GamePiece = { id: `${uid}:${kind}:${state.nextPieceId++}`, owner: uid, kind, damaged };
  state.systems[systemId].push(piece);
  return piece;
}

function tax(state: GameState, uid: string, command: TaxAction): void {
  const location = pieceLocation(state, command.cityId);
  if (!location || location.piece.kind !== 'city') throw new Error('Choose a city on the map.');
  const { systemId, piece } = location;
  if (piece.owner !== uid && systemController(state, systemId) !== uid) throw new Error('You must control a Rival city to tax it.');
  if (state.turn.taxedCities.includes(piece.id)) throw new Error('A city can only be taxed once per turn.');
  const resource = createBoard(state.activeClusters).planets[systemId]?.resource;
  if (!resource) throw new Error('Cities cannot be built at gates.');
  state.turn.taxedCities.push(piece.id);
  gainResource(state, uid, resource, command.slot);
  if (piece.owner !== uid && supplyOf(state, piece.owner, 'agent') > 0) state.players[uid].captiveOwners.push(piece.owner);
}

function build(state: GameState, uid: string, command: BuildAction): void {
  const pieces = state.systems[command.systemId];
  if (!pieces) throw new Error('That system is out of play.');
  if (command.piece === 'ship') {
    const starport = pieces.find((piece) => piece.id === command.starportId && piece.owner === uid && piece.kind === 'starport');
    if (!starport) throw new Error('Build ships at a Loyal starport.');
    if (state.turn.builtAtStarports.includes(starport.id)) throw new Error('A starport can build one ship per turn.');
    if (supplyOf(state, uid, 'ship') < 1) throw new Error('No ships remain in your supply.');
    state.turn.builtAtStarports.push(starport.id);
  } else {
    if (!pieces.some((piece) => piece.owner === uid)) throw new Error('Build a building where you have a Loyal piece.');
    if (supplyOf(state, uid, command.piece) < 1) throw new Error(`No ${command.piece} remains in your supply.`);
  }
  const control = systemController(state, command.systemId);
  placePiece(state, uid, command.piece, command.systemId, control !== null && control !== uid);
}

function move(state: GameState, uid: string, command: MoveAction): void {
  const origin = state.systems[command.from];
  if (!origin || command.shipIds.length === 0 || new Set(command.shipIds).size !== command.shipIds.length) {
    throw new Error('Choose one or more distinct Loyal ships to move.');
  }
  if (command.shipIds.some((id) => !origin.some((piece) => piece.id === id && piece.owner === uid && piece.kind === 'ship'))) {
    throw new Error('Every moving ship must be Loyal and in the origin system.');
  }
  const catapult = origin.some((piece) => piece.owner === uid && piece.kind === 'starport');
  if (command.route.length === 0 || (!catapult && command.route.length !== 1) || command.route.length > 12) {
    throw new Error('A Move goes to one adjacent system unless launched from a Loyal starport.');
  }
  const board = createBoard(state.activeClusters);
  let current = command.from;
  let catapultStopped = false;
  const moving = new Set(command.shipIds);
  for (const [index, step] of command.route.entries()) {
    if (!isAdjacent(board, current, step.to) || !state.systems[step.to]) throw new Error('Every Move step must enter an adjacent active system.');
    if (index > 0 && catapultStopped) {
      throw new Error('A Catapult move stops at a planet or a Rival-controlled gate.');
    }
    const destinationController = systemController(state, step.to);
    const drops = index === command.route.length - 1 && step.dropShipIds.length === 0 ? [...moving] : step.dropShipIds;
    if (new Set(drops).size !== drops.length || drops.some((id) => !moving.has(id))) throw new Error('Ships may only be dropped off once.');
    for (const id of moving) {
      const from = state.systems[current];
      const pieceIndex = from.findIndex((piece) => piece.id === id);
      if (pieceIndex < 0) throw new Error('Moving ship lost its place.');
      state.systems[step.to].push(from.splice(pieceIndex, 1)[0]);
    }
    for (const id of drops) moving.delete(id);
    current = step.to;
    catapultStopped = !current.endsWith(':gate') || (destinationController !== null && destinationController !== uid);
    if (moving.size === 0 && index !== command.route.length - 1) throw new Error('No ships remain to continue the Catapult move.');
  }
  if (moving.size > 0) throw new Error('Finish the move by dropping off every ship.');
}

function repair(state: GameState, uid: string, command: RepairAction): void {
  const location = pieceLocation(state, command.pieceId);
  if (!location || location.piece.owner !== uid || !location.piece.damaged) throw new Error('Choose a damaged Loyal ship or building.');
  location.piece.damaged = false;
}

function influence(state: GameState, uid: string, command: InfluenceAction): void {
  if (!Number.isInteger(command.courtIndex) || command.courtIndex < 0 || command.courtIndex >= state.courtRow.length) {
    throw new Error('Choose a card in the Court.');
  }
  if (supplyOf(state, uid, 'agent') < 1) throw new Error('No agents remain in your supply.');
  const slot = state.courtRow[command.courtIndex];
  slot.agents[uid] = (slot.agents[uid] ?? 0) + 1;
}

function secure(state: GameState, uid: string, command: SecureAction): void {
  if (!Number.isInteger(command.courtIndex) || command.courtIndex < 0 || command.courtIndex >= state.courtRow.length) {
    throw new Error('Choose a card in the Court.');
  }
  const slot = state.courtRow[command.courtIndex];
  const loyal = slot.agents[uid] ?? 0;
  if (loyal < 1 || Object.entries(slot.agents).some(([owner, count]) => owner !== uid && count >= loyal)) {
    throw new Error('You need more agents than each Rival on that card.');
  }
  for (const [owner, count] of Object.entries(slot.agents)) {
    if (owner !== uid) for (let index = 0; index < count; index++) state.players[uid].captiveOwners.push(owner);
  }
  const card = cardById[slot.cardId];
  if (!card) throw new Error('Unknown Court card.');
  if (card.kind === 'guild') {
    state.players[uid].guilds.push(card.id);
    if (card.id === 'ARCS-BC03' || card.id === 'ARCS-BC06') {
      state.heldResources[card.id] = Array(resourceSupply(state, card.suit!)).fill(card.suit!);
    }
  }
  else { state.courtDiscard.push(card.id); state.pendingVox.push(card.id); }
  state.turn.securedThisPrelude.push(card.id);
  if (state.courtDeck.length > 0) state.courtRow[command.courtIndex] = { cardId: state.courtDeck.shift()!, agents: {} };
  else state.courtRow.splice(command.courtIndex, 1);
}

export function applyStandardAction(state: GameState, uid: string, action: StandardActionInput): void {
  requirePlayer(state, uid);
  switch (action.kind) {
    case 'tax': return tax(state, uid, action);
    case 'build': return build(state, uid, action);
    case 'move': return move(state, uid, action);
    case 'repair': return repair(state, uid, action);
    case 'influence': return influence(state, uid, action);
    case 'secure': return secure(state, uid, action);
  }
}
