import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/snapshot_service.dart';

// Plan 053 Phase 3.5 — the retention/prune decision (which snapshots to delete)
// is pure and unit-tested here; the Supabase write/list/restore wiring is
// exercised by the Phase 4 fake-Supabase harness.
void main() {
  group('SnapshotService.snapshotsToDelete', () {
    test('returns empty when at or under the keep limit', () {
      expect(SnapshotService.snapshotsToDelete(['c', 'b', 'a'], 30), isEmpty);
      expect(
        SnapshotService.snapshotsToDelete(List.generate(30, (i) => 't$i'), 30),
        isEmpty,
      );
    });

    test('returns the oldest beyond the keep limit (newest-first input)', () {
      // t0 = newest … t32 = oldest; keep 30 → drop the 3 oldest.
      final desc = List.generate(33, (i) => 't$i');
      expect(
          SnapshotService.snapshotsToDelete(desc, 30), ['t30', 't31', 't32']);
    });
  });
}
