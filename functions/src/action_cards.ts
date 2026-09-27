import type { ActionCard, Suit } from './chapter';

// Verified against the base card examples in the official rulebook (pp. 3,
// 8–10) and cross-checked with haunt-roll-fail's MIT-licensed ARCS deck table
// at commit d157b02. See THIRD_PARTY_NOTICES.md.
const pips: Record<Suit, readonly number[]> = {
  administration: [4, 4, 3, 3, 3, 2, 1],
  aggression: [3, 3, 2, 2, 2, 2, 1],
  construction: [4, 4, 3, 3, 2, 2, 1],
  mobilization: [4, 4, 3, 3, 2, 2, 1],
};
const suits: Suit[] = ['administration', 'aggression', 'construction', 'mobilization'];

export function actionCard(suit: Suit, rank: number): ActionCard {
  if (!Number.isInteger(rank) || rank < 1 || rank > 7) throw new Error('Invalid action-card rank.');
  return { id: `${suit}-${rank}`, suit, rank, pips: pips[suit][rank - 1] };
}

export function actionDeck(playerCount: number): ActionCard[] {
  if (!Number.isInteger(playerCount) || playerCount < 2 || playerCount > 4) {
    throw new Error('ARCS requires two to four players.');
  }
  const ranks = playerCount === 4 ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6];
  return suits.flatMap((suit) => ranks.map((rank) => actionCard(suit, rank)));
}
