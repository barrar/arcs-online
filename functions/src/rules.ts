// Pure base-game rules. Source: ARCS Base Rulebook (August 27, 2025), pp. 6, 18–19.
export type Resource = 'material' | 'fuel' | 'weapon' | 'relic' | 'psionic';
export type Ambition = 'tycoon' | 'tyrant' | 'warlord' | 'keeper' | 'empath';
export type Piece = { owner: string; kind: 'ship' | 'city' | 'starport'; damaged: boolean };
export type System = { id: string; pieces: Piece[] };

export function controller(system: System): string | null {
  const counts = new Map<string, number>();
  for (const piece of system.pieces) {
    if (piece.kind !== 'ship' || piece.damaged) continue;
    counts.set(piece.owner, (counts.get(piece.owner) ?? 0) + 1);
  }
  const ordered = [...counts].sort((a, b) => b[1] - a[1]);
  return ordered.length > 0 && (ordered.length === 1 || ordered[0][1] > ordered[1][1]) ? ordered[0][0] : null;
}

export type ScoringPlayer = {
  uid: string;
  power: number;
  resources: Resource[];
  guildIcons: Resource[];
  trophies: number;
  captives: number;
  citiesBuilt: number;
};
export type AmbitionMarker = { ambition: Ambition; first: number; second: number };
export type ScoreResult = { players: ScoringPlayer[]; winners: string[]; details: Record<Ambition, { first: string[]; second: string[] }> };

export function ambitionStrength(player: ScoringPlayer, ambition: Ambition): number {
  const icons = [...player.resources, ...player.guildIcons];
  switch (ambition) {
    case 'tycoon': return icons.filter((icon) => icon === 'material' || icon === 'fuel').length;
    case 'tyrant': return player.captives;
    case 'warlord': return player.trophies;
    case 'keeper': return icons.filter((icon) => icon === 'relic').length;
    case 'empath': return icons.filter((icon) => icon === 'psionic').length;
  }
}

// The two-player setup places the resources from the covered planets on the
// ambition boxes. They score as a third player; Weapons count as Trophies.
export function phantomScorer(resources: Resource[]): ScoringPlayer {
  return { uid: '__phantom__', power: 0, resources, guildIcons: [], trophies: resources.filter((r) => r === 'weapon').length, captives: 0, citiesBuilt: 0 };
}

export function scoreAmbitions(players: ScoringPlayer[], markers: AmbitionMarker[], phantom?: ScoringPlayer): ScoreResult {
  const next = players.map((player) => ({ ...player }));
  const details = Object.fromEntries((['tycoon', 'tyrant', 'warlord', 'keeper', 'empath'] as Ambition[])
    .map((name) => [name, { first: [] as string[], second: [] as string[] }])) as ScoreResult['details'];
  const all = phantom ? [...next, phantom] : next;
  for (const ambition of new Set(markers.map((marker) => marker.ambition))) {
    const ranked = all.map((player) => ({ uid: player.uid, strength: ambitionStrength(player, ambition) }))
      .filter((item) => item.strength > 0).sort((a, b) => b.strength - a.strength);
    if (ranked.length === 0) continue;
    const highest = ranked[0].strength;
    const tiedFirst = ranked.filter((item) => item.strength === highest).map((item) => item.uid);
    const first = tiedFirst.length === 1 ? tiedFirst : [];
    // On a tie for first, the tied players take second place and nobody else scores.
    // On a tie for second, nobody takes second place.
    const second = tiedFirst.length > 1 ? tiedFirst
      : (() => {
          const runner = ranked.find((item) => item.strength < highest);
          if (!runner) return [];
          const tied = ranked.filter((item) => item.strength === runner.strength);
          return tied.length === 1 ? [runner.uid] : [];
        })();
    details[ambition] = { first, second };
    const firstPower = markers.filter((marker) => marker.ambition === ambition).reduce((sum, marker) => sum + marker.first, 0);
    const secondPower = markers.filter((marker) => marker.ambition === ambition).reduce((sum, marker) => sum + marker.second, 0);
    for (const player of next) {
      if (first.includes(player.uid)) {
        player.power += firstPower + (player.citiesBuilt >= 5 ? 5 : player.citiesBuilt >= 4 ? 2 : 0);
      } else if (second.includes(player.uid)) {
        player.power += secondPower;
      }
    }
  }
  return { players: next, winners: [], details };
}

export function gameWinner(players: ScoringPlayer[], initiativeOrder: string[], chapter: number): string | null {
  const threshold = players.length === 4 ? 27 : players.length === 3 ? 30 : 33;
  if (chapter < 5 && players.every((player) => player.power < threshold)) return null;
  const order = new Map(initiativeOrder.map((uid, index) => [uid, index]));
  return [...players].sort((a, b) => b.power - a.power || (order.get(a.uid)! - order.get(b.uid)!))[0].uid;
}
