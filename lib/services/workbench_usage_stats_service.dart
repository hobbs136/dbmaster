//! 本地使用统计服务（AI 工作台，R8 / design-ai-workbench §4.5 + §5.3 + §6.4）。
//!
//! 纯本地、全程零网络（AC8.4/AC8.5）：SharedPreferences key `workbench_stats_v1`，
//! imports 白名单 = dart:convert（核心库，prefs JSON 编解码用）+ flutter/foundation
//! + shared_preferences；禁止 http/socket/dio 等任何网络库——由
//! test/services/workbench_usage_stats_service_test.dart 读取本文件源码静态断言。
//!
//! 隐私契约（NF2.1 白名单执法）：存储与导出的键集合编译期固定——按天/按周键由
//! 日期与 ISO 周生成器产生，分桶键只能来自 [WorkbenchCardKindStat] 与
//! [WorkbenchOpClass] 两个枚举的 name（读盘时同样拒收越界键）。API 不接受任何
//! 自由字符串，凭据/连接名/SQL 文本结构上进不了存储与导出（AC8.2）。
//!
//! agent 扩展（design-ai-agent §4.7/§5.4，存储 schema 1→2，T08）：键源同上——
//! L0.5 桶键来自 [AgentL05Stat] 枚举；工具分桶键为 AgentToolCatalog 编译期固定
//! 目录名的镜像常量（本文件 imports 白名单禁止直接 import catalog，见
//! [_agentToolKeyWhitelist] 注释）；步数/token 样本只存 int（FIFO ≤ 500）。
//! 无任何自由字符串统计入口（NF6.1/NF6.2），无「关闭统计」旁路。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工具卡类型分桶（R8 字段 3）。枚举即白名单——无自由字符串键。
enum WorkbenchCardKindStat { sqlCard, resultCard }

/// 操作粗分类（R8 字段 4）。
///
/// 映射规则：[WorkbenchOpClass.queryGen]=只读 SQL 执行；
/// [WorkbenchOpClass.ddlPerm]=DDL 确认后执行；[WorkbenchOpClass.bulkMaint]=DML 写执行。
enum WorkbenchOpClass { queryGen, ddlPerm, bulkMaint }

/// L0.5 确认卡事件分桶（R14 字段 5，design-ai-agent §4.7）。
/// 枚举即白名单——无自由字符串键。
enum AgentL05Stat { shown, sessionAllowed, rejected }

/// 行动计划事件分桶（R14 字段 4，design-ai-agent §4.7 recordPlanEvent；
/// T28 落地）。枚举即白名单；值集 = T22 `AgentPlanStatEvent`（shown/
/// approved/rejected）按 name 桥接（agent_plan.dart 桥接说明——两处枚举
/// 值需同步，评审对照项）。
enum AgentPlanStat { shown, approved, rejected }

/// 本地使用统计（R8）。单例，无网络——service 层纯逻辑，不接 Provider、不发请求。
///
/// 生命周期：启动时 [load] 一次（main.dart `unawaited` 接线，fire-and-forget）；
/// 写方法写内存 + 写穿落盘（计数频率低，写穿可接受）；测试用
/// [resetForTesting] 复位、[flushForTesting] 等待挂起写盘。
class WorkbenchUsageStatsService {
  static final WorkbenchUsageStatsService instance =
      WorkbenchUsageStatsService._();
  WorkbenchUsageStatsService._();
  factory WorkbenchUsageStatsService() => instance;

  static const String _prefsKey = 'workbench_stats_v1';

  /// 存储结构版本号（C-4：新字段走加法递增，只加不删）。
  /// 2 = agent 七桶 + 样本 FIFO（design-ai-agent §5.4，T08）。
  /// 3 = 追加 agentPlans 三计数 + agentL1Blocked（R14 字段 4/6，T28）。
  static const int _storageSchema = 3;

  /// 按天桶滚动保留天数（含当天；越界键在 [load] 时删除）。
  static const int _daysRetention = 90;

  /// 按周桶滚动保留周数（含当前周；ISO 周键 `YYYY-Www`，越界键在 [load] 时删除）。
  static const int _weeksRetention = 26;

  /// 步数/token 样本 FIFO 上限（design-ai-agent D14：防 prefs 膨胀，
  /// 导出中位数精度足够；超限丢最旧）。
  static const int _agentSampleCap = 500;

  // ── 内存态（与 §5.3 存储结构一一对应）──
  // Map 值全为单调递增计数：load 合并时取 max，晚到的读盘不会回退已发生的记录。
  final Map<String, int> _dailyEntries = <String, int>{}; // 'YYYY-MM-DD' → 进入次数
  final Map<String, int> _weeklySessions = <String, int>{}; // 'YYYY-Www' → 新建会话数
  final Map<String, int> _cards = <String, int>{}; // WorkbenchCardKindStat.name → 次数
  final Map<String, int> _ops = <String, int>{}; // WorkbenchOpClass.name → 次数
  bool _aiKeyConfigured = false;

  // ── agent 桶内存态（design-ai-agent §5.4 schema 2，加法）──
  final Map<String, int> _agentWeeklyStarts = <String, int>{}; // 'YYYY-Www' → 启动数
  final Map<String, int> _agentActiveDays = <String, int>{}; // 'YYYY-MM-DD' → 1（触达标记）
  final List<int> _agentStepSamples = <int>[]; // R14 字段3 步数样本，FIFO ≤ 500
  final List<int> _agentTokenSamples = <int>[]; // R14 字段8 token 样本，FIFO ≤ 500
  final Map<String, int> _agentL05 = <String, int>{}; // AgentL05Stat.name → 次数
  final Map<String, int> _agentTools = <String, int>{}; // 目录工具名 → 次数
  int _agentLimitStops = 0; // R14 字段9 超限停止累计
  final Map<String, int> _agentPlans = <String, int>{}; // AgentPlanStat.name → 次数（T28）
  int _agentL1Blocked = 0; // R14 字段6 L1 撞门拒绝累计（T28）

  /// 启动读盘（幂等，重复调用返回同一 future）。
  Future<void>? _loadFuture;

  /// 串行化写盘链的尾部（测试经 [flushForTesting] 等待）。
  Future<void>? _pendingWrite;

  static final RegExp _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final Set<String> _cardKeyWhitelist = WorkbenchCardKindStat.values
      .map((WorkbenchCardKindStat kind) => kind.name)
      .toSet();
  static final Set<String> _opKeyWhitelist = WorkbenchOpClass.values
      .map((WorkbenchOpClass op) => op.name)
      .toSet();
  static final Set<String> _agentL05KeyWhitelist = AgentL05Stat.values
      .map((AgentL05Stat stat) => stat.name)
      .toSet();
  static final Set<String> _agentPlanKeyWhitelist = AgentPlanStat.values
      .map((AgentPlanStat stat) => stat.name)
      .toSet();

  /// 工具分桶键白名单 = AgentToolCatalog 的 14 个编译期固定目录名
  /// （design-ai-agent §4.1，FC-6 无运行时注册；NF6.1「目录名即白名单」）。
  /// 本文件 imports 白名单禁止直接 import catalog（M1 T05 零网络先例），
  /// 此处编译期常量镜像；catalog 侧工具名变更时必须同步本清单（评审对照项）。
  static const Set<String> _agentToolKeyWhitelist = <String>{
    // A1 六工具（数据 5 + 上下文 1）
    'execute_readonly_sql',
    'list_tables',
    'describe_table',
    'get_sample_data',
    'explain_plan',
    'get_current_context',
    // A2 八工具（计划 1 + 界面 5 + 跨经典 2）
    'submit_action_plan',
    'open_result_grid',
    'show_table_structure',
    'open_sql_editor',
    'render_chart',
    'pin_artifact',
    'open_in_classic',
    'focus_sidebar',
  };

  // ── 生命周期 ──

  /// 启动读盘 + 滚动裁剪（越界键删除后写回）。永不抛出——统计是旁路数据，
  /// 读盘/裁剪失败静默降级为空态，绝不阻塞启动序列。
  Future<void> load() => _loadFuture ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _mergeStorage(raw);
      }
      if (raw != null && _trimRetention(DateTime.now())) {
        await _writeNow();
      }
    } catch (_) {
      // best-effort：prefs 不可用或数据损坏时保持空态，不上抛（无网络、无重试）。
    }
  }

  // ── 写方法（五个，全部枚举/生成器键，NF2.1）──

  /// 字段 1：进入工作台（按天桶 `days[today].e`）。
  void recordEntry() => _bump(_dailyEntries, _dayKey(DateTime.now()));

  /// 字段 2：工作台内新建会话（按周桶 `weeks[thisWeek].s`）。
  void recordSession() => _bump(_weeklySessions, isoWeekKey(DateTime.now()));

  /// 字段 3：工具卡调用（累计，按类型分桶）。
  void recordCard(WorkbenchCardKindStat kind) => _bump(_cards, kind.name);

  /// 字段 4：操作粗分类（累计，三档）。
  void recordOp(WorkbenchOpClass op) => _bump(_ops, op.name);

  /// 字段 5：AI key 配置布尔（AiConfigProvider 状态变化的投影）。
  /// 单向置位（§6.4）：`true` 写入后不可逆，`false` 不回落已置位的状态。
  void setAiKeyConfigured(bool configured) {
    if (!configured || _aiKeyConfigured) return;
    _aiKeyConfigured = true;
    _schedulePersist();
  }

  // ── agent 写方法（design-ai-agent §4.7，T08 + T28 字段 4/6）──

  /// R14 字段 1：agent 会话启动（按周桶 `agentWeeks[thisWeek].starts`）。
  /// 累计由导出侧对周桶求和派生——与 M1 weeklySessions 同语义（26 周滚动窗口）。
  void recordAgentSessionStart() =>
      _bump(_agentWeeklyStarts, isoWeekKey(DateTime.now()));

  /// R14 字段 2：agent 触达天（按天去重：`agentDays[today] = 1`，
  /// 同日重复启动不重复计）。
  void recordAgentActiveDay() {
    final String key = _dayKey(DateTime.now());
    if (_agentActiveDays.containsKey(key)) return;
    _agentActiveDays[key] = 1;
    _schedulePersist();
  }

  /// R14 字段 3/8：运行结束样本。步数必记；token 在 usage 缺失时为 null
  /// （与 AC3.4「—」降级同源），null 或负值不进样本。样本只存 int（NF6.2），
  /// FIFO ≤ [_agentSampleCap] 超限丢最旧。
  void recordAgentRunEnd({required int steps, int? tokens}) {
    bool changed = false;
    if (steps >= 0) {
      _appendSample(_agentStepSamples, steps);
      changed = true;
    }
    if (tokens != null && tokens >= 0) {
      _appendSample(_agentTokenSamples, tokens);
      changed = true;
    }
    if (changed) _schedulePersist();
  }

  /// R14 字段 5：L0.5 确认卡事件（shown/sessionAllowed/rejected ×3 计数）。
  void recordL05Event(AgentL05Stat event) => _bump(_agentL05, event.name);

  /// R14 字段 7：工具调用计数（按工具名分桶）。
  /// 白名单执法（NF6.1）：[toolName] 只接受 AgentToolCatalog 编译期固定目录名
  /// （镜像见 [_agentToolKeyWhitelist]）；目录外名字静默拒收——统计是旁路
  /// 数据，绝不抛出。
  void recordAgentToolCall(String toolName) {
    if (!_agentToolKeyWhitelist.contains(toolName)) return;
    _bump(_agentTools, toolName);
  }

  /// R14 字段 9：步数上限触发的超限停止次数（累计）。
  void recordLimitStop() {
    _agentLimitStops += 1;
    _schedulePersist();
  }

  /// R14 字段 4：行动计划事件计数（shown/approved/rejected ×3 分桶，
  /// T28）。值集与 T22 `AgentPlanStatEvent` 同步（[AgentPlanStat] 注释）。
  void recordPlanEvent(AgentPlanStat event) => _bump(_agentPlans, event.name);

  /// R14 字段 6：L1 撞门拒绝累计（风险 1 观测——计划在 L1 门被拒的次数，
  /// 观测模型撞门率；T28）。
  void recordL1Blocked() {
    _agentL1Blocked += 1;
    _schedulePersist();
  }

  /// 导出 JSON schema 对象（AC8.1/8.2 逐字段核对对象；设置页导出入口消费，
  /// T14）。导出 = 内存态浅拷贝重排 + appVersion/exportedAt，不触发落盘。
  WorkbenchUsageStatsExport exportJson({required String appVersion}) {
    return WorkbenchUsageStatsExport(
      schema: _storageSchema,
      appVersion: appVersion,
      exportedAt: DateTime.now().toUtc(),
      dailyEntries: Map<String, int>.unmodifiable(_dailyEntries),
      weeklySessions: Map<String, int>.unmodifiable(_weeklySessions),
      toolCards: Map<String, int>.unmodifiable(_cards),
      ops: Map<String, int>.unmodifiable(_ops),
      aiKeyConfigured: _aiKeyConfigured,
      agentWeeks: Map<String, int>.unmodifiable(_agentWeeklyStarts),
      agentDays: Map<String, int>.unmodifiable(_agentActiveDays),
      agentSteps: List<int>.unmodifiable(_agentStepSamples),
      agentTokens: List<int>.unmodifiable(_agentTokenSamples),
      agentL05: Map<String, int>.unmodifiable(_agentL05),
      agentTools: Map<String, int>.unmodifiable(_agentTools),
      agentLimitStops: _agentLimitStops,
      agentPlans: Map<String, int>.unmodifiable(_agentPlans),
      agentL1Blocked: _agentL1Blocked,
    );
  }

  // ── 计数与持久化 ──

  void _bump(Map<String, int> bucket, String key) {
    bucket[key] = (bucket[key] ?? 0) + 1;
    _schedulePersist();
  }

  /// 样本 FIFO 追加（design-ai-agent D14）：只存 int，超 [_agentSampleCap]
  /// 从头部丢最旧。
  void _appendSample(List<int> samples, int value) {
    samples.add(value);
    if (samples.length > _agentSampleCap) {
      samples.removeRange(0, samples.length - _agentSampleCap);
    }
  }

  /// 写穿策略：计数频率低，直接落全量快照；串行链保证后写不覆盖前写。
  void _schedulePersist() {
    final Future<void> previous =
        _pendingWrite ?? Future<void>.value();
    _pendingWrite = _writeAfter(previous);
  }

  Future<void> _writeAfter(Future<void> previous) async {
    try {
      await previous;
      final Future<void>? loadFuture = _loadFuture;
      if (loadFuture != null) {
        await loadFuture; // 启动竞态：先等读盘+裁剪完成，再覆盖写全量快照
      }
      await _writeNow();
    } catch (_) {
      // best-effort：落盘失败不影响内存计数，下次写方法触发时重试。
    }
  }

  Future<void> _writeNow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_storageJson()));
  }

  Map<String, dynamic> _storageJson() => <String, dynamic>{
        'schema': _storageSchema,
        'days': <String, dynamic>{
          for (final MapEntry<String, int> e in _dailyEntries.entries)
            e.key: <String, int>{'e': e.value},
        },
        'weeks': <String, dynamic>{
          for (final MapEntry<String, int> e in _weeklySessions.entries)
            e.key: <String, int>{'s': e.value},
        },
        'cards': Map<String, int>.of(_cards),
        'ops': Map<String, int>.of(_ops),
        'aiKey': _aiKeyConfigured,
        // agent 桶（design-ai-agent §5.4；agentPlans/agentL1Blocked = T28 schema 3）
        'agentWeeks': <String, dynamic>{
          for (final MapEntry<String, int> e in _agentWeeklyStarts.entries)
            e.key: <String, int>{'starts': e.value},
        },
        'agentDays': Map<String, int>.of(_agentActiveDays),
        'agentSteps': List<int>.of(_agentStepSamples),
        'agentTokens': List<int>.of(_agentTokenSamples),
        'agentL05': Map<String, int>.of(_agentL05),
        'agentTools': Map<String, int>.of(_agentTools),
        'agentLimitStops': _agentLimitStops,
        'agentPlans': Map<String, int>.of(_agentPlans),
        'agentL1Blocked': _agentL1Blocked,
      };

  // ── 读盘合并与滚动裁剪 ──

  /// 解析存储串合并进内存态。防御式解析：损坏 JSON / 越界键一律拒收
  /// （白名单执法延伸到读盘——NF2.1）；计数取 max，单调不回退。
  void _mergeStorage(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // 损坏数据：按空态处理
    }
    if (decoded is! Map) return;

    final Object? days = decoded['days'];
    if (days is Map) {
      days.forEach((Object? key, Object? value) {
        if (key is String &&
            _dayKeyPattern.hasMatch(key) &&
            DateTime.tryParse(key) != null &&
            value is Map) {
          final Object? count = value['e'];
          if (count is int && count > 0) {
            _mergeCount(_dailyEntries, key, count);
          }
        }
      });
    }

    final Object? weeks = decoded['weeks'];
    if (weeks is Map) {
      weeks.forEach((Object? key, Object? value) {
        if (key is String && _isWeekKey(key) && value is Map) {
          final Object? count = value['s'];
          if (count is int && count > 0) {
            _mergeCount(_weeklySessions, key, count);
          }
        }
      });
    }

    final Object? cards = decoded['cards'];
    if (cards is Map) {
      cards.forEach((Object? key, Object? value) {
        if (key is String && _cardKeyWhitelist.contains(key)) {
          _mergeCount(_cards, key, value);
        }
      });
    }

    final Object? ops = decoded['ops'];
    if (ops is Map) {
      ops.forEach((Object? key, Object? value) {
        if (key is String && _opKeyWhitelist.contains(key)) {
          _mergeCount(_ops, key, value);
        }
      });
    }

    final Object? aiKey = decoded['aiKey'];
    if (aiKey is bool && aiKey) {
      _aiKeyConfigured = true;
    }

    // agent 桶合并（缺键 = 零值，AC14.4 加法语义；白名单执法延伸到读盘）。
    final Object? agentWeeks = decoded['agentWeeks'];
    if (agentWeeks is Map) {
      agentWeeks.forEach((Object? key, Object? value) {
        if (key is String && _isWeekKey(key) && value is Map) {
          _mergeCount(_agentWeeklyStarts, key, value['starts']);
        }
      });
    }

    final Object? agentDays = decoded['agentDays'];
    if (agentDays is Map) {
      agentDays.forEach((Object? key, Object? value) {
        if (key is String &&
            _dayKeyPattern.hasMatch(key) &&
            DateTime.tryParse(key) != null) {
          _mergeCount(_agentActiveDays, key, value);
        }
      });
    }

    _mergeSamples(_agentStepSamples, decoded['agentSteps']);
    _mergeSamples(_agentTokenSamples, decoded['agentTokens']);

    final Object? agentL05 = decoded['agentL05'];
    if (agentL05 is Map) {
      agentL05.forEach((Object? key, Object? value) {
        if (key is String && _agentL05KeyWhitelist.contains(key)) {
          _mergeCount(_agentL05, key, value);
        }
      });
    }

    final Object? agentTools = decoded['agentTools'];
    if (agentTools is Map) {
      agentTools.forEach((Object? key, Object? value) {
        if (key is String && _agentToolKeyWhitelist.contains(key)) {
          _mergeCount(_agentTools, key, value);
        }
      });
    }

    final Object? agentLimitStops = decoded['agentLimitStops'];
    if (agentLimitStops is int &&
        agentLimitStops > 0 &&
        agentLimitStops > _agentLimitStops) {
      _agentLimitStops = agentLimitStops;
    }

    // T28 schema 3 桶合并（缺键 = 零值，AC14.4 加法语义；白名单执法同上）。
    final Object? agentPlans = decoded['agentPlans'];
    if (agentPlans is Map) {
      agentPlans.forEach((Object? key, Object? value) {
        if (key is String && _agentPlanKeyWhitelist.contains(key)) {
          _mergeCount(_agentPlans, key, value);
        }
      });
    }

    final Object? agentL1Blocked = decoded['agentL1Blocked'];
    if (agentL1Blocked is int &&
        agentL1Blocked > 0 &&
        agentL1Blocked > _agentL1Blocked) {
      _agentL1Blocked = agentL1Blocked;
    }
  }

  /// 单调合并：仅当盘上计数更大时写入，晚到的读盘不回退已发生的记录。
  void _mergeCount(Map<String, int> bucket, String key, Object? count) {
    if (count is int && count > 0 && count > (bucket[key] ?? 0)) {
      bucket[key] = count;
    }
  }

  /// 样本列表合并：存储值必须为全 int 列表（NF6.2），否则整组拒收。
  /// 罕见竞态（写方法先于启动读盘完成）下盘上样本更旧、内存样本更新——
  /// 拼接后保留尾部 [_agentSampleCap] 条（FIFO 新样本在尾，语义不变）。
  void _mergeSamples(List<int> memory, Object? stored) {
    if (stored is! List) return;
    final bool allInt = stored.every((Object? element) => element is int);
    if (!allInt) return;
    final List<int> merged = <int>[...stored.cast<int>(), ...memory];
    final List<int> capped = merged.length > _agentSampleCap
        ? merged.sublist(merged.length - _agentSampleCap)
        : merged;
    memory
      ..clear()
      ..addAll(capped);
  }

  /// ISO 周键形状校验（`YYYY-Www`，周号两位零填充，保证字典序 == 时间序）。
  static bool _isWeekKey(String key) {
    if (key.length != 8) return false;
    if (!RegExp(r'^\d{4}-W\d{2}$').hasMatch(key)) return false;
    final int? year = int.tryParse(key.substring(0, 4));
    final int? week = int.tryParse(key.substring(6, 8));
    return year != null && week != null && week >= 1 && week <= 53;
  }

  /// 裁剪越界桶：按天保留最近 [_daysRetention] 天、按周保留最近
  /// [_weeksRetention] 周（均含当前；agent 天/周桶沿用同一窗口——同一
  /// prefs 膨胀防线）。返回是否删除过键（决定是否写回）。
  bool _trimRetention(DateTime now) {
    final int before = _dailyEntries.length +
        _weeklySessions.length +
        _agentActiveDays.length +
        _agentWeeklyStarts.length;

    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime oldestKeptDay =
        today.subtract(Duration(days: _daysRetention - 1));
    void trimDays(Map<String, int> bucket) {
      bucket.removeWhere((String key, int _) {
        final DateTime? date = DateTime.tryParse(key);
        return date == null || date.isBefore(oldestKeptDay);
      });
    }

    trimDays(_dailyEntries);
    trimDays(_agentActiveDays);

    final String oldestKeptWeek = isoWeekKey(
      today.subtract(Duration(days: 7 * (_weeksRetention - 1))),
    );
    void trimWeeks(Map<String, int> bucket) {
      bucket.removeWhere(
        (String key, int _) => key.compareTo(oldestKeptWeek) < 0,
      );
    }

    trimWeeks(_weeklySessions);
    trimWeeks(_agentWeeklyStarts);

    return _dailyEntries.length +
            _weeklySessions.length +
            _agentActiveDays.length +
            _agentWeeklyStarts.length !=
        before;
  }

  // ── 键生成器（编译期固定键集合的两个来源）──

  /// 本地日期键 `YYYY-MM-DD`（按天桶）。
  static String _dayKey(DateTime time) {
    final String month = time.month.toString().padLeft(2, '0');
    final String day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  /// ISO 8601 周键 `YYYY-Www`（周一起始，W1 含当年第一个周四；年份取该周
  /// 周四所在年份）。周号两位零填充，键的字典序 == 时间序，可直接比较裁剪。
  @visibleForTesting
  static String isoWeekKey(DateTime time) {
    final DateTime date = DateTime(time.year, time.month, time.day);
    final DateTime thursday =
        date.add(Duration(days: DateTime.thursday - date.weekday));
    final DateTime yearStart = DateTime(thursday.year, 1, 1);
    final int week = thursday.difference(yearStart).inDays ~/ 7 + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  // ── 测试钩子 ──

  /// 测试专用：等待挂起写盘链尾部落定，保证断言时 prefs 已写入。
  @visibleForTesting
  Future<void> flushForTesting() =>
      _pendingWrite ?? Future<void>.value();

  /// 重置全部内存态与挂起 future（不清理 prefs——由测试经
  /// SharedPreferences.setMockInitialValues 掌控存储内容）。
  @visibleForTesting
  void resetForTesting() {
    _dailyEntries.clear();
    _weeklySessions.clear();
    _cards.clear();
    _ops.clear();
    _aiKeyConfigured = false;
    _agentWeeklyStarts.clear();
    _agentActiveDays.clear();
    _agentStepSamples.clear();
    _agentTokenSamples.clear();
    _agentL05.clear();
    _agentTools.clear();
    _agentLimitStops = 0;
    _agentPlans.clear();
    _agentL1Blocked = 0;
    _loadFuture = null;
    _pendingWrite = null;
  }
}

/// 导出 JSON schema 对象（AC8.1/AC8.2 + R14 AC14.1 逐字段核对对象）。
///
/// ```
/// {
///   "schema": 3,                        // 结构版本号（C-4：新字段加法递增）
///   "appVersion": "0.3.0",
///   "exportedAt": "2026-09-22T00:00:00.000Z",
///   "metrics": {
///     "dailyEntries":   {"2026-09-20": 3},  // 按天：进入次数
///     "weeklySessions": {"2026-W38": 2},    // 按周：会话数
///     "toolCards":      {"sqlCard": 12, "resultCard": 8},
///     "ops":            {"queryGen": 5, "ddlPerm": 1, "bulkMaint": 0},
///     "aiKeyConfigured": true,
///     // agent 七桶（design-ai-agent §5.4；agentWeeks 沿 M1 导出惯例
///     // 拍平内层包装，{周键: 启动数}；字段 4/6 归 T28）
///     "agentWeeks":     {"2026-W39": 3},
///     "agentDays":      {"2026-09-23": 1},
///     "agentSteps":     [12, 25, 8],        // FIFO ≤ 500
///     "agentTokens":    [18432, 60110],     // FIFO ≤ 500
///     "agentL05":       {"shown": 6, "sessionAllowed": 1, "rejected": 2},
///     "agentTools":     {"execute_readonly_sql": 41, "list_tables": 12},
///     "agentLimitStops": 1,
///     // T28 两键（R14 字段 4/6；metrics 共 14 键）
///     "agentPlans":     {"shown": 3, "approved": 2, "rejected": 1},
///     "agentL1Blocked": 1
///   }
/// }
/// ```
@immutable
class WorkbenchUsageStatsExport {
  const WorkbenchUsageStatsExport({
    required this.schema,
    required this.appVersion,
    required this.exportedAt,
    required this.dailyEntries,
    required this.weeklySessions,
    required this.toolCards,
    required this.ops,
    required this.aiKeyConfigured,
    required this.agentWeeks,
    required this.agentDays,
    required this.agentSteps,
    required this.agentTokens,
    required this.agentL05,
    required this.agentTools,
    required this.agentLimitStops,
    required this.agentPlans,
    required this.agentL1Blocked,
  });

  /// 结构版本号。
  final int schema;

  /// 导出时的应用版本（由调用方传入）。
  final String appVersion;

  /// 导出时刻（UTC）。
  final DateTime exportedAt;

  /// 按天进入次数：`YYYY-MM-DD` → count。
  final Map<String, int> dailyEntries;

  /// 按周新建会话数：`YYYY-Www` → count。
  final Map<String, int> weeklySessions;

  /// 工具卡调用累计（按类型分桶）。
  final Map<String, int> toolCards;

  /// 操作粗分类累计（三档）。
  final Map<String, int> ops;

  /// AI key 是否配置过（单向置位）。
  final bool aiKeyConfigured;

  /// R14 字段 1：agent 会话启动数（按周）：`YYYY-Www` → count（累计由求和派生）。
  final Map<String, int> agentWeeks;

  /// R14 字段 2：agent 触达天：`YYYY-MM-DD` → 1。
  final Map<String, int> agentDays;

  /// R14 字段 3：步数样本（FIFO ≤ 500，导出侧聚合中位数）。
  final List<int> agentSteps;

  /// R14 字段 8：token 消耗样本（FIFO ≤ 500，导出侧聚合中位数与累计）。
  final List<int> agentTokens;

  /// R14 字段 5：L0.5 确认事件计数（shown/sessionAllowed/rejected）。
  final Map<String, int> agentL05;

  /// R14 字段 7：工具调用计数（按目录工具名分桶）。
  final Map<String, int> agentTools;

  /// R14 字段 9：超限停止次数累计。
  final int agentLimitStops;

  /// R14 字段 4：行动计划事件计数（shown/approved/rejected；T28）。
  final Map<String, int> agentPlans;

  /// R14 字段 6：L1 撞门拒绝次数累计（T28）。
  final int agentL1Blocked;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schema,
        'appVersion': appVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'metrics': <String, dynamic>{
          'dailyEntries': dailyEntries,
          'weeklySessions': weeklySessions,
          'toolCards': toolCards,
          'ops': ops,
          'aiKeyConfigured': aiKeyConfigured,
          'agentWeeks': agentWeeks,
          'agentDays': agentDays,
          'agentSteps': agentSteps,
          'agentTokens': agentTokens,
          'agentL05': agentL05,
          'agentTools': agentTools,
          'agentLimitStops': agentLimitStops,
          'agentPlans': agentPlans,
          'agentL1Blocked': agentL1Blocked,
        },
      };
}
