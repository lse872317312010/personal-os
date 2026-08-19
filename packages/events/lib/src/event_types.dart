abstract final class EventTypes {
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
  static const taskCompleted = 'task.completed';
  static const taskSkipped = 'task.skipped';
  static const taskFailed = 'task.failed';
  static const taskStopped = 'task.stopped';

  static const consentRequested = 'consent.requested';
  static const consentGranted = 'consent.granted';
  static const consentRevoked = 'consent.revoked';
  static const consentExpired = 'consent.expired';

  static const reviewCreated = 'review.created';
  static const reviewAccepted = 'review.accepted';
  static const reviewRejected = 'review.rejected';
}

