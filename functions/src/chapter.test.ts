import { describe, expect, it } from 'vitest';
import { endTurn, newChapterRound, passInitiative, playCard, spendPip, type ActionCard } from './chapter';

const card = (suit: ActionCard['suit'], rank: number, pips = 2): ActionCard => ({
  id: `${suit}-${rank}`, suit, rank, pips,
});

describe('action-card play (base rulebook pp. 8–11)', () => {
  it('declares only with the lead and makes its rank zero without losing pips', () => {
    const initial = newChapterRound(['a', 'b'], {
      a: [card('construction', 4, 3)], b: [card('construction', 2, 4)],
    }, 'a');
    const lead = playCard(initial, 'a', 'construction-4', 'lead', { declare: 'warlord' });
    expect(lead.remainingPips).toBe(3);
    expect(lead.declaredAmbitions).toEqual(['warlord']);
    const follow = playCard(endTurn(lead, 'a'), 'b', 'construction-2', 'surpass');
    expect(follow.remainingPips).toBe(4);
    expect(endTurn(follow, 'b').initiativeUid).toBe('b');
  });

  it('enforces surpass, pivot, copy and suit action limits', () => {
    let state = newChapterRound(['a', 'b', 'c'], {
      a: [card('administration', 4)],
      b: [card('administration', 3), card('aggression', 2)],
      c: [card('construction', 5)],
    }, 'a');
    state = endTurn(playCard(state, 'a', 'administration-4', 'lead'), 'a');
    expect(() => playCard(state, 'b', 'administration-3', 'surpass')).toThrow('Surpass');
    expect(() => playCard(state, 'b', 'administration-3', 'pivot')).toThrow('Pivot');
    state = playCard(state, 'b', 'administration-3', 'copy');
    expect(() => spendPip(state, 'b', 'build')).toThrow('not allowed');
    state = spendPip(state, 'b', 'tax');
    expect(() => spendPip(state, 'b', 'repair')).toThrow('No action pips');
    state = endTurn(state, 'b');
    state = playCard(state, 'c', 'construction-5', 'pivot');
    expect(() => spendPip(state, 'c', 'tax')).toThrow('not allowed');
    expect(spendPip(state, 'c', 'build').remainingPips).toBe(0);
  });

  it('awards initiative to the highest surpass unless a player seizes', () => {
    let state = newChapterRound(['a', 'b', 'c'], {
      a: [card('mobilization', 2)],
      b: [card('mobilization', 5), card('aggression', 3)],
      c: [card('mobilization', 6)],
    }, 'a');
    state = endTurn(playCard(state, 'a', 'mobilization-2', 'lead'), 'a');
    state = endTurn(playCard(state, 'b', 'mobilization-5', 'surpass', { extraCardId: 'aggression-3' }), 'b');
    expect(state.initiativeUid).toBe('b');
    expect(() => playCard(state, 'c', 'mobilization-6', 'surpass', { extraCardId: 'mobilization-6' }))
      .toThrow('Initiative cannot be seized');
    state = endTurn(playCard(state, 'c', 'mobilization-6', 'surpass'), 'c');
    expect(state.initiativeUid).toBe('b');
    expect(state.chapterEnded).toBe(true);
  });

  it('lets a 7 seize only if nobody else has seized this round', () => {
    let state = newChapterRound(['a', 'b'], {
      a: [card('aggression', 2)], b: [card('aggression', 7)],
    }, 'a');
    state = endTurn(playCard(state, 'a', 'aggression-2', 'lead'), 'a');
    state = playCard(state, 'b', 'aggression-7', 'surpass');
    expect(state.seizedUid).toBe('b');
    expect(state.remainingPips).toBe(2);
  });

  it('ends a chapter when everyone with cards passes consecutively', () => {
    const initial = newChapterRound(['a', 'b'], {
      a: [card('construction', 3)], b: [card('mobilization', 3)],
    }, 'a');
    const passed = passInitiative(initial, 'a');
    expect(passed.actorUid).toBe('b');
    const ended = passInitiative(passed, 'b');
    expect(ended.chapterEnded).toBe(true);
  });

  it('rejects rank 1 ambition and a mismatched rank ambition', () => {
    const initial = newChapterRound(['a', 'b'], {
      a: [card('construction', 1), card('construction', 2)], b: [],
    }, 'a');
    expect(() => playCard(initial, 'a', 'construction-1', 'lead', { declare: 'tycoon' })).toThrow('cannot declare');
    expect(() => playCard(initial, 'a', 'construction-2', 'lead', { declare: 'warlord' })).toThrow('cannot declare');
  });
});
