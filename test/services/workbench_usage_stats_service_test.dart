// 本地统计服务测试（design-ai-workbench §11.1 R8 行 + design-ai-agent T08）。
//
// 覆盖：AC8.1 五类事件落盘 + 导出逐字段核对（仅白名单字段）；AC8.2 敏感
// 字面量不落盘不出导出；AC8.5 零网络静态断言（读取服务源码检查 import 集）；
// 滚动保留裁剪（91 天前键被删 / 27 周前键被删）；T08 schema 2 agent 七桶
// （字段 1/2/3/5/7/8/9：逐方法落盘、FIFO 截断、白名单拒收、schema 1 旧档
// 兼容读入，AC14.4/NF6.1）；T28 schema 3 两桶（字段 4 agentPlans 三计数 /
// 字段 6 agentL1Blocked——metrics 12→14 键）；T31 全量收口（R14 九字段逐字段
// 核对导出 JSON、agent 会话敏感字面量、schema 1/2 全量兼容往返、全源码无网络
// 符号与无自动上报路径静态扫描、FIFO 500 上限与导出聚合中位数正确性——
// AC14.1-14.4 / NF6.1-6.3 终验）。
//
// 约定（组件级 AGENTS.md §0/§5）：SharedPreferences 必须 mock
// （setMockInitialValues）；禁止 import package:dbmaster/main.dart。

import 'dart:convert';
import 'dart:io';

import 'package:dbmaster/services/workbench_usage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 存储键为服务契约（workbench_stats_v1），测试侧具名常量镜像。
const String _statsPrefsKey = 'workbench_stats_v1';

/// 测试侧独立的日期键生成（与服务实现互为印证）。
String _dayKeyOf(DateTime time) {
  final String month = time.month.toString().padLeft(2, '0');
  final String day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}

/// 导出消费侧聚合（R14 字段 3/8「导出时聚合中位数」的口径实现）：偶数样本取
/// 中间两值均值，奇数取中位。服务导出结构（design-ai-agent §5.4）只含原始
/// 样本数组，不新增聚合键（T31 约束「不新增字段」）——聚合发生在导出消费方。
double _medianOf(List<int> samples) {
  final List<int> sorted = samples.toList()..sort();
  final int n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2].toDouble();
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
}

WorkbenchUsageStatsService get _service => WorkbenchUsageStatsService.instance;

Future<String> _storedRaw() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString(_statsPrefsKey) ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _service.resetForTesting();
  });

  tearDown(() async {
    // 冲掉挂起写盘，避免上一用例的串行写泄漏进下一用例的 mock 存储。
    await _service.flushForTesting();
  });

  group('AC8.1 五类事件落盘与导出逐字段', () {
    test('五类记录后存储结构符合设计 §5.3', () async {
      await _service.load();

      _service.recordEntry();
      _service.recordEntry();
      _service.recordEntry();
      _service.recordSession();
      _service.recordSession();
      _service.recordCard(WorkbenchCardKindStat.sqlCard);
      _service.recordCard(WorkbenchCardKindStat.sqlCard);
      _service.recordCard(WorkbenchCardKindStat.resultCard);
      _service.recordOp(WorkbenchOpClass.queryGen);
      _service.recordOp(WorkbenchOpClass.ddlPerm);
      _service.recordOp(WorkbenchOpClass.bulkMaint);
      _service.setAiKeyConfigured(true);
      await _service.flushForTesting();

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      expect(storage['schema'], 3);

      final Map<String, dynamic> days =
          storage['days'] as Map<String, dynamic>;
      final String today = _dayKeyOf(DateTime.now());
      expect(days.keys.toList(), <String>[today]);
      expect(days[today], <String, int>{'e': 3});

      final Map<String, dynamic> weeks =
          storage['weeks'] as Map<String, dynamic>;
      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      expect(weeks.keys.toList(), <String>[thisWeek]);
      expect(weeks[thisWeek], <String, int>{'s': 2});

      expect(storage['cards'], <String, int>{
        'sqlCard': 2,
        'resultCard': 1,
      });
      expect(storage['ops'], <String, int>{
        'queryGen': 1,
        'ddlPerm': 1,
        'bulkMaint': 1,
      });
      expect(storage['aiKey'], isTrue);
    });

    test('exportJson 导出 schema 逐字段核对，仅白名单字段', () async {
      await _service.load();

      _service.recordEntry();
      _service.recordEntry();
      _service.recordCard(WorkbenchCardKindStat.resultCard);
      _service.recordOp(WorkbenchOpClass.queryGen);
      _service.setAiKeyConfigured(true);
      await _service.flushForTesting();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: '9.9.9+test');
      final Map<String, dynamic> json = export.toJson();

      // 顶层仅白名单四键，metrics 仅白名单 14 键（M1 五键 + agent 七键 +
      // T28 两键，「仅白名单字段」执法）。
      expect(
        json.keys.toSet(),
        <String>{'schema', 'appVersion', 'exportedAt', 'metrics'},
      );
      final Map<String, dynamic> metrics = json['metrics'] as Map<String, dynamic>;
      expect(
        metrics.keys.toSet(),
        <String>{
          'dailyEntries',
          'weeklySessions',
          'toolCards',
          'ops',
          'aiKeyConfigured',
          'agentWeeks',
          'agentDays',
          'agentSteps',
          'agentTokens',
          'agentL05',
          'agentTools',
          'agentLimitStops',
          'agentPlans',
          'agentL1Blocked',
        },
      );

      expect(export.schema, 3);
      expect(export.appVersion, '9.9.9+test');
      expect(export.exportedAt.isUtc, isTrue);
      expect(json['exportedAt'], export.exportedAt.toIso8601String());

      final String today = _dayKeyOf(DateTime.now());
      expect(metrics['dailyEntries'], <String, int>{today: 2});
      expect(metrics['weeklySessions'], <String, int>{});
      expect(metrics['toolCards'], <String, int>{'resultCard': 1});
      expect(metrics['ops'], <String, int>{'queryGen': 1});
      expect(metrics['aiKeyConfigured'], isTrue);
    });

    test('落盘后 reset+load 往返可完整恢复', () async {
      await _service.load();

      _service.recordEntry();
      _service.recordEntry();
      _service.recordSession();
      _service.recordCard(WorkbenchCardKindStat.sqlCard);
      _service.recordOp(WorkbenchOpClass.ddlPerm);
      _service.setAiKeyConfigured(true);
      await _service.flushForTesting();

      _service.resetForTesting();
      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      final String today = _dayKeyOf(DateTime.now());
      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      expect(export.dailyEntries, <String, int>{today: 2});
      expect(export.weeklySessions, <String, int>{thisWeek: 1});
      expect(export.toolCards, <String, int>{'sqlCard': 1});
      expect(export.ops, <String, int>{'ddlPerm': 1});
      expect(export.aiKeyConfigured, isTrue);
    });

    test('空态导出：零值空桶 + schema 3', () async {
      await _service.load();

      final Map<String, dynamic> json =
          _service.exportJson(appVersion: 't').toJson();
      expect(json['schema'], 3);
      expect(json['metrics'], <String, dynamic>{
        'dailyEntries': <String, int>{},
        'weeklySessions': <String, int>{},
        'toolCards': <String, int>{},
        'ops': <String, int>{},
        'aiKeyConfigured': false,
        'agentWeeks': <String, int>{},
        'agentDays': <String, int>{},
        'agentSteps': <int>[],
        'agentTokens': <int>[],
        'agentL05': <String, int>{},
        'agentTools': <String, int>{},
        'agentLimitStops': 0,
        'agentPlans': <String, int>{},
        'agentL1Blocked': 0,
      });
    });
  });

  group('滚动保留裁剪', () {
    test('91 天前的按天键被裁剪删除，90 天窗口边缘保留', () async {
      final DateTime now = DateTime.now();
      final String today = _dayKeyOf(now);
      final String keptEdge = _dayKeyOf(now.subtract(const Duration(days: 89)));
      final String droppedAt90 =
          _dayKeyOf(now.subtract(const Duration(days: 90)));
      final String droppedAt91 =
          _dayKeyOf(now.subtract(const Duration(days: 91)));

      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 1,
          'days': <String, dynamic>{
            droppedAt91: <String, int>{'e': 1},
            droppedAt90: <String, int>{'e': 1},
            keptEdge: <String, int>{'e': 2},
            today: <String, int>{'e': 3},
          },
          'weeks': <String, dynamic>{},
          'cards': <String, int>{},
          'ops': <String, int>{},
          'aiKey': false,
        }),
      });

      await _service.load();

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      final Map<String, dynamic> days =
          storage['days'] as Map<String, dynamic>;
      expect(days.containsKey(droppedAt91), isFalse, reason: '91 天前键必须删除');
      expect(days.containsKey(droppedAt90), isFalse, reason: '90 天窗口外（today-90）键删除');
      expect(days[keptEdge], <String, int>{'e': 2}, reason: 'today-89 在 90 天窗口内保留');
      expect(days[today], <String, int>{'e': 3});
    });

    test('27 周前的按周键被裁剪删除，26 周窗口边缘保留', () async {
      final DateTime now = DateTime.now();
      final String keptWeek25 = WorkbenchUsageStatsService.isoWeekKey(
        now.subtract(const Duration(days: 7 * 25)),
      );
      final String droppedWeek26 = WorkbenchUsageStatsService.isoWeekKey(
        now.subtract(const Duration(days: 7 * 26)),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 1,
          'days': <String, dynamic>{},
          'weeks': <String, dynamic>{
            droppedWeek26: <String, int>{'s': 5},
            keptWeek25: <String, int>{'s': 1},
          },
          'cards': <String, int>{},
          'ops': <String, int>{},
          'aiKey': false,
        }),
      });

      await _service.load();

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      final Map<String, dynamic> weeks =
          storage['weeks'] as Map<String, dynamic>;
      expect(weeks.containsKey(droppedWeek26), isFalse, reason: '27 周前键必须删除');
      expect(weeks[keptWeek25], <String, int>{'s': 1});
    });
  });

  group('AC8.2 敏感字面量不落盘不出导出', () {
    test('构造含密码与连接名的操作后，存储与导出串均不含字面量', () async {
      const String passwordLiteral = 'password123';
      const String connectionName = 'my_secret_connection_name';

      await _service.load();

      // 模拟真实使用：用户在持有该连接名/密码的上下文里发生的全部统计动作。
      // 服务 API 只接受枚举（NF2.1 白名单），没有任何自由字符串入口——凭据与
      // 连接名结构上进不了存储与导出；此断言守护该性质不被后续改动破坏。
      _service.recordEntry();
      _service.recordSession();
      _service.recordCard(WorkbenchCardKindStat.sqlCard);
      _service.recordOp(WorkbenchOpClass.bulkMaint);
      _service.setAiKeyConfigured(true);
      await _service.flushForTesting();

      final String exported = jsonEncode(
        _service.exportJson(appVersion: '0.0.1+1').toJson(),
      );
      expect(exported, isNot(contains(passwordLiteral)));
      expect(exported, isNot(contains(connectionName)));
      expect(exported, isNot(contains('password')));

      final String stored = await _storedRaw();
      expect(stored, isNot(contains(passwordLiteral)));
      expect(stored, isNot(contains(connectionName)));
    });
  });

  group('AC8.5 零网络静态断言', () {
    test('服务源码 import 集在白名单内且不含网络符号', () async {
      final String source = await File(
        'lib/services/workbench_usage_stats_service.dart',
      ).readAsString();

      final RegExp importPattern = RegExp(
        r"^\s*import\s+'([^']+)'",
        multiLine: true,
      );
      final List<String> imports = importPattern
          .allMatches(source)
          .map((RegExpMatch m) => m.group(1)!)
          .toList(growable: false);
      expect(imports, isNotEmpty, reason: '必须能从源码解析出 import 才能执法');

      // 白名单（dart:convert 为核心库，仅 prefs JSON 编解码用，非网络库）。
      const Set<String> allowed = <String>{
        'dart:convert',
        'package:flutter/foundation.dart',
        'package:shared_preferences/shared_preferences.dart',
      };
      for (final String uri in imports) {
        expect(allowed, contains(uri), reason: '越界 import: $uri');
      }

      // AC8.5 字面执法：不含 http/socket/dio 等网络符号。
      final RegExp networkPattern = RegExp(
        r'dart:(io|socket)|package:(http|dio)|socket|websocket',
        caseSensitive: false,
      );
      for (final String uri in imports) {
        expect(networkPattern.hasMatch(uri), isFalse, reason: '网络符号混入: $uri');
      }
    });

    test('全源码（剥离注释后）无网络符号、无自动上报路径（NF6.3/AC14.3，T31）',
        () async {
      final String source = await File(
        'lib/services/workbench_usage_stats_service.dart',
      ).readAsString();

      // 剥离前提（先行自检）：服务源码注释全为 // 行注释、无 /* */ 块注释，
      // 且无字符串字面量含 '//'——按行剥离注释后得到的「纯代码」是可靠扫描面。
      // 若未来引入块注释或含 '//' 的字符串字面量，须先修订剥离策略再扩展扫描。
      expect(source.contains('/*'), isFalse, reason: '出现块注释需先修订剥离策略');
      final String code = source.replaceAll(RegExp(r'//.*'), '');

      // 剥离自检：纯代码仍含服务类定义与 prefs 依赖（扫描面未被误剥空）。
      expect(code, contains('class WorkbenchUsageStatsService'));
      expect(code, contains('SharedPreferences'));

      // NF6.3/AC14.3：纯代码无网络符号（import 集白名单由上一用例执法，
      // 本用例把扫描面扩展到函数体——无任何发起请求/解析 URL 的符号）。
      final RegExp networkSymbols = RegExp(
        r'http|socket|websocket|dio|xmlhttprequest|uri\.parse|dart:io|package:http|fetch\(',
        caseSensitive: false,
      );
      final RegExpMatch? networkHit = networkSymbols.firstMatch(code);
      expect(networkHit, isNull, reason: '纯代码出现网络符号: ${networkHit?.group(0)}');

      // 无自动上报路径：自动上报需脱离用户操作触发——定时器（Timer/periodic）、
      // 后台执行体（Isolate/SendPort）或上报类符号任一即可疑，全部不得出现。
      // 导出仅由设置页手动一键触发（settings_dialog 消费 exportJson），落盘
      // 只经 SharedPreferences；本文件全部行为用例以 mock prefs 运行即
      // 「断网可用」的行为面补证。
      final RegExp autoReportSymbols = RegExp(
        r'Timer|Isolate|SendPort|periodic|upload|telemetry|analytics|postEvent|sendReport',
        caseSensitive: false,
      );
      final RegExpMatch? reportHit = autoReportSymbols.firstMatch(code);
      expect(reportHit, isNull, reason: '纯代码出现自动上报路径符号: ${reportHit?.group(0)}');
    });
  });

  group('aiKey 单向置位', () {
    test('false 不置位；true 置位后再传 false 不回落', () async {
      await _service.load();

      _service.setAiKeyConfigured(false);
      expect(_service.exportJson(appVersion: 't').aiKeyConfigured, isFalse);

      _service.setAiKeyConfigured(true);
      _service.setAiKeyConfigured(false);
      expect(_service.exportJson(appVersion: 't').aiKeyConfigured, isTrue);
    });

    test('置位经落盘往返后仍保持', () async {
      await _service.load();
      _service.setAiKeyConfigured(true);
      await _service.flushForTesting();

      _service.resetForTesting();
      await _service.load();
      expect(_service.exportJson(appVersion: 't').aiKeyConfigured, isTrue);
    });
  });

  group('T28 字段 4/6：agentPlans 三计数 + agentL1Blocked', () {
    test('recordPlanEvent 三值分桶 + recordL1Blocked 计数 + 落盘往返恢复', () async {
      await _service.load();

      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.approved);
      _service.recordPlanEvent(AgentPlanStat.rejected);
      _service.recordL1Blocked();
      _service.recordL1Blocked();
      await _service.flushForTesting();

      _service.resetForTesting();
      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.agentPlans, <String, int>{
        'shown': 2,
        'approved': 1,
        'rejected': 1,
      });
      expect(export.agentL1Blocked, 2);
      expect(export.schema, 3);
    });

    test('agentPlans 读盘白名单拒收越界键（NF2.1 延伸）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 3,
          'agentPlans': <String, int>{'shown': 1, 'executed': 9},
          'agentL1Blocked': 1,
        }),
      });
      await _service.load();
      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.agentPlans, <String, int>{'shown': 1});
      expect(export.agentL1Blocked, 1);
    });

    test('schema 2 旧档读入：缺 agentPlans/agentL1Blocked 键零值不炸（AC14.4 加法）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 2,
          'agentL05': <String, int>{'shown': 3},
          'agentLimitStops': 1,
          // 无 agentPlans / agentL1Blocked（schema 2 形态）
        }),
      });
      await _service.load();
      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.agentL05, <String, int>{'shown': 3});
      expect(export.agentPlans, <String, int>{});
      expect(export.agentL1Blocked, 0);
    });
  });

  group('ISO 周键生成', () {
    test('已知日期互证（含跨年边界与 53 周年）', () {
      // 2026-01-01 为周四 → 自成 2026 年 W1。
      expect(
        WorkbenchUsageStatsService.isoWeekKey(DateTime(2026, 1, 1)),
        '2026-W01',
      );
      // 2025-12-29（周一）所在周的周四为 2026-01-01 → 属 2026-W01。
      expect(
        WorkbenchUsageStatsService.isoWeekKey(DateTime(2025, 12, 29)),
        '2026-W01',
      );
      // 2026-09-22（周二）：其周四为 09-24，年内第 39 周。
      expect(
        WorkbenchUsageStatsService.isoWeekKey(DateTime(2026, 9, 22)),
        '2026-W39',
      );
      // 2026 有 53 个 ISO 周（01-01 为周四）：2026-12-28（周一）属 W53。
      expect(
        WorkbenchUsageStatsService.isoWeekKey(DateTime(2026, 12, 28)),
        '2026-W53',
      );
    });
  });

  group('防御式读盘（白名单执法延伸到 load）', () {
    test('损坏的存储 JSON 静默降级为空态且不抛出', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: '{not-valid-json',
      });

      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.dailyEntries, isEmpty);
      expect(export.toolCards, isEmpty);
      expect(export.aiKeyConfigured, isFalse);
    });

    test('越界枚举键读盘时被拒收', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 1,
          'days': <String, dynamic>{},
          'weeks': <String, dynamic>{},
          'cards': <String, dynamic>{'sqlCard': 2, 'rogueCard': 7},
          'ops': <String, dynamic>{'queryGen': 1, 'rogueOp': 3},
          'aiKey': true,
        }),
      });

      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.toolCards, <String, int>{'sqlCard': 2});
      expect(export.ops, <String, int>{'queryGen': 1});
      expect(export.aiKeyConfigured, isTrue);
    });
  });

  group('T08 schema 2 · agent 七字段落盘（design-ai-agent §4.7/§5.4）', () {
    test('六个 record 方法逐字段落盘且 schema=2（字段 1/2/3/5/7/8/9）', () async {
      await _service.load();

      // 字段 1：按周计数（同周聚合）。
      _service.recordAgentSessionStart();
      _service.recordAgentSessionStart();
      _service.recordAgentSessionStart();
      // 字段 2：按天去重（同日重复启动不重复计）。
      _service.recordAgentActiveDay();
      _service.recordAgentActiveDay();
      // 字段 3/8：运行结束样本（tokens 缺失 → 不进 token 样本）。
      _service.recordAgentRunEnd(steps: 12, tokens: 18432);
      _service.recordAgentRunEnd(steps: 25);
      // 字段 5：L0.5 三态计数。
      _service.recordL05Event(AgentL05Stat.shown);
      _service.recordL05Event(AgentL05Stat.shown);
      _service.recordL05Event(AgentL05Stat.sessionAllowed);
      _service.recordL05Event(AgentL05Stat.rejected);
      // 字段 7：工具分桶。
      _service.recordAgentToolCall('list_tables');
      _service.recordAgentToolCall('list_tables');
      _service.recordAgentToolCall('execute_readonly_sql');
      // 字段 9。
      _service.recordLimitStop();
      await _service.flushForTesting();

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      expect(storage['schema'], 3);

      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      expect(
        storage['agentWeeks'],
        <String, dynamic>{thisWeek: <String, int>{'starts': 3}},
      );
      final String today = _dayKeyOf(DateTime.now());
      expect(storage['agentDays'], <String, int>{today: 1});
      expect(storage['agentSteps'], <int>[12, 25]);
      expect(storage['agentTokens'], <int>[18432]);
      expect(storage['agentL05'], <String, int>{
        'shown': 2,
        'sessionAllowed': 1,
        'rejected': 1,
      });
      expect(storage['agentTools'], <String, int>{
        'list_tables': 2,
        'execute_readonly_sql': 1,
      });
      expect(storage['agentLimitStops'], 1);
    });

    test('FIFO 截断：样本超 500 丢最旧、新样本在尾', () async {
      await _service.load();

      for (int i = 0; i < 505; i++) {
        _service.recordAgentRunEnd(steps: i);
      }
      for (int i = 0; i < 502; i++) {
        // steps 传负值（走拒收路径）以免污染步数样本，单独压测 token FIFO。
        _service.recordAgentRunEnd(steps: -1, tokens: i);
      }
      await _service.flushForTesting();

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      final List<int> steps = (storage['agentSteps'] as List<dynamic>)
          .map((Object? e) => e as int)
          .toList();
      final List<int> tokens = (storage['agentTokens'] as List<dynamic>)
          .map((Object? e) => e as int)
          .toList();
      expect(steps.length, 500);
      expect(steps.first, 5, reason: '最旧 5 条（0..4）被丢弃');
      expect(steps.last, 504);
      expect(tokens.length, 500);
      expect(tokens.first, 2, reason: '最旧 2 条（0..1）被丢弃');
      expect(tokens.last, 501);
    });

    test('负值样本拒收 + 工具分桶白名单写侧执法（NF6.1）', () async {
      await _service.load();

      _service.recordAgentRunEnd(steps: -1, tokens: -5);
      _service.recordAgentToolCall('rogue_tool');
      _service.recordAgentToolCall('');
      await _service.flushForTesting();

      // 全部操作被拒收 → 无任何有效写入，存储保持为空（未被创建过）。
      expect(await _storedRaw(), '');

      // AgentToolCatalog 17 个编译期固定目录名全部接受（镜像全集互证；
      // T4 追加 save_saved_query / save_memory / list_memories）。
      const List<String> catalogNames = <String>[
        'execute_readonly_sql',
        'list_tables',
        'describe_table',
        'get_sample_data',
        'explain_plan',
        'get_current_context',
        'submit_action_plan',
        'open_result_grid',
        'show_table_structure',
        'open_sql_editor',
        'render_chart',
        'pin_artifact',
        'open_in_classic',
        'focus_sidebar',
        'save_saved_query',
        'save_memory',
        'list_memories',
      ];
      for (final String name in catalogNames) {
        _service.recordAgentToolCall(name);
      }
      await _service.flushForTesting();
      final Map<String, dynamic> storage2 =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      expect(
        (storage2['agentTools'] as Map<String, dynamic>).keys.toSet(),
        catalogNames.toSet(),
      );
    });

    test('导出 metrics 恰为 M1 五键 + agent 七键 + T28 两键（14 键），不溢出 R14 白名单', () async {
      await _service.load();

      _service.recordAgentSessionStart();
      _service.recordAgentRunEnd(steps: 3, tokens: 900);
      _service.recordLimitStop();
      await _service.flushForTesting();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: '9.9.9+test');
      final Map<String, dynamic> json = export.toJson();
      expect(export.schema, 3);

      final Map<String, dynamic> metrics =
          json['metrics'] as Map<String, dynamic>;
      expect(
        metrics.keys.toSet(),
        <String>{
          // M1 既有五键（AC14.4 加法兼容，消费方不受影响）
          'dailyEntries',
          'weeklySessions',
          'toolCards',
          'ops',
          'aiKeyConfigured',
          // T08 agent 七键（字段 1/2/3/5/7/8/9）
          'agentWeeks',
          'agentDays',
          'agentSteps',
          'agentTokens',
          'agentL05',
          'agentTools',
          'agentLimitStops',
          // T28 两键（R14 字段 4/6）
          'agentPlans',
          'agentL1Blocked',
        },
      );

      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      expect(export.agentWeeks, <String, int>{thisWeek: 1});
      expect(export.agentDays, <String, int>{});
      expect(export.agentSteps, <int>[3]);
      expect(export.agentTokens, <int>[900]);
      expect(export.agentL05, <String, int>{});
      expect(export.agentTools, <String, int>{});
      expect(export.agentLimitStops, 1);
    });

    test('schema 1 旧档读入：缺键零值不炸、旧数据保留、写入后升级 schema 3（AC14.4）',
        () async {
      final DateTime now = DateTime.now();
      final String today = _dayKeyOf(now);
      final String thisWeek = WorkbenchUsageStatsService.isoWeekKey(now);
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 1,
          'days': <String, dynamic>{today: <String, int>{'e': 4}},
          'weeks': <String, dynamic>{thisWeek: <String, int>{'s': 2}},
          'cards': <String, int>{'sqlCard': 7},
          'ops': <String, int>{'queryGen': 3},
          'aiKey': true,
          // 无任何 agent 键（schema 1 形态）
        }),
      });

      await _service.load();

      // 旧数据完整保留 + 新桶零值（缺键 = 零值）。
      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.dailyEntries, <String, int>{today: 4});
      expect(export.weeklySessions, <String, int>{thisWeek: 2});
      expect(export.toolCards, <String, int>{'sqlCard': 7});
      expect(export.ops, <String, int>{'queryGen': 3});
      expect(export.aiKeyConfigured, isTrue);
      expect(export.agentWeeks, <String, int>{});
      expect(export.agentDays, <String, int>{});
      expect(export.agentSteps, <int>[]);
      expect(export.agentTokens, <int>[]);
      expect(export.agentL05, <String, int>{});
      expect(export.agentTools, <String, int>{});
      expect(export.agentLimitStops, 0);
      expect(export.agentPlans, <String, int>{});
      expect(export.agentL1Blocked, 0);

      // 升级写入：schema 3 + 新键落盘 + 旧键保留（导出消费方可解析，AC14.4）。
      _service.recordAgentSessionStart();
      await _service.flushForTesting();
      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      expect(storage['schema'], 3);
      expect(storage['days'], <String, dynamic>{today: <String, int>{'e': 4}});
      expect(storage['agentWeeks'],
          <String, dynamic>{thisWeek: <String, int>{'starts': 1}});
    });

    test('agent 计数经落盘往返可完整恢复', () async {
      await _service.load();

      _service.recordAgentSessionStart();
      _service.recordAgentActiveDay();
      _service.recordAgentRunEnd(steps: 9, tokens: 1234);
      _service.recordL05Event(AgentL05Stat.sessionAllowed);
      _service.recordAgentToolCall('explain_plan');
      _service.recordLimitStop();
      await _service.flushForTesting();

      _service.resetForTesting();
      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      final String today = _dayKeyOf(DateTime.now());
      expect(export.agentWeeks, <String, int>{thisWeek: 1});
      expect(export.agentDays, <String, int>{today: 1});
      expect(export.agentSteps, <int>[9]);
      expect(export.agentTokens, <int>[1234]);
      expect(export.agentL05, <String, int>{'sessionAllowed': 1});
      expect(export.agentTools, <String, int>{'explain_plan': 1});
      expect(export.agentLimitStops, 1);
    });

    test('agent 周/天桶沿用既有滚动窗口裁剪 + 读盘白名单拒收越界键', () async {
      final DateTime now = DateTime.now();
      final String freshDay = _dayKeyOf(now);
      final String staleDay = _dayKeyOf(now.subtract(const Duration(days: 91)));
      final String freshWeek = WorkbenchUsageStatsService.isoWeekKey(now);
      final String staleWeek = WorkbenchUsageStatsService.isoWeekKey(
        now.subtract(const Duration(days: 7 * 27)),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 2,
          'days': <String, dynamic>{},
          'weeks': <String, dynamic>{},
          'cards': <String, int>{},
          'ops': <String, int>{},
          'aiKey': false,
          'agentWeeks': <String, dynamic>{
            staleWeek: <String, int>{'starts': 2},
            freshWeek: <String, int>{'starts': 1},
          },
          'agentDays': <String, dynamic>{staleDay: 1, freshDay: 1},
          'agentSteps': <int>[1],
          'agentTokens': <int>[],
          'agentL05': <String, int>{'shown': 1, 'rogueStat': 5},
          'agentTools': <String, int>{'list_tables': 3, 'rogue_tool': 9},
          'agentLimitStops': 2,
        }),
      });

      await _service.load();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      expect(export.agentWeeks.keys, <String>[freshWeek],
          reason: '27 周前 agent 周键被裁剪');
      expect(export.agentDays.keys, <String>[freshDay],
          reason: '91 天前 agent 天键被裁剪');
      expect(export.agentL05, <String, int>{'shown': 1},
          reason: '越界 L05 键读盘拒收');
      expect(export.agentTools, <String, int>{'list_tables': 3},
          reason: '越界工具键读盘拒收');
      expect(export.agentLimitStops, 2);
    });

    test('NF6.2 静态执法：agent 桶键集合来自枚举与目录名，导出不含自由字符串入口',
        () async {
      await _service.load();

      // 唯一接受 String 的入口 recordAgentToolCall 受白名单约束（上一用例已证）；
      // 其余 agent API 只接受枚举/int——本用例锁定导出键集合的形状不变式。
      _service.recordL05Event(AgentL05Stat.values.first);
      _service.recordAgentToolCall('describe_table');
      await _service.flushForTesting();

      final Map<String, dynamic> metrics =
          _service.exportJson(appVersion: 't').toJson()['metrics']
              as Map<String, dynamic>;
      expect(
        (metrics['agentL05'] as Map<String, dynamic>).keys,
        <String>['shown'],
      );
      expect(
        (metrics['agentTools'] as Map<String, dynamic>).keys,
        <String>['describe_table'],
      );
    });
  });

  group('T31 全量收口：R14 九字段逐字段 + NF6 + schema 1/2 往返 + FIFO 聚合', () {
    test('R14 九字段逐字段核对导出 JSON（字段名与 §5.4/导出 metrics 一一对应）',
        () async {
      await _service.load();

      // R14 字段 1：agent 会话启动数（按周 + 累计）。
      _service.recordAgentSessionStart();
      _service.recordAgentSessionStart();
      _service.recordAgentSessionStart();
      // R14 字段 2：agent 触达天数（按天去重，同日重复启动不重复计）。
      _service.recordAgentActiveDay();
      _service.recordAgentActiveDay();
      // R14 字段 3：步数样本（运行结束记录）；R14 字段 8：token 消耗样本
      // （usage 缺失的 run 不计入 token 样本，第三个 run 不传 tokens）。
      _service.recordAgentRunEnd(steps: 12, tokens: 18432);
      _service.recordAgentRunEnd(steps: 25, tokens: 60110);
      _service.recordAgentRunEnd(steps: 8);
      // R14 字段 4：行动计划卡出现 / 批准 / 拒绝（计数 ×3）。
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.approved);
      _service.recordPlanEvent(AgentPlanStat.approved);
      _service.recordPlanEvent(AgentPlanStat.rejected);
      // R14 字段 5：L0.5 确认出现 / 会话放行 / 拒绝（计数 ×3）。
      for (int i = 0; i < 6; i++) {
        _service.recordL05Event(AgentL05Stat.shown);
      }
      _service.recordL05Event(AgentL05Stat.sessionAllowed);
      _service.recordL05Event(AgentL05Stat.rejected);
      _service.recordL05Event(AgentL05Stat.rejected);
      // R14 字段 6：L1 拦截（拒绝）次数。
      _service.recordL1Blocked();
      _service.recordL1Blocked();
      _service.recordL1Blocked();
      // R14 字段 7：工具调用计数（按工具名分桶；键 ⊆ 目录白名单）。
      _service.recordAgentToolCall('execute_readonly_sql');
      _service.recordAgentToolCall('execute_readonly_sql');
      _service.recordAgentToolCall('list_tables');
      _service.recordAgentToolCall('get_sample_data');
      // R14 字段 9：超限停止次数。
      _service.recordLimitStop();
      await _service.flushForTesting();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: '9.9.9+t31');
      final Map<String, dynamic> metrics =
          export.toJson()['metrics'] as Map<String, dynamic>;

      // NF6.1 字段集合执法：metrics 恰为 M1 既有五键 + R14 九字段对应九键
      // = 14 键（出清单即不验收；agentPlans/agentL1Blocked 已在 schema 3 落地）。
      expect(
        metrics.keys.toSet(),
        <String>{
          'dailyEntries',
          'weeklySessions',
          'toolCards',
          'ops',
          'aiKeyConfigured',
          'agentWeeks',
          'agentDays',
          'agentSteps',
          'agentTokens',
          'agentL05',
          'agentTools',
          'agentLimitStops',
          'agentPlans',
          'agentL1Blocked',
        },
      );

      final String thisWeek =
          WorkbenchUsageStatsService.isoWeekKey(DateTime.now());
      final String today = _dayKeyOf(DateTime.now());

      // 字段 1 → agentWeeks（按周桶）；「累计」由周桶求和派生（导出侧口径）。
      expect(metrics['agentWeeks'], <String, int>{thisWeek: 3},
          reason: 'R14 字段 1：agent 会话启动数（按周）');
      expect(
        (metrics['agentWeeks'] as Map<String, int>)
            .values
            .fold<int>(0, (int a, int b) => a + b),
        3,
        reason: 'R14 字段 1：累计 = 周桶求和',
      );
      // 字段 2 → agentDays（按天去重标记；按周视图由天键派生）。
      expect(metrics['agentDays'], <String, int>{today: 1},
          reason: 'R14 字段 2：agent 触达天数（同日去重）');
      // 字段 3 → agentSteps。
      expect(metrics['agentSteps'], <int>[12, 25, 8],
          reason: 'R14 字段 3：步数样本');
      // 字段 4 → agentPlans。
      expect(metrics['agentPlans'],
          <String, int>{'shown': 4, 'approved': 2, 'rejected': 1},
          reason: 'R14 字段 4：行动计划卡出现/批准/拒绝');
      // 字段 5 → agentL05。
      expect(metrics['agentL05'],
          <String, int>{'shown': 6, 'sessionAllowed': 1, 'rejected': 2},
          reason: 'R14 字段 5：L0.5 确认出现/会话放行/拒绝');
      // 字段 6 → agentL1Blocked。
      expect(metrics['agentL1Blocked'], 3,
          reason: 'R14 字段 6：L1 拦截（拒绝）次数');
      // 字段 7 → agentTools。
      expect(metrics['agentTools'], <String, int>{
        'execute_readonly_sql': 2,
        'list_tables': 1,
        'get_sample_data': 1,
      }, reason: 'R14 字段 7：工具调用计数（按工具名分桶）');
      // 字段 8 → agentTokens（usage 缺失的第三个 run 不计入）。
      expect(metrics['agentTokens'], <int>[18432, 60110],
          reason: 'R14 字段 8：token 消耗样本');
      // 字段 9 → agentLimitStops。
      expect(metrics['agentLimitStops'], 1,
          reason: 'R14 字段 9：超限停止次数');

      // AC14.4：导出 JSON 可解析且序列化往返不变（导出消费方兼容）。
      final Map<String, dynamic> reparsed =
          jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>;
      expect(reparsed['schema'], 3);
      expect(
        (reparsed['metrics'] as Map<String, dynamic>)['agentPlans'],
        <String, int>{'shown': 4, 'approved': 2, 'rejected': 1},
      );
      expect(
        (reparsed['metrics'] as Map<String, dynamic>)['agentL1Blocked'],
        3,
      );
    });

    test('agent 会话含敏感字面量（SQL/对话/连接名/host/PII）→ 导出与落盘均不含',
        () async {
      const String sqlLiteral =
          "SELECT * FROM agent_secret_users WHERE api_token = 'sk-live-9f8e7d6c'";
      const String chatLiteral =
          '帮我把 payment_cards 表里 card_number 明文列删掉，这是 zhang.san@corp.example 要求的';
      const String connectionNameLiteral = 'billing_primary_secret_conn';
      const String hostLiteral = '203.0.113.77:15432';
      const String piiEmailLiteral = 'zhang.san@corp.example';
      const String piiPhoneLiteral = '+86-138-0013-9000';
      const String credentialFragment = 'sk-live-9f8e7d6c';

      await _service.load();

      // 模拟一次完整 agent 会话的统计动作（与真实接线同构：runner/executor 只
      // 上报计数/枚举/白名单工具名/int 样本）。上述字面量在持有它们的作用域里
      // 发生过，但服务 API 没有任何自由字符串统计入口（NF6.2）——结构上
      // 进不了存储与导出；本用例守护该性质不被后续改动破坏。
      _service.recordAgentSessionStart();
      _service.recordAgentActiveDay();
      _service.recordAgentToolCall('list_tables');
      _service.recordAgentToolCall('describe_table');
      _service.recordAgentToolCall('execute_readonly_sql');
      _service.recordL05Event(AgentL05Stat.shown);
      _service.recordL05Event(AgentL05Stat.sessionAllowed);
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.rejected);
      _service.recordL1Blocked();
      _service.recordAgentRunEnd(steps: 6, tokens: 21504);
      _service.recordLimitStop();
      await _service.flushForTesting();

      final String exported = jsonEncode(
        _service.exportJson(appVersion: '0.0.1+1').toJson(),
      );
      for (final String literal in <String>[
        sqlLiteral,
        chatLiteral,
        connectionNameLiteral,
        hostLiteral,
        piiEmailLiteral,
        piiPhoneLiteral,
        credentialFragment,
      ]) {
        expect(exported, isNot(contains(literal)),
            reason: '导出 JSON 不得含敏感字面量');
      }
      // 凭据/敏感词根的大小写不敏感兜底扫描（键集合也不得出现此类词根）。
      expect(exported.toLowerCase(), isNot(contains('sk-live')));
      expect(exported.toLowerCase(), isNot(contains('password')));
      expect(exported.toLowerCase(), isNot(contains('secret')));

      // 落盘串同样不含（存储与导出同源白名单，纵深断言）。
      final String stored = await _storedRaw();
      for (final String literal in <String>[
        sqlLiteral,
        chatLiteral,
        connectionNameLiteral,
        hostLiteral,
        piiEmailLiteral,
        piiPhoneLiteral,
        credentialFragment,
      ]) {
        expect(stored, isNot(contains(literal)),
            reason: '落盘串不得含敏感字面量');
      }
    });

    test('schema 2 旧档全量兼容往返：读入保留 → 增量写入 → 重读完整恢复 + schema 升 3（AC14.4）',
        () async {
      final DateTime now = DateTime.now();
      final String today = _dayKeyOf(now);
      final String thisWeek = WorkbenchUsageStatsService.isoWeekKey(now);
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 2,
          'days': <String, dynamic>{today: <String, int>{'e': 4}},
          'weeks': <String, dynamic>{thisWeek: <String, int>{'s': 2}},
          'cards': <String, int>{'sqlCard': 7},
          'ops': <String, int>{'queryGen': 3},
          'aiKey': true,
          // schema 2 形态：agent 七桶齐备，无 agentPlans/agentL1Blocked（T28 前档）。
          'agentWeeks': <String, dynamic>{thisWeek: <String, int>{'starts': 5}},
          'agentDays': <String, dynamic>{today: 1},
          'agentSteps': <int>[12, 25, 8],
          'agentTokens': <int>[18432],
          'agentL05': <String, int>{'shown': 6, 'sessionAllowed': 1, 'rejected': 2},
          'agentTools': <String, int>{'list_tables': 12, 'execute_readonly_sql': 41},
          'agentLimitStops': 1,
        }),
      });

      await _service.load();

      // 读入：旧数据全保留 + schema 3 新桶零值（缺键 = 零值，加法语义）。
      WorkbenchUsageStatsExport export = _service.exportJson(appVersion: 't');
      expect(export.dailyEntries, <String, int>{today: 4});
      expect(export.weeklySessions, <String, int>{thisWeek: 2});
      expect(export.toolCards, <String, int>{'sqlCard': 7});
      expect(export.ops, <String, int>{'queryGen': 3});
      expect(export.aiKeyConfigured, isTrue);
      expect(export.agentWeeks, <String, int>{thisWeek: 5});
      expect(export.agentDays, <String, int>{today: 1});
      expect(export.agentSteps, <int>[12, 25, 8]);
      expect(export.agentTokens, <int>[18432]);
      expect(export.agentL05,
          <String, int>{'shown': 6, 'sessionAllowed': 1, 'rejected': 2});
      expect(export.agentTools,
          <String, int>{'list_tables': 12, 'execute_readonly_sql': 41});
      expect(export.agentLimitStops, 1);
      expect(export.agentPlans, <String, int>{});
      expect(export.agentL1Blocked, 0);

      // schema 3 档增量写入（字段 4/6 + 新样本）。
      _service.recordPlanEvent(AgentPlanStat.shown);
      _service.recordPlanEvent(AgentPlanStat.approved);
      _service.recordL1Blocked();
      _service.recordAgentRunEnd(steps: 30, tokens: 60110);
      await _service.flushForTesting();

      // 完整往返：reset → load → 导出 = 旧数据 + 增量，schema 升 3。
      _service.resetForTesting();
      await _service.load();
      export = _service.exportJson(appVersion: 't');
      expect(export.schema, 3);
      expect(export.dailyEntries, <String, int>{today: 4});
      expect(export.agentWeeks, <String, int>{thisWeek: 5});
      expect(export.agentDays, <String, int>{today: 1});
      expect(export.agentSteps, <int>[12, 25, 8, 30]);
      expect(export.agentTokens, <int>[18432, 60110]);
      expect(export.agentL05,
          <String, int>{'shown': 6, 'sessionAllowed': 1, 'rejected': 2});
      expect(export.agentTools,
          <String, int>{'list_tables': 12, 'execute_readonly_sql': 41});
      expect(export.agentLimitStops, 1);
      expect(export.agentPlans, <String, int>{'shown': 1, 'approved': 1});
      expect(export.agentL1Blocked, 1);

      final Map<String, dynamic> storage =
          jsonDecode(await _storedRaw()) as Map<String, dynamic>;
      expect(storage['schema'], 3);
      expect(storage['agentPlans'], <String, int>{'shown': 1, 'approved': 1});
      expect(storage['agentL1Blocked'], 1);
    });

    test('schema 1 旧档全量兼容往返：读入保留 → 增量写入 → 重读完整恢复 + schema 升 3（AC14.4）',
        () async {
      final DateTime now = DateTime.now();
      final String today = _dayKeyOf(now);
      final String thisWeek = WorkbenchUsageStatsService.isoWeekKey(now);
      SharedPreferences.setMockInitialValues(<String, Object>{
        _statsPrefsKey: jsonEncode(<String, dynamic>{
          'schema': 1,
          'days': <String, dynamic>{today: <String, int>{'e': 4}},
          'weeks': <String, dynamic>{thisWeek: <String, int>{'s': 2}},
          'cards': <String, int>{'sqlCard': 7},
          'ops': <String, int>{'queryGen': 3},
          'aiKey': true,
          // schema 1 形态：无任何 agent 键（T08 之前）。
        }),
      });

      await _service.load();

      // 读入：旧数据全保留 + 全部 agent 桶零值（含 schema 3 两桶）。
      WorkbenchUsageStatsExport export = _service.exportJson(appVersion: 't');
      expect(export.dailyEntries, <String, int>{today: 4});
      expect(export.weeklySessions, <String, int>{thisWeek: 2});
      expect(export.toolCards, <String, int>{'sqlCard': 7});
      expect(export.ops, <String, int>{'queryGen': 3});
      expect(export.aiKeyConfigured, isTrue);
      expect(export.agentWeeks, <String, int>{});
      expect(export.agentDays, <String, int>{});
      expect(export.agentSteps, <int>[]);
      expect(export.agentTokens, <int>[]);
      expect(export.agentL05, <String, int>{});
      expect(export.agentTools, <String, int>{});
      expect(export.agentLimitStops, 0);
      expect(export.agentPlans, <String, int>{});
      expect(export.agentL1Blocked, 0);

      // 增量写入九字段代表事件。
      _service.recordAgentSessionStart();
      _service.recordAgentActiveDay();
      _service.recordAgentRunEnd(steps: 9, tokens: 1234);
      _service.recordL05Event(AgentL05Stat.sessionAllowed);
      _service.recordAgentToolCall('explain_plan');
      _service.recordPlanEvent(AgentPlanStat.rejected);
      _service.recordL1Blocked();
      _service.recordLimitStop();
      await _service.flushForTesting();

      // 完整往返：reset → load → 导出 = 旧数据 + 全部增量，schema 升 3。
      _service.resetForTesting();
      await _service.load();
      export = _service.exportJson(appVersion: 't');
      expect(export.schema, 3);
      expect(export.dailyEntries, <String, int>{today: 4});
      expect(export.weeklySessions, <String, int>{thisWeek: 2});
      expect(export.toolCards, <String, int>{'sqlCard': 7});
      expect(export.ops, <String, int>{'queryGen': 3});
      expect(export.aiKeyConfigured, isTrue);
      expect(export.agentWeeks, <String, int>{thisWeek: 1});
      expect(export.agentDays, <String, int>{today: 1});
      expect(export.agentSteps, <int>[9]);
      expect(export.agentTokens, <int>[1234]);
      expect(export.agentL05, <String, int>{'sessionAllowed': 1});
      expect(export.agentTools, <String, int>{'explain_plan': 1});
      expect(export.agentLimitStops, 1);
      expect(export.agentPlans, <String, int>{'rejected': 1});
      expect(export.agentL1Blocked, 1);
    });

    test('FIFO 500 上限与导出聚合（步数/token 中位数与累计）正确性', () async {
      // 阶段 1：600 次运行 → FIFO 裁剪到 500 → 导出消费侧聚合仍正确。
      await _service.load();
      for (int i = 0; i < 600; i++) {
        _service.recordAgentRunEnd(steps: i); // 步数样本 0..599
        // steps 传负值（走拒收路径）以免污染步数样本，单独压 token FIFO。
        _service.recordAgentRunEnd(steps: -1, tokens: i); // token 样本 0..599
      }
      await _service.flushForTesting();

      final WorkbenchUsageStatsExport export =
          _service.exportJson(appVersion: 't');
      // FIFO 上限：恰 500 条，丢最旧（0..99），新样本在尾。
      expect(export.agentSteps.length, 500, reason: '步数样本 FIFO ≤ 500');
      expect(export.agentSteps.first, 100, reason: '最旧 100 条（0..99）被丢弃');
      expect(export.agentSteps.last, 599);
      expect(export.agentTokens.length, 500, reason: 'token 样本 FIFO ≤ 500');
      expect(export.agentTokens.first, 100);
      expect(export.agentTokens.last, 599);

      // R14 字段 3/8 的「导出时聚合中位数 / token 累计」在导出消费侧执行
      // （design-ai-agent §5.4 导出结构只含原始样本数组；T31 约束「不新增
      // 字段」禁止加聚合键）。本断言验证 FIFO 裁剪后的样本链支撑正确聚合。
      final Map<String, dynamic> metrics =
          export.toJson()['metrics'] as Map<String, dynamic>;
      final List<int> steps =
          (metrics['agentSteps'] as List<dynamic>).cast<int>();
      final List<int> tokens =
          (metrics['agentTokens'] as List<dynamic>).cast<int>();
      expect(_medianOf(steps), 349.5,
          reason: '保留窗 100..599 的步数中位数 = (349+350)/2');
      expect(_medianOf(tokens), 349.5,
          reason: '保留窗 100..599 的 token 中位数 = (349+350)/2');
      expect(
        tokens.fold<int>(0, (int a, int b) => a + b),
        174750,
        reason: 'token 累计 = Σ(100..599) = 174750',
      );

      // 阶段 2：小样本（奇数中位数）+ usage 缺失不计入 token 聚合（AC3.4 同源）。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _service.resetForTesting();
      await _service.load();
      _service.recordAgentRunEnd(steps: 8, tokens: 18432);
      _service.recordAgentRunEnd(steps: 12); // tokens null → 不进 token 样本
      _service.recordAgentRunEnd(steps: 25, tokens: 60110);
      await _service.flushForTesting();

      final WorkbenchUsageStatsExport export2 =
          _service.exportJson(appVersion: 't');
      expect(export2.agentSteps, <int>[8, 12, 25]);
      expect(_medianOf(export2.agentSteps), 12.0,
          reason: '奇数样本取中位');
      expect(export2.agentTokens, <int>[18432, 60110],
          reason: 'usage 缺失的 run 不计入 token 样本');
      expect(_medianOf(export2.agentTokens), 39271.0,
          reason: '偶数 token 样本取中间两值均值');
    });
  });
}
