import { describe, expect, it } from 'vitest';
import { controller, gameWinner, phantomScorer, scoreAmbitions, type ScoringPlayer } from './rules';

const player = (uid: string, changes: Partial<ScoringPlayer> = {}): ScoringPlayer => ({
  uid, power: 0, resources: [], guildIcons: [], trophies: 0, captives: 0, citiesBuilt: 0, ...changes,
});

describe('control', () => {
  it('counts only fresh ships and gives nobody control on a tie', () => {
    expect(controller({ id: '1a', pieces: [
      { owner: 'a', kind: 'ship', damaged: false },
      { owner: 'b', kind: 'ship', damaged: false },
      { owner: 'a', kind: 'ship', damaged: true },
      { owner: 'a', kind: 'city', damaged: false },
    ] })).toBeNull();
  });
});

describe('ambitions', () => {
  it('stacks markers but gives the city bonus only once', () => {
    const result = scoreAmbitions(
      [player('a', { resources: ['material', 'fuel'], citiesBuilt: 5 }), player('b', { guildIcons: ['fuel'] })],
      [{ ambition: 'tycoon', first: 5, second: 3 }, { ambition: 'tycoon', first: 3, second: 1 }],
    );
    expect(result.players.map((p) => p.power)).toEqual([13, 4]);
  });
  it('gives tied first-place players second-place power and leaves others unranked', () => {
    const result = scoreAmbitions(
      [player('a', { trophies: 2 }), player('b', { trophies: 2 }), player('c', { trophies: 1 })],
      [{ ambition: 'warlord', first: 5, second: 3 }],
    );
    expect(result.players.map((p) => p.power)).toEqual([3, 3, 0]);
  });
  it('awards nothing for a second-place tie or zero qualification', () => {
    const result = scoreAmbitions(
      [player('a', { captives: 3 }), player('b', { captives: 1 }), player('c', { captives: 1 })],
      [{ ambition: 'tyrant', first: 5, second: 3 }, { ambition: 'empath', first: 3, second: 1 }],
    );
    expect(result.players.map((p) => p.power)).toEqual([5, 0, 0]);
  });
  it('uses covered two-player resources as a third scoring player', () => {
    const result = scoreAmbitions(
      [player('a', { resources: ['relic'] }), player('b', { resources: [] })],
      [{ ambition: 'keeper', first: 5, second: 3 }],
      phantomScorer(['relic', 'relic']),
    );
    expect(result.players.map((p) => p.power)).toEqual([3, 0]);
  });
  it('ends after chapter five and breaks tied Power in initiative order', () => {
    expect(gameWinner([player('a', { power: 12 }), player('b', { power: 12 })], ['b', 'a'], 5)).toBe('b');
    expect(gameWinner([player('a', { power: 12 }), player('b', { power: 12 })], ['b', 'a'], 4)).toBeNull();
  });
});
