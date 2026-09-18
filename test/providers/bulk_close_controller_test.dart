import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/providers/bulk_close_controller.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;

void main() {
  group('BulkCloseController', () {
    late QueryTab tabA;
    late QueryTab tabB;
    late QueryTab tabC;

    setUp(() {
      tabA = QueryTab(id: 'a', title: 'Tab A', sql: 'SELECT 1');
      tabB = QueryTab(id: 'b', title: 'Tab B', sql: 'SELECT 2');
      tabC = QueryTab(id: 'c', title: 'Tab C', sql: 'SELECT 3');
    });

    test('defaults all items to pending', () {
      final controller = BulkCloseController([tabA, tabB]);

      expect(controller.items.length, 2);
      expect(controller.allDecided, isFalse);
      expect(controller.hasPendingItems, isTrue);
      expect(controller.tabsToKeep, [tabA, tabB]);
      expect(controller.tabsToSave, isEmpty);
      expect(controller.tabsToDiscard, isEmpty);
    });

    test('saveAllPending marks pending items as save', () {
      final controller = BulkCloseController([tabA, tabB]);
      controller.setDecision(tabB, BulkCloseDecision.discard);

      controller.saveAllPending();

      expect(controller.decisionFor(tabA), BulkCloseDecision.save);
      expect(controller.decisionFor(tabB), BulkCloseDecision.discard);
    });

    test('discardAllPending marks pending items as discard', () {
      final controller = BulkCloseController([tabA, tabB]);
      controller.setDecision(tabA, BulkCloseDecision.save);

      controller.discardAllPending();

      expect(controller.decisionFor(tabA), BulkCloseDecision.save);
      expect(controller.decisionFor(tabB), BulkCloseDecision.discard);
    });

    test('pendingAll resets all items to pending', () {
      final controller = BulkCloseController([tabA, tabB]);
      controller.discardAllPending();

      controller.pendingAll();

      expect(controller.allDecided, isFalse);
      expect(controller.tabsToKeep, [tabA, tabB]);
    });

    test('setDecision updates a single item', () {
      final controller = BulkCloseController([tabA, tabB, tabC]);

      controller.setDecision(tabB, BulkCloseDecision.discard);

      expect(controller.decisionFor(tabA), BulkCloseDecision.pending);
      expect(controller.decisionFor(tabB), BulkCloseDecision.discard);
      expect(controller.decisionFor(tabC), BulkCloseDecision.pending);
      expect(controller.tabsToDiscard, [tabB]);
    });

    test('notifyListeners is called when decisions change', () {
      final controller = BulkCloseController([tabA]);
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setDecision(tabA, BulkCloseDecision.save);

      expect(notified, isTrue);
    });

    test('notifyListeners is not called when decision is unchanged', () {
      final controller = BulkCloseController([tabA]);
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setDecision(tabA, BulkCloseDecision.pending);

      expect(notified, isFalse);
    });

    test('decisionFor returns pending for unknown tab instead of throwing', () {
      final controller = BulkCloseController([tabA, tabB]);
      final unknownTab = QueryTab(id: 'unknown', title: 'Unknown', sql: 'SELECT');

      expect(
        () => controller.decisionFor(unknownTab),
        returnsNormally,
      );
      expect(controller.decisionFor(unknownTab), BulkCloseDecision.pending);
    });

    test('setDecision ignores unknown tab instead of throwing', () {
      final controller = BulkCloseController([tabA, tabB]);
      final unknownTab = QueryTab(id: 'unknown', title: 'Unknown', sql: 'SELECT');
      var notified = false;
      controller.addListener(() => notified = true);

      expect(
        () => controller.setDecision(unknownTab, BulkCloseDecision.save),
        returnsNormally,
      );
      expect(notified, isFalse);
      expect(controller.tabsToSave, isEmpty);
    });

    test('handles stale tab reference after tab list changes', () {
      final controller = BulkCloseController([tabA, tabB]);
      controller.setDecision(tabA, BulkCloseDecision.save);
      controller.setDecision(tabB, BulkCloseDecision.discard);

      // Re-create controller without tabA to simulate tab closure.
      final newController = BulkCloseController([tabB]);
      newController.setDecision(tabA, BulkCloseDecision.discard);

      expect(newController.tabsToDiscard, isEmpty);
      expect(newController.decisionFor(tabA), BulkCloseDecision.pending);
    });
  });
}
