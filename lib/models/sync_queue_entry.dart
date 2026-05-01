enum SyncOp { upsert, delete }

enum SyncDomain {
  userProfile,
  userCollections,
  fastingState,
  userQuests,
  nutritionLog,
  activityLog,
  financeRecord,
}

class SyncQueueEntry {
  final SyncDomain domain;
  final String key;
  final SyncOp op;
  final DateTime queuedAt;

  const SyncQueueEntry({
    required this.domain,
    required this.key,
    required this.op,
    required this.queuedAt,
  });
}
