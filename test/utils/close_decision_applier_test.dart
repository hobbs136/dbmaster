import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/molecules/bulk_close_dialog.dart';
import 'package:dbmaster/providers/bulk_close_controller.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/utils/close_decision_applier.dart';

void main() {
  group('CloseDecisionApplier', () {
    late QueryTab tabA;
    late QueryTab tabB;
    late QueryTab tabC;

    setUp(() {
      tabA = QueryTab(id: 'a', title: 'Tab A', sql: 'SELECT 1');
      tabB = QueryTab(id: 'b', title: 'Tab B', sql: 'SELECT 2');
      tabC = QueryTab(id: 'c', title: 'Tab C', sql: 'SELECT 3');
    });

    test('returns false when result is cancelled', () async {
      final result = await CloseDecisionApplier.applyDecisions(
        tabs: [tabA, tabB],
        saveTab: (_) async => true,
        closeTabAtIndex: (_) async {},
        result: BulkCloseResult.cancelled,
      );

      expect(result, isFalse);
    });

    test('saves and closes tabs marked save', () async {
      final savedTabIds = <String>[];
      final closedIndices = <int>[];

      final result = await CloseDecisionApplier.applyDecisions(
        tabs: [tabA, tabB],
        saveTab: (tab) async {
          savedTabIds.add(tab.id);
          return true;
        },
        closeTabAtIndex: (index) async => closedIndices.add(index),
        result: BulkCloseResult(
          confirmed: true,
          decisions: {
            'a': BulkCloseDecision.save,
            'b': BulkCloseDecision.discard,
          },
        ),
      );

      expect(result, isTrue);
      expect(savedTabIds, ['a']);
      expect(closedIndices, contains(0)); // saved tab closed first
      expect(closedIndices, contains(1)); // discarded tab closed second
    });

    test('returns false when a save fails and does not close failed tab', () async {
      final closedIndices = <int>[];

      final result = await CloseDecisionApplier.applyDecisions(
        tabs: [tabA, tabB],
        saveTab: (tab) async => tab.id != 'a',
        closeTabAtIndex: (index) async => closedIndices.add(index),
        result: BulkCloseResult(
          confirmed: true,
          decisions: {
            'a': BulkCloseDecision.save,
            'b': BulkCloseDecision.discard,
          },
        ),
      );

      expect(result, isFalse);
      expect(closedIndices, isNot(contains(0)));
      expect(closedIndices, contains(1));
    });

    test('ignores decisions for tabs that no longer exist', () async {
      final savedTabIds = <String>[];
      final closedIndices = <int>[];

      final result = await CloseDecisionApplier.applyDecisions(
        tabs: [tabA, tabB],
        saveTab: (tab) async {
          savedTabIds.add(tab.id);
          return true;
        },
        closeTabAtIndex: (index) async => closedIndices.add(index),
        result: BulkCloseResult(
          confirmed: true,
          decisions: {
            'a': BulkCloseDecision.save,
            'b': BulkCloseDecision.discard,
            'c': BulkCloseDecision.save, // tab c no longer exists
          },
        ),
      );

      expect(result, isTrue);
      expect(savedTabIds, ['a']);
      expect(closedIndices, [0, 1]);
    });

    test('closes all discard tabs for 3+ tabs without index errors', () async {
      final closedIndices = <int>[];

      final result = await CloseDecisionApplier.applyDecisions(
        tabs: [tabA, tabB, tabC],
        saveTab: (_) async => true,
        closeTabAtIndex: (index) async => closedIndices.add(index),
        result: BulkCloseResult(
          confirmed: true,
          decisions: {
            'a': BulkCloseDecision.discard,
            'b': BulkCloseDecision.discard,
            'c': BulkCloseDecision.discard,
          },
        ),
      );

      expect(result, isTrue);
      // Indices must be sorted high-to-low to avoid index shifting.
      expect(closedIndices, [2, 1, 0]);
    });
  });
}
