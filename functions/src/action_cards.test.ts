import { describe, expect, it } from 'vitest';
import { actionCard, actionDeck } from './action_cards';

describe('official base action deck', () => {
  it('uses twenty cards for two or three players and twenty-eight for four', () => {
    for (const count of [2, 3, 4]) {
      const deck = actionDeck(count);
      expect(deck).toHaveLength(count === 4 ? 28 : 20);
      expect(new Set(deck.map((card) => card.id)).size).toBe(deck.length);
      expect(deck.some((card) => card.rank === 1 || card.rank === 7)).toBe(count === 4);
    }
  });
  it('matches rulebook card examples and suit-specific pip counts', () => {
    expect(actionCard('construction', 2).pips).toBe(4);
    expect(actionCard('construction', 4).pips).toBe(3);
    expect(actionCard('construction', 5).pips).toBe(2);
    expect(actionCard('aggression', 2).pips).toBe(3);
    expect(actionCard('administration', 5).pips).toBe(3);
    expect(actionCard('aggression', 1).pips).toBe(3);
  });
});
