// Action-card and round flow from Arcs Base Rulebook (2025-08-27), pp. 8–11.
// This is a pure rules component; the authoritative game service must own the
// hands and must not expose them through a public Firestore document.
import type { Ambition } from './rules';

export type Suit = 'administration' | 'aggression' | 'construction' | 'mobilization';
export type StandardAction = 'tax' | 'build' | 'move' | 'repair' | 'influence' | 'secure' | 'battle';
export type PlayMode = 'lead' | 'surpass' | 'copy' | 'pivot';
export type ActionCard = { id: string; suit: Suit; rank: number; pips: number };
export type CardPlay = {
  uid: string;
  card: ActionCard;
  mode: PlayMode;
  extraCardId?: string;
  declared?: Ambition;
  retainRank?: boolean;
};
export type ChapterRound = {
  order: string[];
  hands: Record<string, ActionCard[]>;
  initiativeUid: string;
  actorUid: string | null;
  lead?: CardPlay;
  plays: CardPlay[];
  seizedUid?: string;
  availableAmbitions: number;
  declaredAmbitions: Ambition[];
  remainingPips: number;
  playedThisTurn: boolean;
  highestSurpass?: { uid: string; rank: number };
  consecutivePasses: number;
  ended: boolean;
  chapterEnded: boolean;
};

const rankAmbition: Partial<Record<number, Ambition>> = {
  2: 'tycoon', 3: 'tyrant', 4: 'warlord', 5: 'keeper', 6: 'empath',
};
const suitActions: Record<Suit, StandardAction[]> = {
  administration: ['tax', 'repair', 'influence'],
  aggression: ['battle', 'move', 'secure'],
  construction: ['build', 'repair'],
  mobilization: ['move', 'influence'],
};

function requireActor(state: ChapterRound, uid: string) {
  if (state.ended || state.actorUid !== uid) throw new Error('It is not your turn.');
}
function withRemoved(hand: ActionCard[], id: string): { card: ActionCard; remaining: ActionCard[] } {
  const card = hand.find((item) => item.id === id);
  if (!card) throw new Error('You do not have that action card.');
  return { card, remaining: hand.filter((item) => item.id !== id) };
}
function clockwise(state: ChapterRound, from: string): string[] {
  const start = state.order.indexOf(from);
  if (start < 0) throw new Error('Player is not seated.');
  return [...state.order.slice(start + 1), ...state.order.slice(0, start + 1)];
}
function nextWithCards(state: ChapterRound, from: string): string | null {
  return clockwise(state, from).find((uid) => (state.hands[uid]?.length ?? 0) > 0) ?? null;
}

export function newChapterRound(order: string[], hands: Record<string, ActionCard[]>, initiativeUid: string): ChapterRound {
  if (order.length < 2 || order.length > 4 || new Set(order).size !== order.length || !order.includes(initiativeUid)) {
    throw new Error('A round requires two to four distinct seated players.');
  }
  if (order.some((uid) => !hands[uid])) throw new Error('Every player needs a hand.');
  return {
    order, hands, initiativeUid, actorUid: initiativeUid, plays: [], availableAmbitions: 3,
    declaredAmbitions: [], remainingPips: 0, playedThisTurn: false, consecutivePasses: 0,
    ended: false, chapterEnded: false,
  };
}

export function playCard(
  state: ChapterRound, uid: string, cardId: string, mode: PlayMode,
  options: { declare?: Ambition; extraCardId?: string; retainRank?: boolean } = {},
): ChapterRound {
  requireActor(state, uid);
  if (state.playedThisTurn) throw new Error('You already played an action card this turn.');
  const { card, remaining } = withRemoved(state.hands[uid], cardId);
  if (card.rank < 1 || card.rank > 7 || card.pips < 1 || card.pips > 4) throw new Error('Invalid action card.');
  const isLead = state.lead === undefined;
  if (isLead !== (mode === 'lead')) throw new Error('Only the initiative player leads the round.');
  if (!isLead) {
    const lead = state.lead!;
    const leadRank = lead.declared && !lead.retainRank ? 0 : lead.card.rank;
    if (mode === 'surpass' && (card.suit !== lead.card.suit || card.rank <= leadRank)) {
      throw new Error('Surpass requires the lead suit and a higher rank.');
    }
    if (mode === 'pivot' && card.suit === lead.card.suit) throw new Error('Pivot requires a different suit.');
  }
  if (options.declare) {
    if (!isLead || state.availableAmbitions === 0) throw new Error('Only the lead can declare an available ambition.');
    if (card.rank === 1 || (card.rank !== 7 && rankAmbition[card.rank] !== options.declare)) {
      throw new Error('This card cannot declare that ambition.');
    }
  }
  if (options.retainRank && (!options.declare || !isLead)) throw new Error('Only a declared lead can retain its rank.');
  if (options.extraCardId && (uid === state.initiativeUid || state.seizedUid)) {
    throw new Error('Initiative cannot be seized now.');
  }
  let nextHand = remaining;
  if (options.extraCardId) nextHand = withRemoved(remaining, options.extraCardId).remaining;
  const automaticSeize = mode === 'surpass' && card.rank === 7 && !state.seizedUid && uid !== state.initiativeUid;
  const seizedUid = options.extraCardId || automaticSeize ? uid : state.seizedUid;
  const play: CardPlay = { uid, card, mode, ...(options.extraCardId ? { extraCardId: options.extraCardId } : {}),
    ...(options.declare ? { declared: options.declare } : {}),
    ...(options.retainRank ? { retainRank: true } : {}) };
  const highestSurpass = mode === 'surpass' && (!state.highestSurpass || card.rank > state.highestSurpass.rank)
    ? { uid, rank: card.rank } : state.highestSurpass;
  return {
    ...state,
    hands: { ...state.hands, [uid]: nextHand },
    lead: isLead ? play : state.lead,
    plays: [...state.plays, play],
    seizedUid,
    initiativeUid: seizedUid ?? state.initiativeUid,
    availableAmbitions: state.availableAmbitions - (options.declare ? 1 : 0),
    declaredAmbitions: options.declare ? [...state.declaredAmbitions, options.declare] : state.declaredAmbitions,
    highestSurpass,
    remainingPips: mode === 'lead' || mode === 'surpass' ? card.pips : 1,
    playedThisTurn: true,
    consecutivePasses: 0,
  };
}

export function spendPip(state: ChapterRound, uid: string, action: StandardAction): ChapterRound {
  requireActor(state, uid);
  if (!state.playedThisTurn || state.remainingPips < 1) throw new Error('No action pips remain.');
  const play = state.plays[state.plays.length - 1];
  const suit = play.mode === 'copy' ? state.lead!.card.suit : play.card.suit;
  if (!suitActions[suit].includes(action)) throw new Error('This action is not allowed by the played card.');
  return { ...state, remainingPips: state.remainingPips - 1 };
}

export function endTurn(state: ChapterRound, uid: string): ChapterRound {
  requireActor(state, uid);
  if (!state.playedThisTurn) throw new Error('Play a card or pass initiative first.');
  const next = clockwise(state, uid).find((candidate) =>
    candidate !== state.lead!.uid && !state.plays.some((play) => play.uid === candidate)
      && (state.hands[candidate]?.length ?? 0) > 0);
  if (next) return { ...state, actorUid: next, remainingPips: 0, playedThisTurn: false };
  const initiativeUid = state.seizedUid ?? state.highestSurpass?.uid ?? state.initiativeUid;
  const chapterEnded = state.order.every((player) => state.hands[player].length === 0);
  return {
    ...state, initiativeUid, actorUid: chapterEnded ? null : initiativeUid,
    lead: undefined, plays: [], seizedUid: undefined, highestSurpass: undefined,
    remainingPips: 0, playedThisTurn: false, ended: chapterEnded, chapterEnded,
  };
}

export function passInitiative(state: ChapterRound, uid: string): ChapterRound {
  requireActor(state, uid);
  if (state.lead || uid !== state.initiativeUid || state.playedThisTurn) {
    throw new Error('Only the player leading a new round may pass initiative.');
  }
  const next = nextWithCards(state, uid);
  if (!next) return { ...state, actorUid: null, ended: true, chapterEnded: true };
  const consecutivePasses = state.consecutivePasses + 1;
  const playersWithCards = state.order.filter((player) => state.hands[player].length > 0).length;
  if (consecutivePasses >= playersWithCards) {
    return { ...state, actorUid: null, ended: true, chapterEnded: true, consecutivePasses };
  }
  return { ...state, initiativeUid: next, actorUid: next, consecutivePasses };
}
