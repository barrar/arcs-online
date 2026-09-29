import { describe, expect, it } from 'vitest';
import { actionCard } from './action_cards';
import { applyGameCommand } from './game_commands';
import { createGameWithSetup } from './game_state';
import type { VoxChoice } from './game_vox';
import type { Lobby } from './lobby';
import { setupChoices } from './setup';

// Official card effects: https://cards.buriedgiant.com/ (ARCS-BC26–31).
function readyToSecure(cardId: string) {
  const seats = ['a', 'b'].map((uid, index) => ({
    uid, name: uid, color: index ? 'azure' : 'ember', ready: true,
  }));
  const lobby: Lobby = {
    id: '00000000-0000-4000-8000-000000000001', name: 'Vox integration',
    code: 'ABCDEFGH', visibility: 'private', status: 'waiting', maxPlayers: 2,
    hostId: 'a', seats, memberIds: ['a', 'b'], timer: { mode: 'async', hours: 24 },
    createdAt: 0, updatedAt: 0,
  };
  const state = createGameWithSetup(lobby, setupChoices(2)[0], 'a', 1000, () => 0);
  state.mulliganPendingUid = null;
  const card = actionCard('aggression', 2);
  state.round.lead = { uid: 'a', card, mode: 'lead' };
  state.round.plays = [state.round.lead];
  state.round.playedThisTurn = true;
  state.round.remainingPips = 1;
  state.courtRow[0] = { cardId, agents: { a: 1 } };
  return state;
}

describe('Vox effects through the authoritative command flow', () => {
  it.each(['ARCS-BC26', 'ARCS-BC27', 'ARCS-BC28', 'ARCS-BC29', 'ARCS-BC30', 'ARCS-BC31'])(
    '%s replaces its Court slot, blocks other commands, and resolves its effect', (cardId) => {
      const initial = readyToSecure(cardId);
      if (cardId === 'ARCS-BC30') {
        initial.players.b.guilds.push('ARCS-BC02');
        initial.courtDiscard.push('ARCS-BC04');
      }
      if (cardId === 'ARCS-BC31') {
        initial.actionDiscard = [actionCard('administration', 2), actionCard('construction', 3)];
      }
      const nextCourt = initial.courtDeck[0];
      const secured = applyGameCommand(initial, 'a', `secure-${cardId}`,
        { kind: 'pip', action: { kind: 'secure', courtIndex: 0 } }, 1001).state;
      expect(secured.courtRow[0].cardId).toBe(nextCourt);
      expect(secured.pendingVox).toEqual([cardId]);
      expect(secured.courtDiscard).toContain(cardId);
      expect(() => applyGameCommand(secured, 'a', `blocked-${cardId}`, { kind: 'end-turn' }, 1002))
        .toThrow('Resolve the secured Vox');
      const choice: VoxChoice = (() => {
        switch (cardId) {
          case 'ARCS-BC26': return { kind: 'mass-uprising', cluster: secured.activeClusters[0] };
          case 'ARCS-BC27': return { kind: 'populist-demands', ambition: 'tycoon' };
          case 'ARCS-BC28': return { kind: 'outrage-spreads', resource: 'psionic' };
          case 'ARCS-BC29': {
            const id = setupChoices(2)[0].starting[0].a;
            const city = secured.systems[id].find((piece) => piece.owner === 'a' && piece.kind === 'city')!;
            return { kind: 'song-of-freedom', cityId: city.id };
          }
          case 'ARCS-BC30': return { kind: 'guild-struggle', rivalUid: 'b', cardId: 'ARCS-BC02' };
          default: return { kind: 'call-to-action' };
        }
      })();
      const resolved = applyGameCommand(secured, 'a', `vox-${cardId}`,
        { kind: 'vox', choice }, 1002, () => 0).state;
      expect(resolved.pendingVox).toHaveLength(0);
      switch (cardId) {
        case 'ARCS-BC26':
          expect(Object.entries(resolved.systems).filter(([id, pieces]) =>
            id.startsWith(`${resolved.activeClusters[0]}:`) && pieces.some((piece) =>
              piece.owner === 'a' && piece.kind === 'ship'))).toHaveLength(4);
          break;
        case 'ARCS-BC27': expect(resolved.markers.at(-1)?.ambition).toBe('tycoon'); break;
        case 'ARCS-BC28': expect(resolved.order.every((uid) =>
          resolved.players[uid].outrage.includes('psionic'))).toBe(true); break;
        case 'ARCS-BC29': expect(resolved.courtDeck).toContain(cardId); break;
        case 'ARCS-BC30':
          expect(resolved.players.a.guilds).toContain('ARCS-BC02');
          expect(resolved.courtDeck).toContain('ARCS-BC04');
          break;
        case 'ARCS-BC31':
          expect(resolved.round.hands.a.at(-1)?.id).toBe('administration-2');
          break;
      }
    });
});
