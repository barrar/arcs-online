import type { Resource } from './board';

// Base Court, 25 Guilds and 6 Vox. Names, suits and printed raid costs are
// cross-checked with the official card library and the physical card faces.
export type CourtCard = { id: string; name: string; kind: 'guild' | 'vox'; suit?: Resource; raidCost?: number };

const guild = (number: number, name: string, suit: Resource, raidCost: number): CourtCard => ({
  id: `ARCS-BC${String(number).padStart(2, '0')}`, name, kind: 'guild', suit, raidCost,
});
const vox = (number: number, name: string): CourtCard => ({
  id: `ARCS-BC${number}`, name, kind: 'vox',
});

export const baseCourt: readonly CourtCard[] = [
  guild(1, 'Loyal Engineers', 'material', 3),
  guild(2, 'Mining Interest', 'material', 2),
  guild(3, 'Material Cartel', 'material', 2),
  guild(4, 'Admin Union', 'material', 2),
  guild(5, 'Construction Union', 'material', 2),
  guild(6, 'Fuel Cartel', 'fuel', 2),
  guild(7, 'Loyal Pilots', 'fuel', 3),
  guild(8, 'Gatekeepers', 'fuel', 2),
  guild(9, 'Shipping Interest', 'fuel', 2),
  guild(10, 'Spacing Union', 'fuel', 2),
  guild(11, 'Arms Union', 'weapon', 2),
  guild(12, 'Prison Wardens', 'weapon', 2),
  guild(13, 'Skirmishers', 'weapon', 2),
  guild(14, 'Court Enforcers', 'weapon', 2),
  guild(15, 'Loyal Marines', 'weapon', 3),
  guild(16, 'Lattice Spies', 'psionic', 2),
  guild(17, 'Farseers', 'psionic', 2),
  guild(18, 'Secret Order', 'psionic', 2),
  guild(19, 'Loyal Empaths', 'psionic', 3),
  guild(20, 'Silver-Tongues', 'psionic', 2),
  guild(21, 'Loyal Keepers', 'relic', 3),
  guild(22, 'Sworn Guardians', 'relic', 1),
  guild(23, 'Elder Broker', 'relic', 2),
  guild(24, 'Relic Fence', 'relic', 2),
  guild(25, 'Galactic Bards', 'relic', 1),
  vox(26, 'Mass Uprising'),
  vox(27, 'Populist Demands'),
  vox(28, 'Outrage Spreads'),
  vox(29, 'Song of Freedom'),
  vox(30, 'Guild Struggle'),
  vox(31, 'Call to Action'),
];

export const cardById: Readonly<Record<string, CourtCard>> = Object.fromEntries(baseCourt.map((card) => [card.id, card]));
