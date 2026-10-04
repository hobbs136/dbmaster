// ============================================================================
// AI 会话导出入口 UI widget 测试（AI-SEX 批 T3，AI-SEX-101~106）。
//
// 覆盖（登记 docs/test/unified_test_spec.md §6.13）：
// - AI-SEX-101 会话条目弹出菜单含「导出会话」项（rename 之后、delete 之前）；
// - AI-SEX-102 导出对话框出现 + 复选框默认勾选、可切换；
// - AI-SEX-103 取消对话框 = 零副作用（无选择器调用 / 无文件写 / 无审计 /
//   无 snackbar）；
// - AI-SEX-104 注入 savePathPicker 完整保存流（落盘 / 信封 format+version /
//   成功 snackbar / 审计 format='ai_session_json' rowCount=消息数）+ 去勾
//   轻量模式（options.includeToolResultData=false 且非 agent
//   toolResultData=null）；
// - AI-SEX-105 注入 picker 抛错 → 错误 snackbar，文案经 redactSecrets 脱敏；
// - AI-SEX-106 两会话并存导出非当前会话 → currentSession 不变、落盘为
//   目标会话；
// - AI-SEX-107 确认对话框后取消文件选择（picker 返回 null）→ 选择器已调用
//   一次但零审计、零文件写、零 snackbar。
//
// FilePicker 平台插件 widget 测试不 mock——AI-SEX-101/102 走真实菜单入口，
// 103~107 直调同一顶层入口注入接缝 fake（先例 attach_database_dialog_test
// 的注入思路）。
//
// ⚠ 平台事实（2026-09-28 探针验证，Windows flutter_tester）：fake async
// 测试体内发起的 dart:io 真实文件 IO，其 future 永不完成——runAsync 窗口内
// IO 系统调用会真实执行（文件确实落盘、内容完整可读），但 future 完成事件
// 永不派发，因此写盘之后的反馈链路（snackbar/审计）在纯 fake async 内不可达
// （fixed-delay 与轮询两种 runAsync 窗口均验证无效）。这与仓库既有惯例一致
// （export_service.dart 刻意拆出纯函数「避免依赖 FilePicker / 文件系统」）。
// 据此本文件分两种落盘断言机制：
// - AI-SEX-104 全链路（含 snackbar/审计）：dart:io IOOverrides.createFile
//   接缝把 File.writeAsString 截获进进程内捕获（_MemoryFiles）——生产代码
//   零改动、任务书接口零改动；
// - AI-SEX-106 落盘内容：真实磁盘（syscall 真实发生，文件内容可读）。
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_export.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_list_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

/// 进程内文件写入捕获（dart:io IOOverrides.createFile 接缝，AI-SEX-104 用）。
/// 平台事实与机制分工见文件头注。
class _MemoryFiles {
  static final Map<String, String> written = <String, String>{};

  static void reset() => written.clear();

  static String? contentOf(String path) => written[path];
}

/// IOOverrides 注入的 File 替身：只具体实现生产链路触达的 writeAsString，
/// 其余成员经 noSuchMethod 显式失败（fail-loud，防静默走错路径）。
class _CapturedFile implements File {
  _CapturedFile(this.path);

  @override
  final String path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    _MemoryFiles.written[path] = contents;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkbenchUsageStatsService.instance.resetForTesting();
    _MemoryFiles.reset();
    tempDir = Directory.systemTemp.createTempSync('session_export_test_');
    // AiSessionManager load/persist 需要文档目录；指向临时目录（mock 手法
    // 沿 workbench_session_list_view_test.dart）。
    const channels = [
      MethodChannel('plugins.flutter.io/path_provider'),
      MethodChannel('plugins.flutter.io/path_provider_foundation'),
      MethodChannel('plugins.flutter.io/path_provider_linux'),
      MethodChannel('plugins.flutter.io/path_provider_windows'),
    ];
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
    }
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // 挂起 IO 在 Windows 上可能仍短时占用临时目录（先例同款防抖注释）。
    }
  });

  AiConversationSession sessionOf(
    String id,
    String title, {
    Map<String, dynamic>? metadata,
  }) => AiConversationSession(
    id: id,
    title: title,
    createdAt: DateTime(2026, 9, 28, 10),
    updatedAt: DateTime(2026, 9, 28, 11),
    // 可增长列表：addMessage 会就地写入 messageIds（const 列表不可加）。
    messageIds: <String>[],
    metadata: metadata,
  );

  AiMessage messageFixture({
    String id = 'm1',
    bool isUser = true,
    String content = 'hello',
    Map<String, dynamic>? toolResultData,
  }) => AiMessage(
    id: id,
    isUser: isUser,
    content: content,
    timestamp: DateTime(2026, 9, 28, 11),
    toolResultData: toolResultData,
  );

  /// 给指定会话注入消息（addMessage 只挂当前会话——先 switch 再逐条加）。
  void seedMessages(
    AppProvider app,
    String sessionId,
    List<AiMessage> messages,
  ) {
    final service = app.aiPanel.aiConversationService;
    service.switchSession(sessionId);
    for (final message in messages) {
      service.addMessage(message);
    }
  }

  /// 泵独立 SessionListView（组件面，harness 沿 workbench_session_list_view_test）。
  Future<AppProvider> pumpView(
    WidgetTester tester, {
    required void Function(AppProvider app) seed,
  }) async {
    final app = AppProvider();
    await tester.runAsync(() => app.aiPanel.aiConversationService.load());
    seed(app);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: SessionListView(showHeader: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// 走完 AiSessionManager 的 500ms 防抖持久化 Timer（先例同款）。
  Future<void> drainPersistDebounce(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
  }

  /// 打开指定会话条目菜单并点「导出会话」→ 导出对话框出现（真实菜单入口）。
  Future<void> openExportDialog(WidgetTester tester, String sessionId) async {
    await tester.tap(find.byKey(ValueKey('workbench_session_menu_$sessionId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export session…'));
    await tester.pumpAndSettle();
  }

  /// 注入接缝 fake：记录建议文件名，返回 [nextPickPath]（null 模拟取消）。
  Future<String?> Function(String) makeRecordingPicker(
    List<String> calls,
    String? Function() nextPickPath,
  ) {
    return (String suggestedFileName) async {
      calls.add(suggestedFileName);
      return nextPickPath();
    };
  }

  /// 注入接缝 fake：记录审计调用的假 logExportEvent。
  Future<void> Function({required String format, required int rowCount})
  makeRecordingAudit(List<Map<String, Object?>> calls) {
    return ({required String format, required int rowCount}) async {
      calls.add(<String, Object?>{'format': format, 'rowCount': rowCount});
    };
  }

  /// 直调顶层导出入口注入两个接缝 fake（与菜单 onSelected 同一入口），
  /// 等对话框出现。流程 future 不在调用点等待——由后续 confirmExport 的
  /// pump 链推进至完成（fire-and-forget 与菜单路径同语义）。
  /// [captureFileWrites] = true 时经 IOOverrides 把 File.writeAsString
  /// 截获进 _MemoryFiles（AI-SEX-104 全链路，见文件头注的平台事实）。
  Future<void> startExportDialogWithInjections(
    WidgetTester tester,
    AppProvider app,
    String sessionId, {
    required Future<String?> Function(String suggestedFileName) picker,
    required Future<void> Function({
      required String format,
      required int rowCount,
    })
    audit,
    bool captureFileWrites = false,
  }) async {
    final context = tester.element(
      find.byKey(ValueKey('workbench_session_menu_$sessionId')),
    );
    final session = app.aiPanel.aiConversationService.sessions.firstWhere(
      (s) => s.id == sessionId,
    );
    void start() {
      unawaited(
        showAiSessionExportDialog(
          context,
          session,
          savePathPicker: picker,
          exportAuditLogger: audit,
        ),
      );
    }

    if (captureFileWrites) {
      IOOverrides.runZoned<void>(
        start,
        createFile: (path) => _CapturedFile(path),
      );
    } else {
      start();
    }
    await tester.pumpAndSettle();
  }

  /// 确认导出。fake async 内真实 IO future 不完成（平台事实见文件头注）：
  /// [diskWritePath] 非 null 时用 runAsync 窗口等待真实落盘生效（轮询文件
  /// 出现 + 尾部延迟），窗口关闭后 pump 刷出可见反馈；null 时（写入捕获）
  /// 链路在 fake async 内完成，直接 pumpAndSettle。
  Future<void> confirmExport(
    WidgetTester tester, {
    String? diskWritePath,
  }) async {
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    if (diskWritePath != null) {
      final target = File(diskWritePath);
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!target.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        // IO 完成事件可能滞后于落盘——尾部延迟留派发时间。
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
    }
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> firstSessionOf(Map<String, dynamic> envelope) =>
      (envelope['sessions'] as List<dynamic>).first as Map<String, dynamic>;

  testWidgets('AI-SEX-101 弹出菜单含导出项（rename 之后、delete 之前，既有两项不动）', (
    tester,
  ) async {
    await pumpView(
      tester,
      seed: (app) {
        app.aiPanel.aiConversationService.restoreSession(
          sessionOf('s1', 'session one'),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('workbench_session_menu_s1')));
    await tester.pumpAndSettle();

    // 三项都在；既有 rename/delete 文案不变。
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Export session…'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // 顺序：rename < export < delete（弹窗条目自上而下）。
    final renameY = tester.getCenter(find.text('Rename')).dy;
    final exportY = tester.getCenter(find.text('Export session…')).dy;
    final deleteY = tester.getCenter(find.text('Delete')).dy;
    expect(renameY < exportY, isTrue, reason: '导出项在 rename 之后');
    expect(exportY < deleteY, isTrue, reason: '导出项在 delete 之前');

    // 接线：选中导出项 → 导出对话框出现（取消收场）。
    await tester.tap(find.text('Export session…'));
    await tester.pumpAndSettle();
    expect(find.text('Export AI Session'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-102 对话框出现：说明文案 + 复选框默认勾选、可切换', (tester) async {
    await pumpView(
      tester,
      seed: (app) {
        app.aiPanel.aiConversationService.restoreSession(
          sessionOf('s1', 'session one'),
        );
      },
    );

    await openExportDialog(tester, 's1');

    expect(find.text('Export AI Session'), findsOneWidget);
    expect(
      find.textContaining('contains the full conversation'),
      findsOneWidget,
      reason: '说明文案（敏感数据提示）',
    );
    expect(find.text('Include query result data'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue, reason: '复选框默认勾选（含结果数据）');

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox)).value,
      isFalse,
      reason: '复选框可切换',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing, reason: '取消零反馈');

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-103 取消对话框 → 无选择器调用、无文件写、无审计、无 snackbar', (tester) async {
    final pickerCalls = <String>[];
    final auditCalls = <Map<String, Object?>>[];
    String? pickPath;
    final app = await pumpView(
      tester,
      seed: (app) {
        app.aiPanel.aiConversationService.restoreSession(
          sessionOf('s1', 'session one'),
        );
      },
    );

    // 对话框阶段未触达选择器（注入缝在确认后才被消费）。
    await startExportDialogWithInjections(
      tester,
      app,
      's1',
      picker: makeRecordingPicker(pickerCalls, () => pickPath),
      audit: makeRecordingAudit(auditCalls),
    );
    expect(pickerCalls, isEmpty, reason: '对话框阶段未触达选择器');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(pickerCalls, isEmpty, reason: '取消 → 选择器不被调用');
    expect(auditCalls, isEmpty, reason: '取消 → 零审计调用');
    expect(find.byType(SnackBar), findsNothing, reason: '取消 → 零反馈');
    // tempDir 同时是 mock 文档目录（AiSessionManager 存 ai_sessions.json），
    // 只断言无导出产物文件。
    final strays = tempDir
        .listSync()
        .where((e) => !e.path.endsWith('ai_sessions.json'))
        .toList();
    expect(strays, isEmpty, reason: '取消 → 无导出文件写');

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-104 完整保存流：落盘/信封/成功反馈/审计；去勾 → 轻量模式', (tester) async {
    final pickerCalls = <String>[];
    final auditCalls = <Map<String, Object?>>[];
    String? pickPath;
    final toolResult = <String, dynamic>{
      'rows': <dynamic>['a', 'b'],
      'rowCount': 2,
    };

    final app = await pumpView(
      tester,
      seed: (app) {
        final service = app.aiPanel.aiConversationService;
        service.restoreSession(sessionOf('ds1', 'diag session'));
        seedMessages(app, 'ds1', <AiMessage>[
          messageFixture(id: 'm1', isUser: true, content: 'find rows'),
          messageFixture(
            id: 'm2',
            isUser: false,
            content: 'here you go',
            toolResultData: toolResult,
          ),
        ]);
      },
    );

    // ── Phase 1：默认勾选（含结果数据）──
    await startExportDialogWithInjections(
      tester,
      app,
      'ds1',
      picker: makeRecordingPicker(pickerCalls, () => pickPath),
      audit: makeRecordingAudit(auditCalls),
      captureFileWrites: true,
    );
    pickPath = '${tempDir.path}/out';
    await confirmExport(tester);

    // T1 命名规则经 picker 透传。
    expect(pickerCalls, hasLength(1));
    expect(pickerCalls.single, startsWith('dbmaster-ai-session-'));
    expect(pickerCalls.single, endsWith('.json'));

    // 落文件（写入捕获，机制见文件头注）+ 信封可解、顶层正确。
    final String? written = _MemoryFiles.contentOf('${tempDir.path}/out.json');
    expect(written, isNotNull, reason: '路径落文件（写入捕获）');
    final envelope =
        jsonDecode(written ?? '') as Map<String, dynamic>; // 上行 expect 已保证非空
    expect(envelope['format'], 'dbmaster-ai-session-export');
    expect(envelope['version'], 1);
    expect(
      (envelope['options'] as Map<String, dynamic>)['includeToolResultData'],
      isTrue,
    );

    // 成功 snackbar（path 插值为最终路径）。
    expect(find.textContaining('Session exported:'), findsOneWidget);
    expect(find.textContaining('out.json'), findsOneWidget);

    // 审计：format='ai_session_json'，rowCount=消息数。
    expect(auditCalls, hasLength(1));
    expect(auditCalls.single['format'], 'ai_session_json');
    expect(auditCalls.single['rowCount'], 2);

    // ── Phase 2：去勾复选框 → 轻量模式 ──
    await startExportDialogWithInjections(
      tester,
      app,
      'ds1',
      picker: makeRecordingPicker(pickerCalls, () => pickPath),
      audit: makeRecordingAudit(auditCalls),
      captureFileWrites: true,
    );
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox)).value,
      isTrue,
      reason: '复选框每次打开默认勾选',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    pickPath = '${tempDir.path}/light';
    await confirmExport(tester);

    final String? lightWritten = _MemoryFiles.contentOf(
      '${tempDir.path}/light.json',
    );
    expect(lightWritten, isNotNull, reason: '轻量模式导出落文件（写入捕获）');
    final lightEnvelope =
        jsonDecode(lightWritten ?? '') as Map<String, dynamic>;
    expect(
      (lightEnvelope['options']
          as Map<String, dynamic>)['includeToolResultData'],
      isFalse,
      reason: '去勾 → includeToolResultData=false',
    );
    final messages =
        (firstSessionOf(lightEnvelope)['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    expect(messages, hasLength(2));
    expect(
      messages[1]['toolResultData'],
      isNull,
      reason: '轻量模式：非 agent toolResultData 置 null',
    );
    expect(auditCalls, hasLength(2), reason: '两次导出各审计一次');

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-105 注入 picker 抛错 → 错误 snackbar，文案经 redactSecrets', (
    tester,
  ) async {
    final auditCalls = <Map<String, Object?>>[];
    final app = await pumpView(
      tester,
      seed: (app) {
        app.aiPanel.aiConversationService.restoreSession(
          sessionOf('s1', 'session one'),
        );
      },
    );

    await startExportDialogWithInjections(
      tester,
      app,
      's1',
      picker: (String suggestedFileName) async =>
          throw Exception('save failed api_key=sk-secret-123'),
      audit: makeRecordingAudit(auditCalls),
    );

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Session export failed'), findsOneWidget);
    expect(
      find.textContaining('sk-secret-123'),
      findsNothing,
      reason: '敏感片段经 redactSecrets 脱敏',
    );
    expect(find.textContaining('***'), findsOneWidget);
    expect(auditCalls, isEmpty, reason: '失败路径不审计');
    final strays = tempDir
        .listSync()
        .where((e) => !e.path.endsWith('ai_sessions.json'))
        .toList();
    expect(strays, isEmpty, reason: '失败 → 无导出文件写');

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-106 两会话并存：导出非当前会话 → currentSession 不变、落盘为目标会话', (
    tester,
  ) async {
    final auditCalls = <Map<String, Object?>>[];
    String? pickPath;
    final app = await pumpView(
      tester,
      seed: (app) {
        final service = app.aiPanel.aiConversationService;
        service.restoreSession(sessionOf('s1', 'target session'));
        seedMessages(app, 's1', <AiMessage>[
          messageFixture(id: 'm1', isUser: true, content: 'from s1'),
        ]);
        service.restoreSession(sessionOf('s2', 'other session'));
        service.switchSession('s2');
      },
    );
    final service = app.aiPanel.aiConversationService;
    expect(service.currentSession?.id, 's2', reason: '前置：当前会话为 s2');

    await startExportDialogWithInjections(
      tester,
      app,
      's1',
      picker: makeRecordingPicker(<String>[], () => pickPath),
      audit: makeRecordingAudit(auditCalls),
    );
    pickPath = '${tempDir.path}/target';
    await confirmExport(tester, diskWritePath: '${tempDir.path}/target.json');

    expect(
      service.currentSession?.id,
      's2',
      reason: '导出非当前会话不改 currentSession',
    );

    final file = File('${tempDir.path}/target.json');
    expect(file.existsSync(), isTrue);
    final envelope =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(
      (firstSessionOf(envelope)['session'] as Map<String, dynamic>)['id'],
      's1',
      reason: '落盘信封为目标会话',
    );

    await drainPersistDebounce(tester);
  });

  testWidgets('AI-SEX-107 确认对话框后取消文件选择（picker 返回 null）→ '
      '选择器已调用一次但零审计、零文件写、零 snackbar', (tester) async {
    final pickerCalls = <String>[];
    final auditCalls = <Map<String, Object?>>[];
    String? pickPath; // null = 文件选择取消
    final app = await pumpView(
      tester,
      seed: (app) {
        app.aiPanel.aiConversationService.restoreSession(
          sessionOf('s1', 'session one'),
        );
      },
    );

    await startExportDialogWithInjections(
      tester,
      app,
      's1',
      picker: makeRecordingPicker(pickerCalls, () => pickPath),
      audit: makeRecordingAudit(auditCalls),
    );
    await confirmExport(tester);

    expect(pickerCalls, hasLength(1), reason: '对话框确认后选择器被调用一次');
    expect(auditCalls, isEmpty, reason: '文件选择取消 → 零审计调用');
    expect(find.byType(SnackBar), findsNothing, reason: '文件选择取消 → 零反馈');
    // tempDir 同时是 mock 文档目录（AiSessionManager 存 ai_sessions.json），
    // 只断言无导出产物文件（断言手法与 AI-SEX-103 同源）。
    final strays = tempDir
        .listSync()
        .where((e) => !e.path.endsWith('ai_sessions.json'))
        .toList();
    expect(strays, isEmpty, reason: '文件选择取消 → 无导出文件写');

    await drainPersistDebounce(tester);
  });
}
