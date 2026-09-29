import { z } from 'zod';

const uid = z.string().min(1).max(128);
const systemId = z.string().regex(/^[1-6]:(arrow|crescent|hex|gate)$/);
const resource = z.enum(['material', 'fuel', 'weapon', 'relic', 'psionic']);
const ambition = z.enum(['tycoon', 'tyrant', 'warlord', 'keeper', 'empath']);
const actionCardId = z.string().regex(/^(administration|aggression|construction|mobilization)-[1-7]$/);
const courtCardId = z.string().regex(/^ARCS-BC(0[1-9]|[12][0-9]|3[01])$/);
const slot = z.number().int().min(0).max(5);
const courtIndex = z.number().int().min(0).max(3);

const tax = z.object({ kind: z.literal('tax'), cityId: z.string().min(1), slot: slot.optional() });
const build = z.object({ kind: z.literal('build'), piece: z.enum(['city', 'starport', 'ship']),
  systemId, starportId: z.string().optional() });
const move = z.object({ kind: z.literal('move'), from: systemId,
  shipIds: z.array(z.string().min(1)).min(1).max(15),
  route: z.array(z.object({ to: systemId, dropShipIds: z.array(z.string().min(1)).max(15) })).min(1).max(12) });
const repair = z.object({ kind: z.literal('repair'), pieceId: z.string().min(1) });
const influence = z.object({ kind: z.literal('influence'), courtIndex });
const secure = z.object({ kind: z.literal('secure'), courtIndex });
const battle = z.object({ kind: z.literal('battle'), systemId, defenderUid: uid,
  dice: z.object({ assault: z.number().int().min(0).max(6), skirmish: z.number().int().min(0).max(6),
    raid: z.number().int().min(0).max(6) }) });
const manufacture = z.object({ kind: z.literal('manufacture'), slot: slot.optional() });
const synthesize = z.object({ kind: z.literal('synthesize'), slot: slot.optional() });
const pressgang = z.object({ kind: z.literal('pressgang'), captiveOwners: z.array(uid).max(10),
  gains: z.array(z.object({ resource, slot: slot.optional() })).max(10) });
const execute = z.object({ kind: z.literal('execute'), captiveOwners: z.array(uid).max(10) });
const abduct = z.object({ kind: z.literal('abduct'), courtIndex });
const trade = z.object({ kind: z.literal('trade'), cityId: z.string().min(1), giveSlot: slot,
  takeSlot: slot, destinationSlot: slot.optional() });
export const playableActionSchema = z.discriminatedUnion('kind', [tax, build, move, repair, influence,
  secure, battle, manufacture, synthesize, pressgang, execute, abduct, trade]);

const stealChoice = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('resource'), rivalUid: uid, rivalSlot: slot, destinationSlot: slot.optional() }),
  z.object({ kind: z.literal('guild'), rivalUid: uid, cardId: courtCardId }),
]);
const guildPrelude = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('interest'), cardId: z.enum(['ARCS-BC02', 'ARCS-BC09']),
    placements: z.array(z.object({ slot, stealFrom: z.object({ uid, slot }).optional() })).max(6) }),
  z.object({ kind: z.literal('cartel'), cardId: z.enum(['ARCS-BC03', 'ARCS-BC06']), steal: stealChoice.optional() }),
  z.object({ kind: z.literal('union'), cardId: z.enum(['ARCS-BC04', 'ARCS-BC05', 'ARCS-BC10', 'ARCS-BC11']),
    actionCardId }),
  z.object({ kind: z.literal('gatekeepers'), gateIds: z.array(systemId).max(5).optional() }),
  z.object({ kind: z.literal('place-ships'), cardId: z.enum(['ARCS-BC12', 'ARCS-BC13', 'ARCS-BC14', 'ARCS-BC15']), systemId }),
  z.object({ kind: z.literal('lattice-spies') }),
  z.object({ kind: z.literal('farseers'), discardActionCardIds: z.array(actionCardId).max(6) }),
  z.object({ kind: z.literal('silver-tongues'), steal: stealChoice.optional() }),
  z.object({ kind: z.literal('elder-broker'), slots: z.array(slot.nullable()).length(3) }),
  z.object({ kind: z.literal('relic-fence'), discardSlot: slot, destinationSlot: slot.optional() }),
]);

const voxChoice = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('mass-uprising'), cluster: z.number().int().min(1).max(6),
    systemIds: z.array(systemId).max(4).optional() }),
  z.object({ kind: z.literal('populist-demands'), ambition: ambition.optional() }),
  z.object({ kind: z.literal('outrage-spreads'), resource: resource.optional() }),
  z.object({ kind: z.literal('song-of-freedom'), cityId: z.string().optional(), seize: z.boolean().optional() }),
  z.object({ kind: z.literal('guild-struggle'), rivalUid: uid.optional(), cardId: courtCardId.optional() }),
  z.object({ kind: z.literal('call-to-action') }),
]);

export const gameCommandSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('mulligan'), replace: z.boolean() }),
  z.object({ kind: z.literal('play'), cardId: actionCardId, mode: z.enum(['lead', 'surpass', 'copy', 'pivot']),
    declare: ambition.optional(), extraCardId: actionCardId.optional(), bardDeclare: ambition.optional() }),
  z.object({ kind: z.literal('pass') }),
  z.object({ kind: z.literal('pip'), action: playableActionSchema }),
  z.object({ kind: z.literal('resource'), slot, as: resource, action: playableActionSchema.optional() }),
  z.object({ kind: z.literal('guild-prelude'), effect: guildPrelude }),
  z.object({ kind: z.literal('farseers-target'), targetUid: uid }),
  z.object({ kind: z.literal('farseers-swap'), myCardId: actionCardId.optional(), rivalCardId: actionCardId.optional() }),
  z.object({ kind: z.literal('choose-resources'), slots: z.array(resource.nullable()).min(2).max(6) }),
  z.object({ kind: z.literal('rearrange-resources'), slots: z.array(resource.nullable()).min(2).max(6) }),
  z.object({ kind: z.literal('recover'), gateId: systemId }),
  z.object({ kind: z.literal('end-turn') }),
  z.object({ kind: z.literal('reroll-skirmish'), faceIndexes: z.array(z.number().int().min(0).max(17)).min(1).max(6) }),
  z.object({ kind: z.literal('assign-hits'), assignment: z.object({ own: z.array(z.string()),
    ships: z.array(z.string()), buildings: z.array(z.string()),
    ransackCourtIndexes: z.array(courtIndex).optional() }) }),
  z.object({ kind: z.literal('raid'), target: z.discriminatedUnion('kind', [
    z.object({ kind: z.literal('resource'), slot, destinationSlot: slot.optional() }),
    z.object({ kind: z.literal('guild'), cardId: courtCardId }),
  ]) }),
  z.object({ kind: z.literal('finish-raid') }),
  z.object({ kind: z.literal('vox'), choice: voxChoice }),
  z.object({ kind: z.literal('vote-kick'), targetUid: uid }),
  z.object({ kind: z.literal('concede') }),
]);

export const submitGameCommandSchema = z.object({ gameId: z.string().uuid(), commandId: z.string().uuid(),
  command: gameCommandSchema });
