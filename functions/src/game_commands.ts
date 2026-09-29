import { randomInt } from 'node:crypto';
import { actionCard } from './action_cards';
import type { Resource, SystemId } from './board';
import { endTurn, passInitiative, playCard, spendPip, type PlayMode, type StandardAction, type Suit } from './chapter';
import { applyStandardAction, discardResource, type StandardActionInput } from './game_actions';
import { placePiece, supplyOf } from './game_actions';
import { assignBattleHits, beginBattle, finishBattleRaid, raidBattle, rerollSkirmish,
  type BattleRoll, type HitAssignment, type RaidTarget } from './game_battle';
import { applyGuildAction, applyGuildPrelude, guildBaseAction, type GuildAction, type GuildPrelude } from './game_guild';
import { advanceAfterChapter, availableMarker, chooseResourcesAfterCityReturn, closeChapter,
  currentDecisionUid, emptyTurn, shuffled, type GameState } from './game_state';
import { timerMilliseconds } from './lobby';
import type { Ambition } from './rules';
import { castKickVote } from './session';
import { resolveVox, type VoxChoice } from './game_vox';

export type GameCommand =
  | { kind: 'mulligan'; replace: boolean }
  | { kind: 'play'; cardId: string; mode: PlayMode; declare?: Ambition; extraCardId?: string; bardDeclare?: Ambition }
  | { kind: 'pass' }
  | { kind: 'pip'; action: PlayableAction }
  | { kind: 'resource'; slot: number; as: Resource; action?: PlayableAction }
  | { kind: 'guild-prelude'; effect: GuildPrelude }
  | { kind: 'farseers-target'; targetUid: string }
  | { kind: 'farseers-swap'; myCardId?: string; rivalCardId?: string }
  | { kind: 'choose-resources'; slots: (Resource | null)[] }
  | { kind: 'rearrange-resources'; slots: (Resource | null)[] }
  | { kind: 'recover'; gateId: SystemId }
  | { kind: 'end-turn' }
  | { kind: 'reroll-skirmish'; faceIndexes: number[] }
  | { kind: 'assign-hits'; assignment: HitAssignment }
  | { kind: 'raid'; target: RaidTarget }
  | { kind: 'finish-raid' }
  | { kind: 'vox'; choice: VoxChoice }
  | { kind: 'vote-kick'; targetUid: string }
  | { kind: 'concede' };

export type CommandResult = { state: GameState; summary: string; changed: boolean };
type Random = (max: number) => number;
export type PlayableAction = StandardActionInput | ({ kind: 'battle' } & BattleRoll) | GuildAction;

const rankAmbition: Partial<Record<number, Ambition>> = {
  2: 'tycoon', 3: 'tyrant', 4: 'warlord', 5: 'keeper', 6: 'empath',
};
const suitActions: Record<Suit, readonly StandardAction[]> = {
  administration: ['tax', 'repair', 'influence'], aggression: ['battle', 'move', 'secure'],
  construction: ['build', 'repair'], mobilization: ['move', 'influence'],
};

function parseCardId(id: string) {
  const match = /^(administration|aggression|construction|mobilization)-([1-7])$/.exec(id);
  if (!match) throw new Error('Unknown action card.');
  return actionCard(match[1] as Suit, Number(match[2]));
}

function requireTurn(state: GameState, uid: string): void {
  if (state.round.actorUid !== uid) throw new Error('It is not your turn.');
}

function isGuildAction(input: PlayableAction): input is GuildAction {
  return ['manufacture', 'synthesize', 'pressgang', 'execute', 'abduct', 'trade'].includes(input.kind);
}

function actionName(input: PlayableAction): StandardAction {
  return isGuildAction(input) ? guildBaseAction(input) : input.kind;
}

function act(state: GameState, uid: string, action: PlayableAction, random: Random): void {
  if (action.kind === 'battle') beginBattle(state, uid, action, random);
  else if (isGuildAction(action)) applyGuildAction(state, uid, action);
  else applyStandardAction(state, uid, action);
}

function battleSummary(state: GameState): string {
  const battle = state.pendingBattle;
  if (!battle) return '';
  const tally = battle.faces.reduce((total, face) => ({
    own: total.own + face.own, ships: total.ships + face.ship,
    buildings: total.buildings + face.building, keys: total.keys + face.keys,
    intercept: total.intercept || face.intercept,
  }), { own: 0, ships: 0, buildings: 0, keys: 0, intercept: false });
  return ` Rolled ${tally.own} self hits, ${tally.ships} ship hits, ${tally.buildings} building hits, ` +
    `${tally.keys} keys${tally.intercept ? ', and interception' : ''}.`;
}

function play(state: GameState, uid: string, command: Extract<GameCommand, { kind: 'play' }>): string {
  const retainRank = !!command.declare && ['keeper', 'empath'].includes(command.declare) &&
    state.players[uid].guilds.includes('ARCS-BC18');
  const round = playCard(state.round, uid, command.cardId, command.mode, {
    declare: command.declare, extraCardId: command.extraCardId, retainRank,
  });
  state.round = round;
  state.turn = { ...emptyTurn(), preludeOpen: true };
  if (command.declare) {
    state.markers.push(availableMarker(state, command.declare));
    state.declaredThisRound = true;
    if (state.players[uid].guilds.includes('ARCS-BC17')) state.pendingFarseers = { uid };
  }
  if (command.bardDeclare) {
    const card = round.plays[round.plays.length - 1].card;
    if (!state.players[uid].guilds.includes('ARCS-BC25') || !['surpass', 'pivot'].includes(command.mode) ||
      state.declaredThisRound || (card.rank !== 7 && rankAmbition[card.rank] !== command.bardDeclare)) {
      throw new Error('Galactic Bards cannot declare that ambition now.');
    }
    state.markers.push(availableMarker(state, command.bardDeclare));
    state.round.availableAmbitions--;
    state.round.declaredAmbitions.push(command.bardDeclare);
    state.declaredThisRound = true;
    if (state.players[uid].guilds.includes('ARCS-BC17')) state.pendingFarseers = { uid };
  }
  return command.mode === 'copy' ? `${state.players[uid].name} copied the lead card.` :
    `${state.players[uid].name} played ${command.cardId} to ${command.mode}${command.declare ? ` and declared ${command.declare}` : ''}.`;
}

function spendResourcePrelude(state: GameState, uid: string, command: Extract<GameCommand, { kind: 'resource' }>, random: Random): string {
  requireTurn(state, uid);
  if (!state.round.playedThisTurn || !state.turn.preludeOpen) throw new Error('Resources can only be spent in your Prelude.');
  const actual = state.players[uid].resources[command.slot];
  if (!actual) throw new Error('Choose a resource you hold.');
  const loyalGuild: Record<Resource, string> = { material: 'ARCS-BC01', fuel: 'ARCS-BC07',
    weapon: 'ARCS-BC15', psionic: 'ARCS-BC19', relic: 'ARCS-BC21' };
  const converted = actual !== command.as;
  if (converted && !state.players[uid].guilds.includes(loyalGuild[command.as])) {
    throw new Error('A Loyal Guild is required to spend another resource as this type.');
  }
  if (state.players[uid].outrage.includes(command.as) && !state.players[uid].guilds.includes(loyalGuild[command.as])) {
    throw new Error('That resource action is Outraged.');
  }
  if (command.as === 'weapon') {
    if (command.action) throw new Error('A Weapon enables Battle pips; it does not take an action itself.');
  } else {
    if (!command.action) throw new Error('Choose the action granted by the resource.');
    const kind = actionName(command.action);
    const allowed = command.as === 'material' ? ['build', 'repair']
      : command.as === 'fuel' ? ['move'] : command.as === 'relic' ? ['secure']
        : suitActions[state.round.lead!.card.suit];
    if (!allowed.includes(kind)) throw new Error('That resource cannot take the chosen action.');
  }
  const spent = discardResource(state, uid, command.slot);
  state.turn.canRearrange = false;
  state.turn.spentResources.push(spent);
  if (command.as === 'weapon') state.turn.weaponEnabled = true;
  else act(state, uid, command.action!, random);
  return `${state.players[uid].name} spent ${actual} as ${command.as}` +
    (command.action ? ` for ${command.action.kind} in the Prelude.` : '.') +
    (command.action?.kind === 'battle' ? battleSummary(state) : '');
}

function usePip(state: GameState, uid: string, command: Extract<GameCommand, { kind: 'pip' }>, random: Random): string {
  requireTurn(state, uid);
  if (!state.round.playedThisTurn) throw new Error('Play an action card before taking actions.');
  const kind = actionName(command.action);
  if (kind === 'battle' && state.turn.weaponEnabled) {
    if (state.round.remainingPips < 1) throw new Error('No action pips remain.');
    state.round.remainingPips--;
  } else state.round = spendPip(state.round, uid, kind);
  state.turn.preludeOpen = false;
  state.turn.canRearrange = false;
  state.turn.spentResources = [];
  act(state, uid, command.action, random);
  return `${state.players[uid].name} took a ${command.action.kind} action.` +
    (command.action.kind === 'battle' ? battleSummary(state) : '');
}

function mulligan(state: GameState, uid: string, replace: boolean, random: Random): string {
  if (state.mulliganPendingUid !== uid || state.order.length !== 2) throw new Error('No mulligan is available.');
  if (replace) {
    if (state.actionDiscard.length < 6) throw new Error('The action deck cannot supply a new hand.');
    const oldHand = state.round.hands[uid];
    state.round.hands[uid] = state.actionDiscard.splice(0, 6);
    state.actionDiscard = shuffled([...state.actionDiscard, ...oldHand], random);
  }
  state.mulliganPendingUid = null;
  return `${state.players[uid].name} ${replace ? 'took' : 'kept their hand instead of taking'} a mulligan.`;
}

function finishTurn(state: GameState, uid: string, now: number, random: Random): string {
  requireTurn(state, uid);
  if (!state.round.playedThisTurn) throw new Error('Play a card or pass initiative.');
  const hasPresence = Object.values(state.systems).some((pieces) => pieces.some((piece) =>
    piece.owner === uid && (piece.kind === 'ship' || piece.kind === 'starport')));
  if (!hasPresence && !state.pendingRecoveryUid && supplyOf(state, uid, 'ship') > 0) {
    state.pendingRecoveryUid = uid;
    return `${state.players[uid].name} must place three ships in a gate before their turn ends.`;
  }
  const before = state.round;
  const next = endTurn(before, uid);
  if (!next.lead) {
    const reserved = new Set(state.unionReservations
      .filter((item) => state.players[item.uid].guilds.includes(item.guildId))
      .map((item) => item.actionCardId));
    for (const played of before.plays) {
      if (!reserved.has(played.card.id)) state.actionDiscard.push(played.card);
      if (played.extraCardId) state.actionDiscard.push(parseCardId(played.extraCardId));
    }
    for (const reservation of state.unionReservations) {
      const owner = state.players[reservation.uid];
      const card = before.plays.find((played) => played.card.id === reservation.actionCardId)?.card;
      if (card && owner.guilds.includes(reservation.guildId)) {
        next.hands[owner.uid].push(card);
        owner.guilds.splice(owner.guilds.indexOf(reservation.guildId), 1);
        state.courtDiscard.push(reservation.guildId);
      }
    }
    state.unionReservations = [];
    if (next.chapterEnded && state.order.some((playerUid) => next.hands[playerUid].length > 0)) {
      next.chapterEnded = false; next.ended = false; next.actorUid = next.initiativeUid;
    }
    state.declaredThisRound = false;
  }
  state.round = next;
  state.turn = emptyTurn();
  if (next.chapterEnded) {
    Object.assign(state, closeChapter(state, now, random));
    if (state.pendingResourceChoices.length > 0) return 'Chapter scoring is complete; players must choose resources to keep.';
    return state.status === 'finished' ? `Chapter ${state.chapter} ended. The match is finished.`
      : `Chapter ${state.chapter - 1} ended; chapter ${state.chapter} begins.`;
  }
  state.deadlineMs = now + timerMilliseconds(state.timer);
  return `${state.players[uid].name} ended their turn.`;
}

export function applyGameCommand(source: GameState, uid: string, commandId: string, command: GameCommand,
  now: number, random: Random = randomInt): CommandResult {
  if (!source.order.includes(uid)) throw new Error('Only seated players may command this match.');
  if (source.recentCommands.includes(commandId)) return { state: source, summary: 'Already applied.', changed: false };
  if (source.status !== 'playing') throw new Error('This match is no longer active.');
  const state = structuredClone(source);
  let summary: string;
  if (command.kind === 'vote-kick') {
    const voted = castKickVote({ memberIds: state.order, actorUid: currentDecisionUid(state)!,
      deadlineMs: state.deadlineMs, status: state.status, vote: state.vote }, uid, command.targetUid, now);
    state.vote = voted.vote;
    if (voted.status === 'terminated') {
      state.status = 'terminated'; state.winnerUid = null; state.termination = voted.termination;
    }
    summary = `${state.players[uid].name} voted to remove the overdue player.`;
  } else if (command.kind === 'concede') {
    state.status = 'terminated';
    state.winnerUid = null;
    state.termination = { reason: 'concession', targetUid: uid, at: now };
    summary = `${state.players[uid].name} conceded the match.`;
  } else {
    if (state.pendingResourceChoices.length > 0 && command.kind !== 'choose-resources') {
      throw new Error('Wait for the resource-slot choice.');
    }
    if (state.pendingRecoveryUid && command.kind !== 'recover') {
      throw new Error('Place recovery ships in a gate before the turn ends.');
    }
    if (state.mulliganPendingUid && command.kind !== 'mulligan') throw new Error('Wait for the two-player mulligan decision.');
    if (state.pendingFarseers && !['farseers-target', 'farseers-swap'].includes(command.kind)) {
      throw new Error('Finish Farseers’ hand choice before continuing.');
    }
    if (state.pendingVox.length > 0 && state.pendingResourceChoices.length === 0 &&
      !state.pendingFarseers && command.kind !== 'vox') {
      throw new Error('Resolve the secured Vox first.');
    }
    if (state.pendingBattle && state.pendingResourceChoices.length === 0 && !state.pendingFarseers &&
      !['reroll-skirmish', 'assign-hits', 'raid', 'finish-raid'].includes(command.kind)) {
      throw new Error('Finish the battle before taking another action.');
    }
    if (!state.pendingBattle && ['reroll-skirmish', 'assign-hits', 'raid', 'finish-raid'].includes(command.kind)) {
      throw new Error('There is no pending battle.');
    }
    switch (command.kind) {
      case 'mulligan': summary = mulligan(state, uid, command.replace, random); break;
      case 'play': requireTurn(state, uid); summary = play(state, uid, command); break;
      case 'pass': {
        requireTurn(state, uid);
        state.round = passInitiative(state.round, uid);
        state.turn = emptyTurn();
        if (state.round.chapterEnded) Object.assign(state, closeChapter(state, now, random));
        else state.deadlineMs = now + timerMilliseconds(state.timer);
        summary = `${state.players[uid].name} passed initiative.`;
        break;
      }
      case 'pip': summary = usePip(state, uid, command, random); break;
      case 'resource': summary = spendResourcePrelude(state, uid, command, random); break;
      case 'guild-prelude': requireTurn(state, uid); state.turn.canRearrange = false;
        applyGuildPrelude(state, uid, command.effect);
        summary = `${state.players[uid].name} used ${command.effect.kind} in the Prelude.`; break;
      case 'farseers-target': {
        if (state.pendingFarseers?.uid !== uid || !state.players[command.targetUid] || command.targetUid === uid ||
          state.pendingFarseers.targetUid) throw new Error('Choose one Rival hand to inspect.');
        state.pendingFarseers.targetUid = command.targetUid;
        summary = `${state.players[uid].name} inspected a Rival hand with Farseers.`;
        break;
      }
      case 'farseers-swap': {
        const pending = state.pendingFarseers;
        if (!pending || pending.uid !== uid) throw new Error('No Farseers choice is pending.');
        if (!!command.myCardId !== !!command.rivalCardId) throw new Error('Choose both cards or skip the swap.');
        if (command.myCardId) {
          if (!pending.targetUid) throw new Error('Inspect a Rival hand first.');
          const mine = state.round.hands[uid];
          const theirs = state.round.hands[pending.targetUid];
          const myIndex = mine.findIndex((card) => card.id === command.myCardId);
          const theirIndex = theirs.findIndex((card) => card.id === command.rivalCardId);
          if (myIndex < 0 || theirIndex < 0) throw new Error('Choose cards currently in both hands.');
          [mine[myIndex], theirs[theirIndex]] = [theirs[theirIndex], mine[myIndex]];
        }
        state.pendingFarseers = undefined;
        summary = `${state.players[uid].name} resolved Farseers.`;
        break;
      }
      case 'choose-resources': {
        chooseResourcesAfterCityReturn(state, uid, command.slots);
        if (state.pendingResourceChoices.length === 0 && state.chapterOutcomeWinnerUid !== undefined) {
          Object.assign(state, advanceAfterChapter(state, now, random));
        }
        summary = `${state.players[uid].name} chose resources to keep.`;
        break;
      }
      case 'rearrange-resources': {
        requireTurn(state, uid);
        if (!state.turn.canRearrange) throw new Error('Rearrange resources when you take one.');
        const player = state.players[uid];
        const capacity = [2, 3, 4, 6, 6, 6][player.citiesOut];
        if (command.slots.length !== capacity) throw new Error('Fill your current resource slots.');
        for (const resource of ['material', 'fuel', 'weapon', 'relic', 'psionic'] as Resource[]) {
          if (command.slots.filter((item) => item === resource).length !==
            player.resources.filter((item) => item === resource).length) {
            throw new Error('Rearrangement cannot add or discard resources.');
          }
        }
        player.resources = [...command.slots, ...Array<null>(6 - capacity).fill(null)];
        state.turn.canRearrange = false;
        summary = `${player.name} rearranged resources.`;
        break;
      }
      case 'recover': {
        if (state.pendingRecoveryUid !== uid || !command.gateId.endsWith(':gate') ||
          !Object.hasOwn(state.systems, command.gateId)) throw new Error('Choose an active gate for recovery.');
        for (let index = 0; index < 3; index++) placePiece(state, uid, 'ship', command.gateId);
        state.pendingRecoveryUid = undefined;
        summary = finishTurn(state, uid, now, random);
        break;
      }
      case 'end-turn': summary = finishTurn(state, uid, now, random); break;
      case 'reroll-skirmish': rerollSkirmish(state, uid, command.faceIndexes, random);
        summary = `${state.players[uid].name} rerolled ${command.faceIndexes.length} skirmish dice.${battleSummary(state)}`; break;
      case 'assign-hits': assignBattleHits(state, uid, command.assignment);
        summary = `${state.players[uid].name} assigned ${command.assignment.own.length} self, ` +
          `${command.assignment.ships.length} ship, and ${command.assignment.buildings.length} building hits.`; break;
      case 'raid': {
        const defender = state.pendingBattle?.defenderUid;
        const stolenResource = command.target.kind === 'resource' && defender
          ? state.players[defender].resources[command.target.slot] : null;
        raidBattle(state, uid, command.target);
        summary = `${state.players[uid].name} raided ${command.target.kind === 'guild' ? command.target.cardId :
          stolenResource ?? 'a resource'}.`;
        break;
      }
      case 'finish-raid': finishBattleRaid(state, uid); summary = 'The raid ended.'; break;
      case 'vox': {
        const voxId = state.pendingVox[0];
        resolveVox(state, uid, command.choice);
        summary = `${state.players[uid].name} resolved ${voxId}.`;
        break;
      }
    }
  }
  state.updatedAt = now;
  state.version++;
  state.recentCommands = [...state.recentCommands.slice(-49), commandId];
  if (currentDecisionUid(state) !== currentDecisionUid(source) && state.status === 'playing') {
    state.vote = undefined;
    state.deadlineMs = now + timerMilliseconds(state.timer);
  }
  return { state, summary, changed: true };
}
