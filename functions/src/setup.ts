// The official base rulebook (2025-08-27), pp. 3–5, has four setup cards per
// player count. These layout names and out-of-play clusters were read from the
// 12 printed setup diagrams embedded in the user-provided offline reference.
// Starting-piece labels must be encoded separately before starting a match.
import { createBoard, type Board } from './board';

export type SetupVariant = {
  id: string;
  name: string;
  playerCount: 2 | 3 | 4;
  activeClusters: number[];
};

export const setupVariants: readonly SetupVariant[] = [
  { id: '2p-frontiers', name: 'Frontiers', playerCount: 2, activeClusters: [2, 3, 4, 5] },
  { id: '2p-mix-up-1', name: 'Mix Up 1', playerCount: 2, activeClusters: [1, 3, 4, 6] },
  { id: '2p-homelands', name: 'Homelands', playerCount: 2, activeClusters: [2, 3, 5, 6] },
  { id: '2p-mix-up-2', name: 'Mix Up 2', playerCount: 2, activeClusters: [2, 3, 5, 6] },
  { id: '3p-mix-up', name: 'Mix Up', playerCount: 3, activeClusters: [2, 3, 5, 6] },
  { id: '3p-frontiers', name: 'Frontiers', playerCount: 3, activeClusters: [1, 4, 5, 6] },
  { id: '3p-homelands', name: 'Homelands', playerCount: 3, activeClusters: [1, 2, 3, 4] },
  { id: '3p-core-conflict', name: 'Core Conflict', playerCount: 3, activeClusters: [1, 2, 4, 5] },
  { id: '4p-mix-up-1', name: 'Mix Up 1', playerCount: 4, activeClusters: [1, 2, 4, 5, 6] },
  { id: '4p-mix-up-2', name: 'Mix Up 2', playerCount: 4, activeClusters: [1, 2, 3, 5, 6] },
  { id: '4p-frontiers', name: 'Frontiers', playerCount: 4, activeClusters: [1, 2, 3, 4, 6] },
  { id: '4p-mix-up-3', name: 'Mix Up 3', playerCount: 4, activeClusters: [1, 2, 3, 4, 5] },
];

export function setupChoices(playerCount: number): SetupVariant[] {
  if (!Number.isInteger(playerCount) || playerCount < 2 || playerCount > 4) {
    throw new Error('ARCS requires two to four players.');
  }
  return setupVariants.filter((setup) => setup.playerCount === playerCount);
}

export function boardForSetup(id: string): Board {
  const setup = setupVariants.find((candidate) => candidate.id === id);
  if (!setup) throw new Error('Unknown base setup.');
  return createBoard(setup.activeClusters);
}
