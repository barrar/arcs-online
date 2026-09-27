// Base map topology and planet data. Adjacency follows Arcs Base Rulebook
// (2025-08-27), p. 6. Planet resources and building-slot counts were
// cross-checked against haunt-roll-fail's MIT-licensed base map table at
// commit d157b02; see THIRD_PARTY_NOTICES.md.

export type Resource = 'material' | 'fuel' | 'weapon' | 'relic' | 'psionic';
export type Glyph = 'arrow' | 'crescent' | 'hex';
export type SystemId = `${number}:${Glyph | 'gate'}`;
export type Planet = { id: SystemId; cluster: number; glyph: Glyph; resource: Resource; slots: number };
export type Board = {
  activeClusters: number[];
  planets: Record<SystemId, Planet>;
  adjacency: Record<SystemId, SystemId[]>;
};

const planetData: Record<number, Record<Glyph, readonly [Resource, number]>> = {
  1: { arrow: ['weapon', 2], crescent: ['fuel', 1], hex: ['material', 2] },
  2: { arrow: ['psionic', 1], crescent: ['weapon', 1], hex: ['relic', 2] },
  3: { arrow: ['material', 1], crescent: ['fuel', 1], hex: ['weapon', 2] },
  4: { arrow: ['relic', 2], crescent: ['fuel', 2], hex: ['material', 1] },
  5: { arrow: ['weapon', 1], crescent: ['relic', 1], hex: ['psionic', 2] },
  6: { arrow: ['material', 1], crescent: ['fuel', 2], hex: ['psionic', 1] },
};

const glyphs: Glyph[] = ['arrow', 'crescent', 'hex'];
const system = (cluster: number, glyph: Glyph | 'gate'): SystemId => `${cluster}:${glyph}`;

export function createBoard(activeClusters: number[]): Board {
  const clusters = [...activeClusters].sort((a, b) => a - b);
  if (
    ![4, 5].includes(clusters.length) ||
    new Set(clusters).size !== clusters.length ||
    clusters.some((cluster) => !Number.isInteger(cluster) || cluster < 1 || cluster > 6)
  ) throw new Error('A base map has four or five distinct active clusters numbered 1–6.');

  const planets = {} as Record<SystemId, Planet>;
  const neighbors = new Map<SystemId, Set<SystemId>>();
  const connect = (a: SystemId, b: SystemId) => {
    neighbors.get(a)!.add(b);
    neighbors.get(b)!.add(a);
  };

  for (const cluster of clusters) {
    const gate = system(cluster, 'gate');
    neighbors.set(gate, new Set());
    for (const glyph of glyphs) {
      const id = system(cluster, glyph);
      const [resource, slots] = planetData[cluster][glyph];
      planets[id] = { id, cluster, glyph, resource, slots };
      neighbors.set(id, new Set());
      connect(gate, id);
    }
    connect(system(cluster, 'arrow'), system(cluster, 'crescent'));
    connect(system(cluster, 'crescent'), system(cluster, 'hex'));
  }

  // A path marker joins the gates on either side of every removed cluster.
  for (let i = 0; i < clusters.length; i++) {
    connect(system(clusters[i], 'gate'), system(clusters[(i + 1) % clusters.length], 'gate'));
  }

  // Two thin borders cross between planets in neighboring clusters.
  if (clusters.includes(2) && clusters.includes(3)) connect(system(2, 'hex'), system(3, 'arrow'));
  if (clusters.includes(5) && clusters.includes(6)) connect(system(5, 'hex'), system(6, 'arrow'));

  const adjacency = {} as Record<SystemId, SystemId[]>;
  for (const [id, connected] of neighbors) adjacency[id] = [...connected].sort();
  return { activeClusters: clusters, planets, adjacency };
}

export function isAdjacent(board: Board, from: SystemId, to: SystemId): boolean {
  return board.adjacency[from]?.includes(to) ?? false;
}
