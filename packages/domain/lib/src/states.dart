enum ClaimState { proposed, confirmed, disputed, expired, withdrawn }

enum GoalState { draft, active, paused, achieved, abandoned, replaced }

enum PlanState { draft, approved, active, paused, completed, stopped }

enum TaskState {
  planned,
  ready,
  inProgress,
  completed,
  skipped,
  failed,
  stopped,
}

enum ConsentState { requested, granted, expired, revoked }

enum ReviewState { draft, userReviewed, accepted, rejected }
