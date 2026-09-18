//! Unit tests for the drift wire models — U09 additions: run-summary snapshot
//! pair getters (`snapshotId` / `baselineSnapshotId`) used by the run-history
//! "View Diff" to open exactly the pair that run compared.

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/drift_models.dart';

DriftRunHistoryEntry _entryWithSummary(String? summaryJson) {
  return DriftRunHistoryEntry(
    id: 'r1',
    taskId: 't1',
    startedAt: '2026-08-17T10:00:00Z',
    finishedAt: '2026-08-17T10:00:05Z',
    status: 'succeeded',
    error: null,
    summaryJson: summaryJson,
    triggeredBy: 'scheduler',
  );
}

void main() {
  group('DriftRunHistoryEntry — snapshot pair getters (U09)', () {
    test('reads snapshot ids from a post-U09 summary', () {
      final e = _entryWithSummary(
        '{"drift_count":2,"webhook_status":"ok","duration_ms":120,'
        '"snapshot_id":"snap-9","baseline_snapshot_id":"snap-8"}',
      );
      expect(e.snapshotId, 'snap-9');
      expect(e.baselineSnapshotId, 'snap-8');
      expect(e.driftCount, 2);
    });

    test('first run has snapshot id but null baseline', () {
      final e = _entryWithSummary(
        '{"drift_count":0,"webhook_status":"skipped","duration_ms":50,'
        '"snapshot_id":"snap-first","baseline_snapshot_id":null}',
      );
      expect(e.snapshotId, 'snap-first');
      expect(e.baselineSnapshotId, isNull);
    });

    test('legacy summary without the keys yields nulls (fallback to latest two)', () {
      final e = _entryWithSummary(
        '{"drift_count":1,"webhook_status":"ok","duration_ms":80}',
      );
      expect(e.snapshotId, isNull);
      expect(e.baselineSnapshotId, isNull);
    });

    test('missing or empty summary yields nulls without throwing', () {
      expect(_entryWithSummary(null).snapshotId, isNull);
      expect(_entryWithSummary('').baselineSnapshotId, isNull);
      expect(_entryWithSummary('not json').snapshotId, isNull);
      // Empty-string ids are treated as absent.
      final e = _entryWithSummary(
        '{"snapshot_id":"","baseline_snapshot_id":""}',
      );
      expect(e.snapshotId, isNull);
      expect(e.baselineSnapshotId, isNull);
    });
  });
}
