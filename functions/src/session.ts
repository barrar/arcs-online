export type VoteState = { targetUid: string; approvals: string[]; deadlineMs: number };
export type ActiveSession = {
  memberIds: string[];
  actorUid: string;
  deadlineMs: number;
  status: 'playing' | 'terminated' | 'finished';
  vote?: VoteState;
  termination?: { reason: 'kick'; targetUid: string; at: number };
};

export function castKickVote(session: ActiveSession, voterUid: string, targetUid: string, now: number): ActiveSession {
  if (session.status !== 'playing') throw new Error('This match is not active.');
  if (!session.memberIds.includes(voterUid)) throw new Error('Only seated players may vote.');
  if (targetUid !== session.actorUid || now < session.deadlineMs) throw new Error('The current player is not overdue.');
  if (voterUid === targetUid) throw new Error('Players cannot vote to kick themselves.');
  const vote = session.vote?.targetUid === targetUid && session.vote.deadlineMs === session.deadlineMs
    ? session.vote : { targetUid, approvals: [], deadlineMs: session.deadlineMs };
  const approvals = [...new Set([...vote.approvals, voterUid])];
  const otherPlayers = session.memberIds.filter((uid) => uid !== targetUid);
  if (otherPlayers.every((uid) => approvals.includes(uid))) {
    return { ...session, status: 'terminated', vote: { ...vote, approvals }, termination: { reason: 'kick', targetUid, at: now } };
  }
  return { ...session, vote: { ...vote, approvals } };
}

export function advanceActor(session: ActiveSession, actorUid: string, now: number, durationMs: number): ActiveSession {
  if (!session.memberIds.includes(actorUid)) throw new Error('Next actor must be seated.');
  return { ...session, actorUid, deadlineMs: now + durationMs, vote: undefined };
}
