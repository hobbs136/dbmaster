//! AI 工作台上下文选择器（design-ai-workbench §4.2 R2 修订，T18）。
//!
//! 修复走查缺陷「进入 workbench 后无法选择已创建的实例和数据库」：三态语义
//! =「选择即锁定」，不引入第三态——picker 选中连接/库即
//! `aiPanel.lockWorkbenchContext(connId, dbName)` 进入锁定态；解锁回跟随；
//! 未设置态是跟随态 source == none 的子情形。
//!
//! 技术强制：resolver 只读 tab/侧栏、不读 selectedConnectionId——只
//! setSelected 不落锁会被芯片同步管道下一帧按 effective 值写回。因此本组件
//! 只经 `lockWorkbenchContext` 落锁生效（design §4.2 R2）。
//!
//! 布局：单层双栏 master-detail（连接栏 200 固定 | 库栏 Expanded，总内容区
//! 440）。数据路径复用经典面板同一来源：连接分区 = `savedConnections` +
//! `connectionGroups`（未分组在前、组头不可点、孤儿分组按未分组）；连接状态
//! = `isConnectionConnected/isConnectionConnecting`；库列表 =
//! `dbService.getDatabases(connectionId:)`，装载成功经
//! `setSelectedConnectionDatabases` 写共享缓存（与经典 `_loadDatabasesForServer`
//! 同源）。本组件不触碰 `ai_panel_widget.dart`。
//!
//! 取消纪律：取消/Esc/遮罩 = 零状态变化（唯一 provider 写入点是装库成功
//! 后的共享库列表缓存与落锁动作本身）。
//!
//! 表模式（v0.3.5 批2 T5 / B-04，`onTableSelected != null`）：库行 = 钻取
//! 表清单（不提交），表行 = 回调三元组后关闭；右栏两级切换（库列表⇄表
//! 清单，带返回），无第三栏、无锁定出口、无仅连接出口。表清单经
//! `getTables(connectionId:, databaseName:)` 实时载入，picker 本地态不写
//! provider（取消 = 零状态变化；载库成功仍走既有
//! `setSelectedConnectionDatabases` 共享缓存不变）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../atoms/app_transitions.dart';
import '../../l10n/app_localizations.dart';
import '../../models/connection_failure.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/workbench_context_resolver.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../connection/connect_failure_dialog.dart';
import '../connection/connection_dialog.dart';
import '../connection/password_prompt_dialog.dart';
import 'workbench_context_change_hint.dart';

/// AI 工作台上下文选择器（三态全态可开；选择即锁定，R2）。
class WorkbenchContextPicker extends StatefulWidget {
  /// 创建上下文选择器。
  ///
  /// [onSelected] 可选：传入时确认选择改为回调写入（v0.3.5 批1 返工 T2b，
  /// 经典 dock 紧凑卡入口用——写 dock 手动上下文而非工作台锁定），回调后
  /// 直接关闭、不落 `lockWorkbenchContext`；null（默认）保持 R2「选择即
  /// 锁定」语义逐字节不变（工作台入口零回归）。
  ///
  /// [onTableSelected] 非 null 即进入**表模式**（T5/B-04）：库行点击 =
  /// 钻取表清单（不提交），表行点击 = 回调三元组后关闭；无锁定 / 仅连接
  /// 出口。[initialConnectionId]/[initialDatabaseName] 仅表模式读取，
  /// 打开即定位到该连接（库已定则直接呈表清单）。
  const WorkbenchContextPicker({
    super.key,
    this.onSelected,
    this.onTableSelected,
    this.initialConnectionId,
    this.initialDatabaseName,
  });

  /// 确认选择回调（连接 id + 库名，null = 仅连接）。
  final void Function(String connectionId, String? databaseName)? onSelected;

  /// 表模式确认回调（连接 id + 库名 + 表名）；非 null 即表模式。
  final void Function(String connectionId, String databaseName, String tableName)?
  onTableSelected;

  /// 表模式初始连接（仅表模式读取）。
  final String? initialConnectionId;

  /// 表模式初始库（仅表模式读取；已定则打开即钻取表清单）。
  final String? initialDatabaseName;

  /// 以模态对话框打开（ConnectFailureDialog.show 同款 showAnimatedDialog）。
  /// 遮罩可点关闭（取消 = 零状态变化）。
  static Future<void> show(
    BuildContext context, {
    void Function(String connectionId, String? databaseName)? onSelected,
    void Function(String connectionId, String databaseName, String tableName)?
    onTableSelected,
    String? initialConnectionId,
    String? initialDatabaseName,
  }) {
    return context.showAnimatedDialog<void>(
      barrierDismissible: true,
      builder: (_) => WorkbenchContextPicker(
        onSelected: onSelected,
        onTableSelected: onTableSelected,
        initialConnectionId: initialConnectionId,
        initialDatabaseName: initialDatabaseName,
      ),
    );
  }

  @override
  State<WorkbenchContextPicker> createState() => _WorkbenchContextPickerState();
}

class _WorkbenchContextPickerState extends State<WorkbenchContextPicker> {
  final FocusNode _connColumnFocus = FocusNode();
  final FocusNode _dbColumnFocus = FocusNode();
  final FocusNode _newConnectionFocus = FocusNode();
  final ScrollController _connScroll = ScrollController();
  final ScrollController _dbScroll = ScrollController();

  /// master 栏扁平条目（分组头 + 连接）；build 与键盘逻辑共用。
  List<_ConnEntry> _entries = const <_ConnEntry>[];
  int? _selectedConnIndex;
  bool _connColumnFocused = false;
  bool _dbColumnFocused = false;

  // 右栏状态机：hint → loading → (databases | empty | failed)。
  DbServer? _activeConnection;
  List<String> _databases = const <String>[];
  int? _selectedDbIndex;
  bool _loadingDatabases = false;
  bool _loadFailed = false;

  // 表模式右栏第二级（B-04）：库列表 ⇄ 表清单。
  bool _showingTables = false;
  String? _activeTableDatabase;
  List<String> _tables = const <String>[];
  int? _selectedTableIndex;
  bool _loadingTables = false;
  bool _tablesLoadFailed = false;

  /// 表模式判定唯一依据 = `onTableSelected != null`（不引入独立 bool）。
  bool get _tableMode => widget.onTableSelected != null;

  @override
  void initState() {
    super.initState();
    // 打开时预选当前生效上下文（不因预选自动连接，R2 交互裁决）。
    final provider = context.read<AppProvider>();
    _entries = _buildEntries(provider);
    _selectedConnIndex = _initialSelectionIndex(provider);
    if (_tableMode) {
      // 表模式：post-frame 定位初始连接/库（已连接才载库，预选不建连）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_bootstrapTableTarget());
      });
    }
  }

  @override
  void dispose() {
    _connColumnFocus.dispose();
    _dbColumnFocus.dispose();
    _newConnectionFocus.dispose();
    _connScroll.dispose();
    _dbScroll.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 数据（连接分区装配与侧栏树多连接分节同语义——未分组在前、组头不可点；
  // T27 selector 退役后语义锚 = 侧栏树，不搬组件）
  // ──────────────────────────────────────────────────────────────────────────

  /// 连接分区：未分组在前 → 各分组（组头不可点）；孤儿分组（groupId 指向
  /// 已删组）按未分组处理，与侧栏树连接分节装配语义一致。
  List<_ConnEntry> _buildEntries(AppProvider provider) {
    final groups = provider.connectionGroups;
    final grouped = <String, List<DbServer>>{};
    final ungrouped = <DbServer>[];
    for (final conn in provider.savedConnections) {
      final gid = conn.groupId;
      if (gid != null && groups.any((g) => g.id == gid)) {
        grouped.putIfAbsent(gid, () => <DbServer>[]).add(conn);
      } else {
        ungrouped.add(conn);
      }
    }
    final entries = <_ConnEntry>[
      for (final server in ungrouped) _ConnEntry.server(server),
    ];
    for (final group in groups) {
      final members = grouped[group.id];
      if (members == null || members.isEmpty) continue;
      entries.add(_ConnEntry.group(group));
      for (final server in members) {
        entries.add(_ConnEntry.server(server));
      }
    }
    return entries;
  }

  int? _initialSelectionIndex(AppProvider provider) {
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.aiConversationService.currentSession,
      provider,
    );
    final id = ctx.connectionId;
    if (id != null) {
      for (var i = 0; i < _entries.length; i++) {
        if (_entries[i].server?.id == id) return i;
      }
    }
    return _firstSelectableIndex();
  }

  int? _firstSelectableIndex() {
    for (var i = 0; i < _entries.length; i++) {
      if (!_entries[i].isGroupHeader) return i;
    }
    return null;
  }

  int? _lastSelectableIndex() {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (!_entries[i].isGroupHeader) return i;
    }
    return null;
  }

  /// 从 [from] 起（不含）按 [step] 找下一个可选条目（跳过分组头）。
  int? _nextSelectableIndex(int from, int step) {
    var i = from + step;
    while (i >= 0 && i < _entries.length) {
      if (!_entries[i].isGroupHeader) return i;
      i += step;
    }
    return null;
  }

  double _rowHeightOf(int index) => _entries[index].isGroupHeader
      ? AppDesignSystem.workbenchContextPickerItemHeight - 6
      : AppDesignSystem.workbenchContextPickerItemHeight;

  double _connOffsetFor(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _rowHeightOf(i);
    }
    return offset;
  }

  void _ensureConnVisible(int index) {
    if (!_connScroll.hasClients) return;
    final position = _connScroll.position;
    final top = _connOffsetFor(index);
    final bottom = top + _rowHeightOf(index);
    if (top < position.pixels) {
      _connScroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _connScroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  void _ensureDbVisible(int index) {
    if (!_dbScroll.hasClients) return;
    final position = _dbScroll.position;
    final rowHeight = AppDesignSystem.workbenchContextPickerItemHeight;
    final top = index * rowHeight;
    final bottom = top + rowHeight;
    if (top < position.pixels) {
      _dbScroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _dbScroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  /// 表清单与库列表共用右栏滚动控制器（同一列两级）。
  void _ensureTableVisible(int index) => _ensureDbVisible(index);

  // ──────────────────────────────────────────────────────────────────────────
  // 动作
  // ──────────────────────────────────────────────────────────────────────────

  /// 点连接行 / 连接栏 Enter：未连接则先连接（密码提示 → 连接失败对话框），
  /// 然后装载库列表进右栏。失败对话框重试成功后自动继续装库。
  Future<void> _activateConnEntry(int index) async {
    final server = _entries[index].server;
    if (server == null) return;
    if (_loadingDatabases) return;
    _resetRightColumn();
    setState(() => _selectedConnIndex = index);
    await _connectAndLoad(server);
  }

  void _resetRightColumn() {
    _activeConnection = null;
    _databases = const <String>[];
    _selectedDbIndex = null;
    _loadingDatabases = false;
    _loadFailed = false;
    _resetTableLevel();
  }

  /// 表清单层级复位（回库列表 / 换连接 / 关闭时调用）。
  void _resetTableLevel() {
    _showingTables = false;
    _activeTableDatabase = null;
    _tables = const <String>[];
    _selectedTableIndex = null;
    _loadingTables = false;
    _tablesLoadFailed = false;
  }

  /// 表模式初始定位：选中初始连接；已连接才载库，库已定则直接钻取表清单。
  /// 未连接时保持预选 + 右栏提示态（R2 交互裁决：预选不自动建连）。
  Future<void> _bootstrapTableTarget() async {
    final String? initialId = widget.initialConnectionId;
    if (initialId == null) return;
    final int index = _entries.indexWhere((e) => e.server?.id == initialId);
    if (index < 0) return;
    final server = _entries[index].server;
    if (server == null) return;
    setState(() => _selectedConnIndex = index);
    final provider = context.read<AppProvider>();
    if (!provider.isConnectionConnected(server.id)) return;
    await _loadDatabases(server);
    if (!mounted) return;
    final String? initialDb = widget.initialDatabaseName;
    if (initialDb == null || initialDb.isEmpty) return;
    if (!_databases.contains(initialDb)) return;
    await _openTables(initialDb);
  }

  Future<void> _connectAndLoad(DbServer server) async {
    final provider = context.read<AppProvider>();
    try {
      if (!provider.isConnectionConnected(server.id)) {
        final withPassword = await PasswordPromptDialog.ensurePassword(
          context,
          server,
        );
        if (withPassword == null) {
          // 密码取消：零写入（picker 保持、右栏回提示态）。
          if (!mounted) return;
          setState(_resetRightColumn);
          return;
        }
        final connected = await provider.connection.connectToServer(
          withPassword,
        );
        if (!connected) {
          if (!mounted) return;
          await _showConnectFailure(withPassword);
          if (!mounted) return;
          if (provider.isConnectionConnected(server.id)) {
            await _loadDatabases(server);
          } else {
            setState(_resetRightColumn);
          }
          return;
        }
      }
      await _loadDatabases(server);
    } catch (error, stackTrace) {
      AppLogger.e(
        'WorkbenchContextPicker',
        'connect/load databases failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadingDatabases = false;
        _loadFailed = true;
        _databases = const <String>[];
        _selectedDbIndex = null;
      });
    }
  }

  /// 连接失败：ConnectFailureDialog（重试/最新失败注入，同经典路径）；
  /// 失败期间 picker 保持打开、零写入。
  Future<void> _showConnectFailure(DbServer attempt) async {
    final failure = context
        .read<AppProvider>()
        .connection
        .lastConnectFailure;
    await ConnectFailureDialog.show(
      context,
      failure:
          failure ??
          ConnectionFailure(
            kind: ConnectionFailureKind.unknown,
            errorCode: '',
            rawMessage: '',
            occurredAt: DateTime.now(),
          ),
      // T8 报告字段接线：库型显示名（DatabaseType.displayName）+ 环境标签
      //（status_bar 三态 l10n 映射口径；无 environment 传 null，报告省略行）。
      driverName: attempt.type.displayName,
      environmentLabel: _connectFailureEnvironmentLabel(
        AppLocalizations.of(context),
        attempt.environment,
      ),
      onRetry: () => context
          .read<AppProvider>()
          .connection
          .connectToServer(attempt),
      latestFailure: () =>
          context.read<AppProvider>().connection.lastConnectFailure,
    );
  }

  /// 连接失败报告的环境标签（T8 接线）：沿 status_bar_widget /
  /// production_guard_dialog「消费面各持副本、不建共享文件」惯例的本地
  /// 三态映射；environment 为 null 时返回 null（报告省略「环境标签」行）。
  String? _connectFailureEnvironmentLabel(
    AppLocalizations? l10n,
    ConnectionEnvironment? environment,
  ) {
    switch (environment) {
      case null:
        return null;
      case ConnectionEnvironment.production:
        return l10n?.environmentProduction ?? 'Production environment';
      case ConnectionEnvironment.testing:
        return l10n?.environmentTesting ?? 'Testing environment';
      case ConnectionEnvironment.development:
        return l10n?.environmentDevelopment ?? 'Development environment';
    }
  }

  Future<void> _loadDatabases(DbServer server) async {
    final provider = context.read<AppProvider>();
    setState(() {
      // 先落 active：失败态（内联错误行/重试）也锚定该连接。
      _activeConnection = server;
      _loadingDatabases = true;
      _loadFailed = false;
      _selectedDbIndex = null;
    });
    try {
      final databases = await provider.dbService.getDatabases(
        connectionId: server.id,
      );
      if (!mounted) return;
      // 数据路径（R2）：与经典面板同源，写共享库列表缓存；仅缓存，不落
      // selectedConnectionId/DatabaseName（落锁才是生效写入）。
      provider.aiPanel.setSelectedConnectionDatabases(databases);
      setState(() {
        _activeConnection = server;
        _databases = databases;
        _loadingDatabases = false;
        _selectedDbIndex = databases.isNotEmpty ? 0 : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureDbVisible(0);
      });
    } catch (error, stackTrace) {
      AppLogger.e(
        'WorkbenchContextPicker',
        'load databases failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadingDatabases = false;
        _loadFailed = true;
        _databases = const <String>[];
        _selectedDbIndex = null;
      });
    }
  }

  /// 表模式：库行点击 = 钻取表清单（不 commit，B-04）。
  Future<void> _openTables(String databaseName) async {
    final connection = _activeConnection;
    if (connection == null) return;
    setState(() {
      _showingTables = true;
      _activeTableDatabase = databaseName;
      _tables = const <String>[];
      _selectedTableIndex = null;
      _loadingTables = true;
      _tablesLoadFailed = false;
    });
    try {
      final tables = await context.read<AppProvider>().dbService.getTables(
        connectionId: connection.id,
        databaseName: databaseName,
      );
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loadingTables = false;
        _selectedTableIndex = tables.isNotEmpty ? 0 : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureTableVisible(0);
      });
    } catch (error, stackTrace) {
      AppLogger.e(
        'WorkbenchContextPicker',
        'load tables failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadingTables = false;
        _tablesLoadFailed = true;
        _tables = const <String>[];
        _selectedTableIndex = null;
      });
    }
  }

  /// 表清单 → 库列表（右栏返回；清表清单层级，不动连接/库列表）。
  void _backToDatabases() {
    setState(_resetTableLevel);
  }

  /// 表模式提交：回调三元组（provider 写入责任在宿主）后关闭。
  void _commitTable(String tableName) {
    final connection = _activeConnection;
    final databaseName = _activeTableDatabase;
    final onTableSelected = widget.onTableSelected;
    if (connection == null ||
        databaseName == null ||
        onTableSelected == null) {
      return;
    }
    onTableSelected(connection.id, databaseName, tableName);
    Navigator.of(context).pop();
  }

  /// 点库行 / 库栏 Enter：选择即确认（三态语义裁决），随即关闭。
  ///
  /// 表模式（[WorkbenchContextPicker.onTableSelected] 非 null）→ 钻取表
  /// 清单不提交（B-04）；[onSelected] 传入（经典 dock 入口）→ 回调写入
  /// 后直接关闭，不落工作台锁定；null（工作台入口）→ 保持 R2「选择即
  /// 锁定」+ run 活跃提示，逐字节不变。
  void _commitDatabase(String databaseName) {
    final connection = _activeConnection;
    if (connection == null) return;
    if (widget.onTableSelected != null) {
      unawaited(_openTables(databaseName));
      return;
    }
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(connection.id, databaseName);
      Navigator.of(context).pop();
      return;
    }
    final aiPanel = context.read<AppProvider>().aiPanel;
    aiPanel.lockWorkbenchContext(connection.id, databaseName);
    // T6：run 活跃时提示「改选下次运行生效」（D15 快照契约显示面）；放在
    // pop 前——pop 后本 State 的 context 失效。
    WorkbenchContextChangeHint.showIfRunActive(context, aiPanel);
    Navigator.of(context).pop();
  }

  /// 库列表为空时允许仅确认连接（databaseName = null）；出口语义同
  /// [_commitDatabase]（回调路径 / 工作台锁定路径）。
  void _lockConnectionOnly() {
    final connection = _activeConnection;
    if (connection == null) return;
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(connection.id, null);
      Navigator.of(context).pop();
      return;
    }
    final aiPanel = context.read<AppProvider>().aiPanel;
    aiPanel.lockWorkbenchContext(connection.id, null);
    WorkbenchContextChangeHint.showIfRunActive(context, aiPanel);
    Navigator.of(context).pop();
  }

  /// 次出口：新建连接（picker 保持打开，新建结果经 provider 通知实时进列表）。
  void _openNewConnectionDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 键盘（R2-11）：↑↓ 栏内 roving、Home/End/PageUp/Down、Enter 提交；
  // Tab/Shift+Tab 双栏与 footer 环形（根级接管）；Esc 关闭。
  // ──────────────────────────────────────────────────────────────────────────

  KeyEventResult _onRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _cycleFocus(shift: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _cycleFocus({required bool shift}) {
    final nodes = <FocusNode>[
      _connColumnFocus,
      _dbColumnFocus,
      _newConnectionFocus,
    ];
    final current = FocusManager.instance.primaryFocus;
    var index = nodes.indexWhere((n) => identical(n, current) || n.hasFocus);
    if (index < 0) {
      index = 0;
    } else {
      index =
          (index + (shift ? nodes.length - 1 : 1)) % nodes.length;
    }
    nodes[index].requestFocus();
  }

  KeyEventResult _onConnColumnKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) return _moveConnSelection(1);
    if (key == LogicalKeyboardKey.arrowUp) return _moveConnSelection(-1);
    if (key == LogicalKeyboardKey.pageDown) return _moveConnSelectionByPage(1);
    if (key == LogicalKeyboardKey.pageUp) return _moveConnSelectionByPage(-1);
    if (key == LogicalKeyboardKey.home) return _jumpConnSelection(toStart: true);
    if (key == LogicalKeyboardKey.end) return _jumpConnSelection(toStart: false);
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _selectedConnIndex;
      if (index != null) {
        unawaited(_activateConnEntry(index));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveConnSelection(int step) {
    final current = _selectedConnIndex;
    final target = current == null
        ? _firstSelectableIndex()
        : _nextSelectableIndex(current, step);
    return _applyConnSelection(target);
  }

  KeyEventResult _moveConnSelectionByPage(int pages) {
    var target = _selectedConnIndex;
    for (var i = 0; i < 5; i++) {
      if (target == null) break;
      final next = _nextSelectableIndex(target, pages);
      if (next == null) break;
      target = next;
    }
    return _applyConnSelection(target);
  }

  KeyEventResult _jumpConnSelection({required bool toStart}) =>
      _applyConnSelection(toStart ? _firstSelectableIndex() : _lastSelectableIndex());

  KeyEventResult _applyConnSelection(int? target) {
    if (target == null) return KeyEventResult.handled;
    setState(() => _selectedConnIndex = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnVisible(target);
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _onDbColumnKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_tableMode && _showingTables) {
      return _onTableColumnKeyEvent(event);
    }
    final key = event.logicalKey;
    final count = _databases.length;
    if (count == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      return _moveDbSelection(1);
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      return _moveDbSelection(-1);
    }
    if (key == LogicalKeyboardKey.home) return _moveDbSelectionTo(0);
    if (key == LogicalKeyboardKey.end) return _moveDbSelectionTo(count - 1);
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _selectedDbIndex;
      if (index != null && index >= 0 && index < count) {
        _commitDatabase(_databases[index]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 表清单键盘（表模式下右栏第二级）：与库栏同款 roving，Enter 提交表。
  KeyEventResult _onTableColumnKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    final count = _tables.length;
    if (count == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      return _moveTableSelection(1);
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      return _moveTableSelection(-1);
    }
    if (key == LogicalKeyboardKey.home) return _moveTableSelectionTo(0);
    if (key == LogicalKeyboardKey.end) return _moveTableSelectionTo(count - 1);
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _selectedTableIndex;
      if (index != null && index >= 0 && index < count) {
        _commitTable(_tables[index]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveTableSelection(int step) {
    final count = _tables.length;
    if (count == 0) return KeyEventResult.handled;
    final current = _selectedTableIndex ?? (step > 0 ? -1 : count);
    var target = current + step;
    if (target < 0) target = 0;
    if (target > count - 1) target = count - 1;
    return _moveTableSelectionTo(target);
  }

  KeyEventResult _moveTableSelectionTo(int target) {
    setState(() => _selectedTableIndex = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTableVisible(target);
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _moveDbSelection(int step) {
    final count = _databases.length;
    if (count == 0) return KeyEventResult.handled;
    final current = _selectedDbIndex ?? (step > 0 ? -1 : count);
    var target = current + step;
    if (target < 0) target = 0;
    if (target > count - 1) target = count - 1;
    return _moveDbSelectionTo(target);
  }

  KeyEventResult _moveDbSelectionTo(int target) {
    setState(() => _selectedDbIndex = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureDbVisible(target);
    });
    return KeyEventResult.handled;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 构建
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final l10n = AppLocalizations.of(context)!;
    // watch 数据驱动重建时同步键盘逻辑面（build 之外的处理器读同一份）。
    _entries = _buildEntries(provider);
    final selected = _selectedConnIndex;
    if (selected != null && selected >= _entries.length) {
      _selectedConnIndex = _firstSelectableIndex();
    }
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onRootKeyEvent,
      child: Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(context, l10n),
              const SizedBox(height: AppDesignSystem.space3),
              if (provider.savedConnections.isEmpty)
                _buildEmptyGuidance(context, l10n)
              else
                _buildColumns(context, provider, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, AppLocalizations l10n) {
    return Text(
      l10n.workbenchContextPickerTitle,
      style: TextStyle(
        fontSize: AppDesignSystem.fontSizeLg,
        fontWeight: AppDesignSystem.fontWeightSemibold,
        color: context.themeColors.textPrimary,
      ),
    );
  }

  /// 无任何已保存连接：不渲染双栏，居中引导 + 「新建连接」入口（R2-7）。
  Widget _buildEmptyGuidance(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return SizedBox(
      width: AppDesignSystem.workbenchContextPickerWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppDesignSystem.space4),
          Icon(LucideIcons.database, size: 28, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            l10n.aiPanelNoConnections,
            style: TextStyle(fontSize: AppDesignSystem.fontSizeSm, color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          FilledButton.icon(
            onPressed: _openNewConnectionDialog,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accentBlue,
              foregroundColor: colors.bgSecondary,
            ),
            icon: const Icon(LucideIcons.plus, size: 14),
            label: Text(l10n.workbenchContextPickerNewConnection),
          ),
          _buildFooter(context, l10n),
        ],
      ),
    );
  }

  Widget _buildColumns(BuildContext context, AppProvider provider, AppLocalizations l10n) {
    return SizedBox(
      key: const ValueKey('workbench_context_picker_content'),
      width: AppDesignSystem.workbenchContextPickerWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConnectionColumn(context, l10n),
              Container(
                width: 1,
                color: context.themeColors.borderLight,
              ),
              Expanded(child: _buildDatabaseColumn(context, l10n)),
            ],
          ),
          _buildFooter(context, l10n),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          fontWeight: AppDesignSystem.fontWeightSemibold,
          color: context.themeColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildConnectionColumn(BuildContext context, AppLocalizations l10n) {
    return SizedBox(
      width: AppDesignSystem.workbenchContextPickerConnListWidth,
      child: Focus(
        focusNode: _connColumnFocus,
        autofocus: true,
        onFocusChange: (focused) => setState(() => _connColumnFocused = focused),
        onKeyEvent: _onConnColumnKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildColumnHeader(l10n.aiPanelSelectConnection),
            const SizedBox(height: AppDesignSystem.space1),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: AppDesignSystem.workbenchContextPickerListMaxHeight,
              ),
              child: SingleChildScrollView(
                controller: _connScroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _entries.length; i++)
                      _buildConnEntry(context, i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnEntry(BuildContext context, int index) {
    final entry = _entries[index];
    final group = entry.group;
    if (group != null) return _buildGroupHeader(context, group);
    final server = entry.server;
    if (server == null) return const SizedBox.shrink();
    return _buildConnectionRow(context, index, server);
  }

  Widget _buildGroupHeader(BuildContext context, ConnectionGroup group) {
    final colors = context.themeColors;
    return Container(
      height: AppDesignSystem.workbenchContextPickerItemHeight - 6,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _parseGroupColor(context, group.color),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseGroupColor(BuildContext context, String? colorStr) {
    if (colorStr == null) return context.themeColors.accentBlue;
    try {
      return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (_) {
      return context.themeColors.accentBlue;
    }
  }

  Widget _buildConnectionRow(
    BuildContext context,
    int index,
    DbServer server,
  ) {
    final provider = context.watch<AppProvider>();
    final colors = context.themeColors;
    final selected = index == _selectedConnIndex;
    final isConnecting = provider.isConnectionConnecting(server.id);
    final isConnected = provider.isConnectionConnected(server.id);
    return _PickerRow(
      key: ValueKey('workbench_context_picker_conn_${server.id}'),
      height: AppDesignSystem.workbenchContextPickerItemHeight,
      selected: selected,
      showFocusRing: selected && _connColumnFocused,
      onTap: () => unawaited(_activateConnEntry(index)),
      child: Row(
        children: [
          Icon(
            server.type.typeIcon,
            size: 14,
            color: colors.brandColor(server.type),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: selected ? AppDesignSystem.fontWeightSemibold : null,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
          if (isConnecting)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.accentBlue,
              ),
            )
          else if (isConnected)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.success,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatabaseColumn(BuildContext context, AppLocalizations l10n) {
    return Focus(
      focusNode: _dbColumnFocus,
      onFocusChange: (focused) => setState(() => _dbColumnFocused = focused),
      onKeyEvent: _onDbColumnKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRightColumnHeader(context, l10n),
          const SizedBox(height: AppDesignSystem.space1),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: AppDesignSystem.workbenchContextPickerListMaxHeight,
            ),
            child: SingleChildScrollView(
              controller: _dbScroll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildDatabaseColumnBody(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 右栏头：库列表 = 「Select Database」；表清单 = 返回按钮 + 库名（B-04
  /// 两级切换，无第三栏）。
  Widget _buildRightColumnHeader(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    if (!(_tableMode && _showingTables)) {
      return Padding(
        padding: const EdgeInsets.only(left: AppDesignSystem.space2),
        child: _buildColumnHeader(l10n.aiPanelSelectDatabase),
      );
    }
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(left: AppDesignSystem.space1),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey(
              'workbench_context_picker_back_to_databases',
            ),
            onPressed: _backToDatabases,
            tooltip: l10n.aiPanelSelectDatabase,
            icon: const Icon(LucideIcons.arrowLeft, size: 12),
            color: colors.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Expanded(
            child: Text(
              _activeTableDatabase ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDatabaseColumnBody(BuildContext context) {
    if (_tableMode && _showingTables) return _buildTableColumnBody(context);
    if (_activeConnection == null) return [_buildConnectHint(context)];
    if (_loadingDatabases) return [_buildLoadingRow(context)];
    if (_loadFailed) return [_buildLoadErrorRow(context)];
    if (_databases.isEmpty) return [_buildEmptyDatabases(context)];
    return [
      for (var i = 0; i < _databases.length; i++) _buildDatabaseRow(context, i),
    ];
  }

  /// 表清单（表模式第二级）：loading / failed / 空态引导 / 表行。
  List<Widget> _buildTableColumnBody(BuildContext context) {
    if (_loadingTables) {
      return [
        _buildLoadingRow(
          context,
          label: AppLocalizations.of(context)!.commonLoading,
        ),
      ];
    }
    if (_tablesLoadFailed) {
      final String? databaseName = _activeTableDatabase;
      return [
        _buildLoadErrorRow(
          context,
          message: AppLocalizations.of(context)!.commonFailed,
          onRetry: databaseName == null
              ? null
              : () => unawaited(_openTables(databaseName)),
        ),
      ];
    }
    if (_tables.isEmpty) return [_buildTableHintRow(context)];
    return [
      for (var i = 0; i < _tables.length; i++) _buildTableRow(context, i),
    ];
  }

  Widget _buildConnectHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space3,
      ),
      child: Text(
        AppLocalizations.of(context)!.workbenchContextPickerConnectHint,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeSm,
          color: context.themeColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildLoadingRow(BuildContext context, {String? label}) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colors.accentBlue,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              label ?? l10n.workbenchContextPickerLoadingDatabases,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 库加载失败：右栏内联错误行 + 重试（不用全局 snackbar，R2-9）。
  /// 表清单复用同形态（message/onRetry 注入）。
  Widget _buildLoadErrorRow(
    BuildContext context, {
    String? message,
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final server = _activeConnection;
    final VoidCallback? retry =
        onRetry ??
        (server == null
            ? null
            : () => unawaited(_loadDatabases(server)));
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 14, color: colors.error),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  message ?? l10n.aiPanelLoadDatabasesFailed,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1),
          TextButton.icon(
            onPressed: retry,
            style: TextButton.styleFrom(
              foregroundColor: colors.accentBlue,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.refreshCcw, size: 12),
            label: Text(
              l10n.commonRetry,
              style: const TextStyle(fontSize: AppDesignSystem.fontSizeSm),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDatabases(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.workbenchContextPickerNoDatabases,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              color: colors.textMuted,
            ),
          ),
          // 表模式无「仅连接」出口（B-04：无仅连接出口）。
          if (!_tableMode) ...[
            const SizedBox(height: AppDesignSystem.space2),
            TextButton.icon(
              onPressed: _lockConnectionOnly,
              style: TextButton.styleFrom(
                foregroundColor: colors.accentBlue,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(LucideIcons.lock, size: 12),
              label: Text(
                l10n.workbenchContextPickerConnectionOnly,
                style: const TextStyle(fontSize: AppDesignSystem.fontSizeSm),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 表模式空表清单引导行（B-04：空表清单渲染 uirvDockContextPickerHint）。
  Widget _buildTableHintRow(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space3,
      ),
      child: Text(
        AppLocalizations.of(context)!.uirvDockContextPickerHint,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeSm,
          color: colors.textMuted,
        ),
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, int index) {
    final colors = context.themeColors;
    final tableName = _tables[index];
    final selected = index == _selectedTableIndex;
    return _PickerRow(
      key: ValueKey('workbench_context_picker_table_$tableName'),
      height: AppDesignSystem.workbenchContextPickerItemHeight,
      selected: selected,
      showFocusRing: selected && _dbColumnFocused,
      onTap: () => _commitTable(tableName),
      child: Row(
        children: [
          Icon(LucideIcons.table2, size: 12, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              tableName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: selected ? AppDesignSystem.fontWeightSemibold : null,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseRow(BuildContext context, int index) {
    final colors = context.themeColors;
    final databaseName = _databases[index];
    final selected = index == _selectedDbIndex;
    return _PickerRow(
      key: ValueKey('workbench_context_picker_db_$databaseName'),
      height: AppDesignSystem.workbenchContextPickerItemHeight,
      selected: selected,
      showFocusRing: selected && _dbColumnFocused,
      onTap: () => _commitDatabase(databaseName),
      child: Row(
        children: [
          Icon(LucideIcons.database, size: 12, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              databaseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: selected ? AppDesignSystem.fontWeightSemibold : null,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            focusNode: _newConnectionFocus,
            onPressed: _openNewConnectionDialog,
            style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
            icon: const Icon(LucideIcons.plus, size: 14),
            label: Text(l10n.workbenchContextPickerNewConnection),
          ),
        ],
      ),
    );
  }
}

/// master 栏条目：分组头或连接（互斥；picker 内部装配用）。
class _ConnEntry {
  final DbServer? server;
  final ConnectionGroup? group;

  const _ConnEntry.server(this.server) : group = null;
  const _ConnEntry.group(this.group) : server = null;

  bool get isGroupHeader => group != null;
}

/// 选择器行壳：hover/选中 bgTertiary + 焦点环 1.5 accentBlue（R2 视觉规格）。
class _PickerRow extends StatefulWidget {
  const _PickerRow({
    super.key,
    required this.height,
    required this.selected,
    required this.showFocusRing,
    required this.onTap,
    required this.child,
  });

  final double height;
  final bool selected;
  final bool showFocusRing;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final highlighted = widget.selected || _hovering;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: highlighted ? colors.bgTertiary : null,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          foregroundDecoration: widget.showFocusRing
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.accentBlue, width: 1.5),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}
