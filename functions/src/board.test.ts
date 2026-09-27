import { describe, expect, it } from 'vitest';
import { createBoard, isAdjacent } from './board';

describe('base map', () => {
  it('rejects invalid active-cluster sets', () => {
    expect(() => createBoard([1, 2, 3])).toThrow();
    expect(() => createBoard([1, 2, 2, 4])).toThrow();
    expect(() => createBoard([1, 2, 3, 7])).toThrow();
  });

  it('keeps out-of-play systems inaccessible and connects adjacent surviving gates', () => {
    const board = createBoard([1, 3, 5, 6]);
    expect(Object.keys(board.planets)).toHaveLength(12);
    expect(Object.keys(board.adjacency)).toHaveLength(16);
    expect(board.adjacency['2:gate']).toBeUndefined();
    expect(isAdjacent(board, '1:gate', '3:gate')).toBe(true);
    expect(isAdjacent(board, '3:gate', '5:gate')).toBe(true);
    expect(isAdjacent(board, '1:gate', '5:gate')).toBe(false);
  });

  it('makes every route bidirectional while respecting thick borders', () => {
    const board = createBoard([2, 3, 4, 5, 6]);
    for (const [from, destinations] of Object.entries(board.adjacency)) {
      for (const to of destinations) expect(isAdjacent(board, to, from)).toBe(true);
    }
    expect(isAdjacent(board, '2:hex', '3:arrow')).toBe(true);
    expect(isAdjacent(board, '5:hex', '6:arrow')).toBe(true);
    expect(isAdjacent(board, '2:arrow', '2:hex')).toBe(false);
    expect(isAdjacent(board, '2:crescent', '2:hex')).toBe(true);
  });

  it('pins planet resources and building slots to named systems', () => {
    const board = createBoard([1, 2, 3, 4, 5]);
    expect(board.planets['1:arrow']).toMatchObject({ resource: 'weapon', slots: 2 });
    expect(board.planets['2:hex']).toMatchObject({ resource: 'relic', slots: 2 });
    expect(board.planets['4:crescent']).toMatchObject({ resource: 'fuel', slots: 2 });
    expect(board.planets['5:hex']).toMatchObject({ resource: 'psionic', slots: 2 });
  });
});
