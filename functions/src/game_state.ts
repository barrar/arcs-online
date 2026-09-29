import { randomInt } from 'node:crypto';
import { actionDeck } from './action_cards';
import { createBoard, type Resource, type SystemId } from './board';
import { newChapterRound, type ActionCard, type ChapterRound } from './chapter';
import { baseCourt, cardById } from './court';
import { timerMilliseconds, type Lobby, type Timer } from './lobby';
import { phantomScorer, scoreAmbitions, gameWinner, type Ambition, type AmbitionMarker, type ScoringPlayer } from './rules';
import { setupChoices, type SetupVariant } from './setup';

export const baseRulesVersion = 'arcs-base-2025-08-27';
export const raidCosts = [3, 1, 1, 2, 1, 3] as const;
export type GamePiece = { id: string; owner: string; kind: 'ship' | 'city' | 'starport' | 'agent'; damaged: boolean };
export type PlayerState = {
  uid: string;
  name: string;
  color: string;
  power: number;
  resources: (Resource | null)[];
  citiesOut: number;
  guilds: string[];
  trophies: GamePiece[];
  captiveOwners: string[];
  outrage: Resource[];
};
export type CourtSlot = { cardId: string; agents: Record<string, number> };
export type DeclaredMarker = AmbitionMarker & { index: number };
export type TurnRecord = {
  taxedCities: string[];
  builtAtStarports: string[];
  preludeOpen: boolean;
  weaponEnabled: boolean;
  spentResources: Resource[];
  securedThisPrelude: string[];
  usedGuilds: string[];
  canRearrange: boolean;
};
export type BattleFace = { die: 'assault' | 'skirmish' | 'raid'; own: number; intercept: boolean;
  ship: number; building: number; keys: number };
export type PendingBattle = {
  systemId: SystemId;
  attackerUid: string;
  defenderUid: string;
  faces: BattleFace[];
  phase: 'assign' | 'raid';
  keys: number;
  rerolled: boolean;
};
export type GameState = {
  id: string;
  name: string;
  rulesVersion: typeof baseRulesVersion;
  status: 'playing' | 'finished' | 'terminated';
  winnerUid: string | null;
  termination?: { reason: 'kick' | 'concession'; targetUid: string; at: number };
  timer: Timer;
  deadlineMs: number;
  vote?: { targetUid: string; approvals: string[]; deadlineMs: number };
  order: string[];
  setupId: string;
  activeClusters: number[];
  systems: Record<SystemId, GamePiece[]>;
  players: Record<string, PlayerState>;
  chapter: number;
  round: ChapterRound;
  mulliganPendingUid: string | null;
  declaredThisRound: boolean;
  markers: DeclaredMarker[];
  markerFlips: number;
  courtDeck: string[];
  courtRow: CourtSlot[];
  courtDiscard: string[];
  heldResources: Record<string, Resource[]>;
  actionDiscard: ActionCard[];
  phantomResources: Resource[];
  turn: TurnRecord;
  pendingBattle?: PendingBattle;
  pendingVox: string[];
  pendingFarseers?: { uid: string; targetUid?: string };
  pendingRecoveryUid?: string;
  pendingResourceChoices: string[];
  chapterOutcomeWinnerUid?: string | null;
  lastScoring?: { chapter: number; details: ReturnType<typeof scoreAmbitions>['details'];
    powerBefore: Record<string, number>; powerAfter: Record<string, number> };
  unionReservations: { uid: string; guildId: string; actionCardId: string }[];
  version: number;
  updatedAt: number;
  recentCommands: string[];
  nextPieceId: number;
};

export function shuffled<T>(items: readonly T[], random: (max: number) => number = randomInt): T[] {
  const result = [...items];
  for (let index = result.length - 1; index > 0; index--) {
    const other = random(index + 1);
    if (!Number.isInteger(other) || other < 0 || other > index) throw new Error('Invalid shuffle index.');
    [result[index], result[other]] = [result[other], result[index]];
  }
  return result;
}

export function resourceCapacity(citiesOut: number): number {
  if (!Number.isInteger(citiesOut) || citiesOut < 0 || citiesOut > 5) throw new Error('Invalid city count.');
  return [2, 3, 4, 6, 6, 6][citiesOut];
}

export function emptyTurn(): TurnRecord {
  return { taxedCities: [], builtAtStarports: [], preludeOpen: false, weaponEnabled: false,
    spentResources: [], securedThisPrelude: [], usedGuilds: [], canRearrange: false };
}

export function createGameState(lobby: Lobby, now: number, random: (max: number) => number = randomInt): GameState {
  if (lobby.seats.length < 2 || lobby.seats.length > 4) throw new Error('A match needs two to four seated players.');
  if (lobby.seats.some((seat) => !seat.ready)) throw new Error('Every player must be ready.');
  const order = lobby.seats.map((seat) => seat.uid);
  const initiativeIndex = random(order.length);
  const initiativeUid = order[initiativeIndex];
  const setupOptions = setupChoices(order.length);
  const setup = setupOptions[random(setupOptions.length)];
  return createGameWithSetup(lobby, setup, initiativeUid, now, random);
}

export function createGameWithSetup(
  lobby: Lobby, setup: SetupVariant, initiativeUid: string, now: number,
  random: (max: number) => number = randomInt,
): GameState {
  const count = lobby.seats.length;
  if (setup.playerCount !== count || setup.starting.length !== count) throw new Error('Setup does not match player count.');
  const clockwise = lobby.seats.map((seat) => seat.uid);
  if (!clockwise.includes(initiativeUid)) throw new Error('Initiative player is not seated.');
  const start = clockwise.indexOf(initiativeUid);
  const order = [...clockwise.slice(start), ...clockwise.slice(0, start)];
  const board = createBoard(setup.activeClusters);
  const systems = Object.fromEntries(Object.keys(board.adjacency).map((id) => [id, []])) as Record<SystemId, GamePiece[]>;
  const supply: Record<Resource, number> = { material: 5, fuel: 5, weapon: 5, relic: 5, psionic: 5 };
  const phantomResources: Resource[] = [];
  if (count === 2) {
    for (let cluster = 1; cluster <= 6; cluster++) {
      if (setup.activeClusters.includes(cluster)) continue;
      const covered = createBoard([cluster, (cluster % 6) + 1, ((cluster + 1) % 6) + 1, ((cluster + 2) % 6) + 1]);
      for (const planet of Object.values(covered.planets).filter((planet) => planet.cluster === cluster)) {
        phantomResources.push(planet.resource);
        supply[planet.resource]--;
      }
    }
  }
  const players: Record<string, PlayerState> = {};
  for (const [index, uid] of order.entries()) {
    const seat = lobby.seats.find((entry) => entry.uid === uid)!;
    const position = setup.starting[index];
    if (!board.planets[position.a] || !board.planets[position.b] || position.c.length !== (count === 2 ? 2 : 1)) {
      throw new Error('Setup card has an invalid starting position.');
    }
    const place = (systemId: SystemId, kind: GamePiece['kind'], amount: number) => {
      if (!(systemId in systems)) throw new Error('Setup card points to an out-of-play system.');
      for (let pieceIndex = 0; pieceIndex < amount; pieceIndex++) {
        systems[systemId].push({ id: `${uid}:${kind}:${index}:${systemId}:${pieceIndex}`, owner: uid, kind, damaged: false });
      }
    };
    place(position.a, 'city', 1);
    place(position.a, 'ship', 3);
    place(position.b, 'starport', 1);
    place(position.b, 'ship', 3);
    for (const systemId of position.c) place(systemId, 'ship', 2);
    const resources = [board.planets[position.a].resource, board.planets[position.b].resource];
    for (const resource of resources) {
      if (supply[resource] < 1) throw new Error('Setup card exhausts the resource supply.');
      supply[resource]--;
    }
    players[uid] = { uid, name: seat.name, color: seat.color, power: 0,
      resources: [resources[0], resources[1], null, null, null, null],
      citiesOut: 1, guilds: [], trophies: [], captiveOwners: [], outrage: [] };
  }
  const cards = shuffled(actionDeck(count), random);
  const hands: Record<string, ActionCard[]> = {};
  for (const uid of order) hands[uid] = cards.splice(0, 6);
  const courtDeck = shuffled(baseCourt.map((card) => card.id), random);
  const courtRow: CourtSlot[] = Array.from({ length: count === 2 ? 3 : 4 }, () => ({ cardId: courtDeck.shift()!, agents: {} }));
  return {
    id: lobby.id, name: lobby.name, rulesVersion: baseRulesVersion, status: 'playing', winnerUid: null,
    timer: lobby.timer, deadlineMs: now + timerMilliseconds(lobby.timer), order, setupId: setup.id,
    activeClusters: setup.activeClusters, systems, players, chapter: 1,
    round: newChapterRound(order, hands, initiativeUid), mulliganPendingUid: count === 2 ? order[1] : null,
    declaredThisRound: false, markers: [], markerFlips: 0,
    courtDeck, courtRow, courtDiscard: [], heldResources: {}, actionDiscard: shuffled(cards, random), phantomResources,
    turn: emptyTurn(), pendingVox: [], pendingResourceChoices: [], unionReservations: [],
    version: 0, updatedAt: now, recentCommands: [], nextPieceId: 0,
  };
}

export function scoringPlayers(state: GameState): ScoringPlayer[] {
  return state.order.map((uid) => {
    const player = state.players[uid];
    const held = player.guilds.flatMap((cardId) => state.heldResources[cardId] ?? []);
    return { uid, power: player.power, resources: [...player.resources.filter((item): item is Resource => item !== null), ...held],
      guildIcons: player.guilds.map((id) => cardById[id]?.suit).filter((item): item is Resource => item !== undefined),
      trophies: player.trophies.length, captives: player.captiveOwners.length, citiesBuilt: player.citiesOut };
  });
}

export function closeChapter(state: GameState, now: number, random: (max: number) => number = randomInt): GameState {
  if (!state.round.chapterEnded) throw new Error('The chapter has not ended.');
  const scoring = scoreAmbitions(scoringPlayers(state), state.markers,
    state.order.length === 2 ? phantomScorer(state.phantomResources) : undefined);
  const players = Object.fromEntries(Object.entries(state.players).map(([uid, player]) => [uid, {
    ...player, resources: [...player.resources], guilds: [...player.guilds], trophies: [...player.trophies],
    captiveOwners: [...player.captiveOwners], outrage: [...player.outrage],
  }])) as Record<string, PlayerState>;
  for (const scored of scoring.players) players[scored.uid] = { ...players[scored.uid], power: scored.power };
  for (const [cardId, resource] of [['ARCS-BC03', 'material'], ['ARCS-BC06', 'fuel']] as const) {
    const holder = state.order.find((uid) => players[uid].guilds.includes(cardId));
    if (holder) for (const uid of state.order) {
      if (uid !== holder) players[uid].resources = players[uid].resources.map((item) => item === resource ? null : item);
    }
  }
  const scoredAmbitions = new Set(state.markers.map((marker) => marker.ambition));
  if (scoredAmbitions.has('warlord')) {
    for (const player of Object.values(players)) {
      for (const piece of player.trophies) if (piece.kind === 'city') players[piece.owner].citiesOut--;
    }
    for (const player of Object.values(players)) player.trophies = [];
  }
  if (scoredAmbitions.has('tyrant')) for (const player of Object.values(players)) player.captiveOwners = [];
  const initiativeIndex = state.order.indexOf(state.round.initiativeUid);
  const turnOrder = [...state.order.slice(initiativeIndex), ...state.order.slice(0, initiativeIndex)];
  const winnerUid = gameWinner(scoring.players, turnOrder, state.chapter);
  const markerFlips = Math.min(3, state.markerFlips + 1);
  const awaiting: string[] = [];
  for (const uid of state.order) {
    const player = players[uid];
    const held = player.resources.filter((item): item is Resource => item !== null);
    const capacity = resourceCapacity(player.citiesOut);
    if (held.length > capacity) awaiting.push(uid);
    else player.resources = [...held, ...Array<null>(6 - held.length).fill(null)];
  }
  const scored = { ...state, players, markerFlips, markers: [], updatedAt: now,
    pendingResourceChoices: awaiting, chapterOutcomeWinnerUid: winnerUid,
    lastScoring: { chapter: state.chapter, details: scoring.details,
      powerBefore: Object.fromEntries(state.order.map((uid) => [uid, state.players[uid].power])),
      powerAfter: Object.fromEntries(state.order.map((uid) => [uid, players[uid].power])) } };
  if (awaiting.length > 0) return { ...scored, deadlineMs: now + timerMilliseconds(state.timer) };
  return advanceAfterChapter(scored, now, random);
}

export function advanceAfterChapter(state: GameState, now: number,
  random: (max: number) => number = randomInt): GameState {
  if (!state.round.chapterEnded || state.pendingResourceChoices.length > 0 || state.chapterOutcomeWinnerUid === undefined) {
    throw new Error('Chapter cleanup is not complete.');
  }
  const winnerUid = state.chapterOutcomeWinnerUid;
  if (winnerUid) return { ...state, winnerUid, status: 'finished', chapterOutcomeWinnerUid: undefined,
    updatedAt: now };
  const cards = shuffled(actionDeck(state.order.length), random);
  const hands: Record<string, ActionCard[]> = {};
  for (const uid of state.order) hands[uid] = cards.splice(0, 6);
  return { ...state, chapter: state.chapter + 1, chapterOutcomeWinnerUid: undefined,
    round: newChapterRound(state.order, hands, state.round.initiativeUid), actionDiscard: shuffled(cards, random),
    mulliganPendingUid: state.order.length === 2 ? state.order.find((uid) => uid !== state.round.initiativeUid)! : null,
    declaredThisRound: false,
    deadlineMs: now + timerMilliseconds(state.timer), turn: emptyTurn(), updatedAt: now };
}

export function chooseResourcesAfterCityReturn(state: GameState, uid: string, slots: (Resource | null)[]): void {
  if (state.pendingResourceChoices[0] !== uid) throw new Error('It is not your resource choice.');
  const player = state.players[uid];
  const capacity = resourceCapacity(player.citiesOut);
  if (slots.length !== capacity) throw new Error('Choose resources for the open slots.');
  const held = player.resources.filter((item): item is Resource => item !== null);
  const chosen = slots.filter((item): item is Resource => item !== null);
  if (chosen.length !== Math.min(held.length, capacity)) throw new Error('Keep as many resources as the open slots allow.');
  for (const resource of ['material', 'fuel', 'weapon', 'relic', 'psionic'] as Resource[]) {
    if (chosen.filter((item) => item === resource).length > held.filter((item) => item === resource).length) {
      throw new Error('You cannot keep a resource you did not hold.');
    }
  }
  player.resources = [...slots, ...Array<null>(6 - capacity).fill(null)];
  state.pendingResourceChoices.shift();
}

export function currentDecisionUid(state: GameState): string | null {
  return state.pendingResourceChoices[0] ?? state.pendingRecoveryUid ?? state.mulliganPendingUid ?? state.round.actorUid;
}

export function availableMarker(state: GameState, ambition: Ambition): DeclaredMarker {
  const values: readonly (readonly [number, number])[] = [[2, 0], [3, 2], [5, 3]];
  const flipped: readonly (readonly [number, number])[] = [[4, 2], [6, 3], [9, 4]];
  const available = [0, 1, 2]
    .filter((index) => !state.markers.some((marker) => marker.index === index))
    .sort((left, right) => {
      const leftValue = (left < state.markerFlips ? flipped : values)[left][0];
      const rightValue = (right < state.markerFlips ? flipped : values)[right][0];
      return rightValue - leftValue;
    })[0];
  if (available === undefined) throw new Error('No ambition markers remain.');
  const [first, second] = available < state.markerFlips ? flipped[available] : values[available];
  return { index: available, ambition, first, second };
}

export function publicGame(state: GameState): Record<string, unknown> {
  const { round, actionDiscard, courtDeck, recentCommands, pendingFarseers, ...rest } = state;
  void actionDiscard; void courtDeck; void recentCommands;
  const { hands, ...publicRound } = round;
  return { ...rest, farseersPendingUid: pendingFarseers?.uid ?? null,
    actorUid: currentDecisionUid(state), round: { ...publicRound,
    hands: Object.fromEntries(Object.entries(hands).map(([uid, hand]) => [uid, hand.length])),
    plays: round.plays.map((play) => play.mode === 'copy'
      ? { uid: play.uid, mode: play.mode, card: null, extraCardId: null }
      : { ...play, extraCardId: play.extraCardId ? 'face-down' : undefined }),
  }, courtDeckCount: courtDeck.length, actionDiscardCount: actionDiscard.length,
    memberIds: state.order };
}

export function privateHand(state: GameState, uid: string): Record<string, unknown> {
  const reveal = state.pendingFarseers?.uid === uid && state.pendingFarseers.targetUid
    ? { targetUid: state.pendingFarseers.targetUid,
      cards: state.round.hands[state.pendingFarseers.targetUid].map((card) => card.id) }
    : null;
  return { cards: state.round.hands[uid].map((card) => card.id), farseersReveal: reveal,
    chapter: state.chapter, version: state.version };
}
