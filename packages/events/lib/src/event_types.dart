abstract final class EventTypes {
  static const sourceRegistered = 'source.registered';
  static const observationRecorded = 'observation.recorded';
  static const baselineCreated = 'baseline.created';
  static const opportunityIdentified = 'opportunity.identified';
  static const recommendationCreated = 'recommendation.created';
  static const executionRecorded = 'execution.recorded';
  static const outcomeRecorded = 'outcome.recorded';
  static const constraintRecorded = 'constraint.recorded';

  static const personalAssetRecorded = 'personal_asset.recorded';
  static const personalAssetSuperseded = 'personal_asset.superseded';
  static const personalAssetArchived = 'personal_asset.archived';

  static const strategyProposed = 'strategy.proposed';
  static const strategyAccepted = 'strategy.accepted';
  static const strategyActivated = 'strategy.activated';
  static const strategyCompleted = 'strategy.completed';
  static const strategyAbandoned = 'strategy.abandoned';

  static const agentSessionOpened = 'agent_session.opened';
  static const agentSessionProposalSubmitted =
      'agent_session.proposal_submitted';
  static const agentSessionClosed = 'agent_session.closed';
  static const agentSessionFailed = 'agent_session.failed';

  static const claimProposed = 'claim.proposed';
  static const claimConfirmed = 'claim.confirmed';
  static const claimDisputed = 'claim.disputed';
  static const claimExpired = 'claim.expired';
  static const claimWithdrawn = 'claim.withdrawn';

  static const goalCreated = 'goal.created';
  static const goalActivated = 'goal.activated';
  static const goalPaused = 'goal.paused';
  static const goalCompleted = 'goal.completed';

  static const planDrafted = 'plan.drafted';
  static const planApproved = 'plan.approved';
  static const planActivated = 'plan.activated';
  static const planPaused = 'plan.paused';
  static const planCompleted = 'plan.completed';
  static const planStopped = 'plan.stopped';

  static const taskPlanned = 'task.planned';
  static const taskReady = 'task.ready';
  static const taskInProgress = 'task.in_progress';
  static const taskCompleted = 'task.completed';
  static const taskSkipped = 'task.skipped';
  static const taskFailed = 'task.failed';
  static const taskStopped = 'task.stopped';

  static const consentRequested = 'consent.requested';
  static const consentGranted = 'consent.granted';
  static const consentRevoked = 'consent.revoked';
  static const consentExpired = 'consent.expired';

  static const reviewCreated = 'review.created';
  static const reviewUserReviewed = 'review.user_reviewed';
  static const reviewAccepted = 'review.accepted';
  static const reviewRejected = 'review.rejected';

  static const modelRevisionProposed = 'model.revision.proposed';
  static const modelRevisionAccepted = 'model.revision.accepted';

  static const deletionRequested = 'deletion.requested';
  static const deletionCompleted = 'deletion.completed';

  static const conflictDetected = 'conflict.detected';
  static const conflictResolutionProposed = 'conflict.resolution.proposed';
  static const conflictResolved = 'conflict.resolved';
  static const conflictDismissed = 'conflict.dismissed';
}
