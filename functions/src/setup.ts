// Base Rulebook (2025-08-27), pp. 4–5. The labels were transcribed from all
// twelve printed setup diagrams in the user's offline reference. A and B are
// planets; each C system gets two ships (two C systems in a two-player game).
import { createBoard, type Board, type SystemId } from './board';

export type StartingPosition = {
  a: SystemId;
  b: SystemId;
  c: readonly SystemId[];
};

export type SetupVariant = {
  id: string;
  name: string;
  playerCount: 2 | 3 | 4;
  activeClusters: number[];
  starting: readonly StartingPosition[];
};

export const setupVariants: readonly SetupVariant[] = [
  { id: '2p-frontiers', name: 'Frontiers', playerCount: 2, activeClusters: [2, 3, 4, 5], starting: [
    { a: '5:hex', b: '4:hex', c: ['3:gate', '3:hex'] },
    { a: '3:arrow', b: '5:arrow', c: ['5:gate', '4:arrow'] },
  ] },
  { id: '2p-mix-up-1', name: 'Mix Up 1', playerCount: 2, activeClusters: [1, 3, 4, 6], starting: [
    { a: '4:crescent', b: '3:crescent', c: ['6:arrow', '1:gate'] },
    { a: '6:hex', b: '3:hex', c: ['1:crescent', '4:gate'] },
  ] },
  { id: '2p-homelands', name: 'Homelands', playerCount: 2, activeClusters: [2, 3, 5, 6], starting: [
    { a: '5:arrow', b: '6:arrow', c: ['5:hex', '5:gate'] },
    { a: '3:hex', b: '3:arrow', c: ['2:arrow', '3:gate'] },
  ] },
  { id: '2p-mix-up-2', name: 'Mix Up 2', playerCount: 2, activeClusters: [2, 3, 5, 6], starting: [
    { a: '5:arrow', b: '2:arrow', c: ['6:hex', '3:gate'] },
    { a: '2:crescent', b: '6:arrow', c: ['5:gate', '3:hex'] },
  ] },
  { id: '3p-mix-up', name: 'Mix Up', playerCount: 3, activeClusters: [2, 3, 5, 6], starting: [
    { a: '3:hex', b: '5:crescent', c: ['2:gate'] },
    { a: '2:arrow', b: '5:hex', c: ['3:gate'] },
    { a: '2:hex', b: '3:arrow', c: ['5:gate'] },
  ] },
  { id: '3p-frontiers', name: 'Frontiers', playerCount: 3, activeClusters: [1, 4, 5, 6], starting: [
    { a: '1:hex', b: '4:hex', c: ['6:gate'] },
    { a: '5:hex', b: '1:crescent', c: ['5:gate'] },
    { a: '4:crescent', b: '6:arrow', c: ['1:gate'] },
  ] },
  { id: '3p-homelands', name: 'Homelands', playerCount: 3, activeClusters: [1, 2, 3, 4], starting: [
    { a: '2:hex', b: '3:crescent', c: ['3:gate'] },
    { a: '1:hex', b: '2:arrow', c: ['2:gate'] },
    { a: '1:arrow', b: '4:hex', c: ['4:gate'] },
  ] },
  { id: '3p-core-conflict', name: 'Core Conflict', playerCount: 3, activeClusters: [1, 2, 4, 5], starting: [
    { a: '1:hex', b: '2:crescent', c: ['1:gate'] },
    { a: '2:hex', b: '1:crescent', c: ['2:gate'] },
    { a: '1:arrow', b: '2:arrow', c: ['4:gate'] },
  ] },
  { id: '4p-mix-up-1', name: 'Mix Up 1', playerCount: 4, activeClusters: [1, 2, 4, 5, 6], starting: [
    { a: '4:arrow', b: '6:hex', c: ['1:gate'] },
    { a: '4:hex', b: '5:hex', c: ['6:gate'] },
    { a: '5:arrow', b: '1:hex', c: ['4:gate'] },
    { a: '6:arrow', b: '1:arrow', c: ['5:gate'] },
  ] },
  { id: '4p-mix-up-2', name: 'Mix Up 2', playerCount: 4, activeClusters: [1, 2, 3, 5, 6], starting: [
    { a: '5:hex', b: '3:arrow', c: ['2:gate'] },
    { a: '3:hex', b: '5:crescent', c: ['1:gate'] },
    { a: '2:hex', b: '1:hex', c: ['3:gate'] },
    { a: '1:arrow', b: '2:arrow', c: ['5:gate'] },
  ] },
  { id: '4p-frontiers', name: 'Frontiers', playerCount: 4, activeClusters: [1, 2, 3, 4, 6], starting: [
    { a: '1:hex', b: '3:crescent', c: ['2:gate'] },
    { a: '2:hex', b: '6:hex', c: ['3:gate'] },
    { a: '4:crescent', b: '2:arrow', c: ['6:gate'] },
    { a: '1:arrow', b: '6:arrow', c: ['4:gate'] },
  ] },
  { id: '4p-mix-up-3', name: 'Mix Up 3', playerCount: 4, activeClusters: [1, 2, 3, 4, 5], starting: [
    { a: '3:hex', b: '5:crescent', c: ['1:gate'] },
    { a: '1:arrow', b: '3:arrow', c: ['2:gate'] },
    { a: '1:hex', b: '4:hex', c: ['3:gate'] },
    { a: '4:arrow', b: '2:crescent', c: ['5:gate'] },
  ] },
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
