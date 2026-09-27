import { describe, expect, it } from 'vitest';
import { boardForSetup, setupChoices, setupVariants } from './setup';

describe('base setup cards', () => {
  it('offers four distinct diagrams at each official player count', () => {
    expect(new Set(setupVariants.map((setup) => setup.id)).size).toBe(12);
    for (const count of [2, 3, 4]) {
      const choices = setupChoices(count);
      expect(choices).toHaveLength(4);
      for (const choice of choices) {
        expect(choice.activeClusters).toHaveLength(count === 4 ? 5 : 4);
        const board = boardForSetup(choice.id);
        expect(board.activeClusters).toEqual(choice.activeClusters);
        expect(Object.keys(board.planets)).toHaveLength(choice.activeClusters.length * 3);
      }
    }
  });

  it('keeps the two-player variants separate even when they share active clusters', () => {
    const homelands = setupChoices(2).find((setup) => setup.name === 'Homelands')!;
    const mixUp2 = setupChoices(2).find((setup) => setup.name === 'Mix Up 2')!;
    expect(homelands.id).not.toBe(mixUp2.id);
    expect(homelands.activeClusters).toEqual(mixUp2.activeClusters);
  });

  it('rejects invalid player counts and setup IDs', () => {
    expect(() => setupChoices(1)).toThrow();
    expect(() => setupChoices(5)).toThrow();
    expect(() => boardForSetup('campaign')).toThrow();
  });
});
