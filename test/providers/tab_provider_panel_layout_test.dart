// spec 041 (US1/Foundational) — per-tab 面板可见性状态机单元测试。
// 覆盖：默认预设、set/updatePanelLayout、_ensureResultsVisible（成功+错误+空结果集）、
// 生命周期清理、PanelLayout 相等性（context.select 前提）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/panel_layout.dart';
import 'package:dbmaster/models/filter_condition.dart';

class MockDatabaseService extends Mock implements DatabaseService {}

void main() {
  group('TabProvider panel layout (spec 041)', () {
    late TabProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TabProvider(MockDatabaseService());
    });

    test('panelLayoutFor 默认 PanelLayout.query（editor 显、filter/results 隐）', () {
      const layout = PanelLayout.query;
      expect(layout.editorVisible, isTrue);
      expect(layout.filterBarVisible, isFalse);
      expect(layout.resultsVisible, isFalse);
      // 未设置过的 tabId 取默认
      expect(provider.panelLayoutFor('unknown'), PanelLayout.query);
    });

    test('setPanelLayout 存储 browse 预设', () {
      provider.setPanelLayout('t1', PanelLayout.browse);
      final layout = provider.panelLayoutFor('t1');
      expect(layout, PanelLayout.browse);
      expect(layout.editorVisible, isFalse);
      expect(layout.filterBarVisible, isTrue);
      expect(layout.resultsVisible, isFalse);
    });

    test('updatePanelLayout 仅翻转指定位、其余保留', () {
      provider.setPanelLayout('t1', PanelLayout.query); // (true,false,false)
      provider.updatePanelLayout('t1', results: true);
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
      expect(provider.panelLayoutFor('t1').editorVisible, isTrue); // 未动
      expect(provider.panelLayoutFor('t1').filterBarVisible, isFalse); // 未动
      provider.updatePanelLayout('t1', editor: false);
      expect(provider.panelLayoutFor('t1').editorVisible, isFalse);
    });

    test('addResultToTab 翻 resultsVisible false->true（FR-009）', () {
      provider.setPanelLayout('t1', PanelLayout.query);
      expect(provider.panelLayoutFor('t1').resultsVisible, isFalse);
      provider.addResultToTab(
        't1',
        <ExecutionResult>[],
        sql: 'SELECT 1',
        executionTime: Duration.zero,
      );
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
    });

    test('addErrorMessageToTab 同样翻 resultsVisible true（错误也显 results）', () {
      provider.setPanelLayout('t1', PanelLayout.query);
      provider.addErrorMessageToTab('t1', 'boom', sql: 'SELECT 1');
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
    });

    test('空结果集（0 行）仍显 results 面板（Edge：不回退隐藏）', () {
      provider.setPanelLayout('t1', PanelLayout.query);
      provider.addResultToTab(
        't1',
        <ExecutionResult>[], // 0 行
        sql: 'SELECT 1',
        executionTime: Duration.zero,
      );
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
    });

    test('手动隐 results 后再执行 -> 再次翻 true（接受该行为）', () {
      provider.setPanelLayout('t1', PanelLayout.query);
      provider.addResultToTab(
        't1',
        <ExecutionResult>[],
        sql: 'SELECT 1',
        executionTime: Duration.zero,
      );
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
      // 用户手动隐
      provider.updatePanelLayout('t1', results: false);
      expect(provider.panelLayoutFor('t1').resultsVisible, isFalse);
      // 再次执行
      provider.addResultToTab(
        't1',
        <ExecutionResult>[],
        sql: 'SELECT 2',
        executionTime: Duration.zero,
      );
      expect(provider.panelLayoutFor('t1').resultsVisible, isTrue);
    });

    test('closeAllTabs 清理 per-tab 布局（会话内、不持久化）', () async {
      provider.setPanelLayout('t1', PanelLayout.browse);
      expect(provider.panelLayoutFor('t1'), PanelLayout.browse);
      await provider.closeAllTabs();
      // 清理后回到默认
      expect(provider.panelLayoutFor('t1'), PanelLayout.query);
    });

    test('PanelLayout 相等性（context.select 精确比较前提）', () {
      expect(PanelLayout.query, equals(PanelLayout.query));
      expect(PanelLayout.query == PanelLayout.browse, isFalse);
      expect(
        PanelLayout.query.copyWith(resultsVisible: true),
        const PanelLayout(
          editorVisible: true,
          filterBarVisible: false,
          resultsVisible: true,
        ),
      );
      // hashCode 与 == 一致
      expect(PanelLayout.query.hashCode, PanelLayout.query.hashCode);
    });

    test('FilterBar 相关 getter 默认值', () {
      expect(provider.browseTargetFor('t1'), isNull);
      expect(provider.filterConditionsFor('t1'), isEmpty);
      expect(provider.filterCombinatorFor('t1'), FilterCombinator.and);
    });

    test('新建 query tab 默认 PanelLayout.query（results 隐）— US4/T027', () async {
      final tab = await provider.openQueryTab(
        connectionId: 'c1',
        databaseName: 'db',
      );
      expect(tab.id, isNotEmpty);
      final layout = provider.panelLayoutFor(tab.id);
      expect(layout, PanelLayout.query);
      expect(layout.resultsVisible, isFalse, reason: '新 query tab results 应默认隐藏');
      expect(layout.editorVisible, isTrue);
      expect(layout.filterBarVisible, isFalse);
    });
  });
}
