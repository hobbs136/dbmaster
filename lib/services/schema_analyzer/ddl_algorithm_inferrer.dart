import '../../models/schema_analyzer/ddl_algorithm.dart';

/// MySQL DDL 锁语义推断器（纯函数，无 IO）。
///
/// 第四阶段 DDL 锁分析（requirements-phase4.md R13 / design-phase4.md §4.2）。
///
/// 根据 DDL 类型 + MySQL 版本推断默认 algorithm。用户显式写
/// `ALGORITHM=` / `LOCK=` 时以用户指定为准（不覆盖用户意图）。
///
/// 非 MySQL 库 / 版本不可用 → 返回 [DdlAlgorithmResult.unknown]
/// （保守，不静默乐观）。
///
/// 设计原则：
/// - **纯函数**：无 IO、无副作用，可纯单测（注入 mock 版本字符串）。
/// - **保守优先**（R18 NF5）：版本边界严格、不确定降级，宁可多报不漏报。
class DdlAlgorithmInferrer {
  /// 推断 DDL 的锁语义。
  ///
  /// [ddlStatement] 原始 DDL 文本（用于检测显式 ALGORITHM=/LOCK= + AFTER/FIRST + 字符集变更）。
  /// [ddlType] 来自 `ImpactAssessor.extractDdlType`（ADD_COLUMN / ALTER_COLUMN / TRUNCATE_TABLE / ...）。
  /// [databaseType] 库类型名（'mysql' / 'postgresql' / ...）。
  /// [serverVersion] `SELECT VERSION()` 返回（'8.0.32' / '5.7.43' / null）。
  ///
  /// 返回 [DdlAlgorithmResult]；非 MySQL 或版本不可解析时返回 unknown。
  static DdlAlgorithmResult infer({
    required String ddlStatement,
    required String ddlType,
    required String databaseType,
    String? serverVersion,
  }) {
    // 1. 按库分发。第四阶段只做 MySQL；B4 扩展 PostgreSQL / SQLite。
    //    Doris / ClickHouse / SQL Server / Oracle 等仍返回 unknown（不套用错误语义）。
    switch (databaseType.toLowerCase()) {
      case 'mysql':
        return _inferMysql(ddlStatement, ddlType, serverVersion);
      case 'postgresql':
        return _inferPostgres(ddlStatement, ddlType);
      case 'sqlite':
        return _inferSqlite(ddlStatement, ddlType);
      default:
        return DdlAlgorithmResult.unknown;
    }
  }

  /// MySQL 锁语义推断（第四阶段既有逻辑，原样提取到此方法）。
  static DdlAlgorithmResult _inferMysql(
    String ddlStatement,
    String ddlType,
    String? serverVersion,
  ) {
    // 显式 ALGORITHM=/LOCK= → 以用户指定为准（用户意图优先）。
    final explicit = _parseExplicitAlgorithm(ddlStatement);
    if (explicit != null) return explicit;

    // 解析 MySQL 版本。null（版本无法解析 / MariaDB）→ 保守 unknown。
    final version = _parseMysqlVersion(serverVersion);
    if (version == null) {
      return DdlAlgorithmResult(
        algorithm: DdlAlgorithm.unknown,
        concurrencyImpact: ConcurrencyImpact.unknown,
        note: '无法解析 MySQL 版本（$serverVersion），保守处理',
      );
    }

    // DDL 类型 → algorithm 映射（含版本分支）。
    return _inferByDdlType(ddlStatement, ddlType, version);
  }

  /// PostgreSQL 锁语义推断（B4）。
  ///
  /// PG 没有 MySQL 的 INSTANT/INPLACE/COPY 三分法，靠表级锁模式：
  /// - ALTER TABLE 系列（ADD/DROP/ALTER COLUMN、改类型）→ ACCESS EXCLUSIVE（阻塞读写）→ copy
  /// - CREATE INDEX 普通 → SHARE（阻塞写）→ copy（保守，比 MySQL COPY 轻）
  /// - CREATE/DROP INDEX **CONCURRENTLY** → SHARE UPDATE EXCLUSIVE（允许并发 DML）→ inplace
  /// - TRUNCATE / DROP / RENAME → ACCESS EXCLUSIVE（瞬时元数据改）→ metadataOnly
  ///
  /// PG 的锁模型与版本基本无关，无需 serverVersion 探测。
  static DdlAlgorithmResult _inferPostgres(String ddl, String ddlType) {
    switch (ddlType) {
      case 'TRUNCATE_TABLE':
      case 'DROP_TABLE':
      case 'RENAME_TABLE':
      case 'RENAME_COLUMN':
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: '元数据锁（PG ACCESS EXCLUSIVE，瞬时）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: 'PG $ddlType 只改元数据，瞬时完成',
        );
      case 'CREATE_INDEX':
      case 'DROP_INDEX':
        // CONCURRENTLY 关键字 → 允许并发 DML（PG 唯一的轻量 DDL 路径）。
        if (RegExp(r'\bCONCURRENTLY\b', caseSensitive: false).hasMatch(ddl)) {
          return DdlAlgorithmResult(
            algorithm: DdlAlgorithm.inplace,
            lockType: 'PG SHARE UPDATE EXCLUSIVE 锁（允许并发 DML，耗时较长）',
            concurrencyImpact: ConcurrencyImpact.allowsConcurrentDml,
            note: 'PG $ddlType CONCURRENTLY 不阻塞写，但构建耗时较长',
          );
        }
        // 普通 CREATE/DROP INDEX → SHARE 锁（阻塞写）。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          lockType: 'PG SHARE 锁（阻塞写，允许读）',
          concurrencyImpact: ConcurrencyImpact.blocksDml,
          note: 'PG $ddlType 普通（SHARE 锁，阻塞写）。'
              '可用 CONCURRENTLY 避免阻塞写',
        );
      case 'ALTER_COLUMN':
      case 'ADD_COLUMN':
      case 'DROP_COLUMN':
        // PG ALTER TABLE 所有 form 都拿 ACCESS EXCLUSIVE（最强制锁，阻塞读写）。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          lockType: 'PG ACCESS EXCLUSIVE 锁（阻塞读写，最强制锁）',
          concurrencyImpact: ConcurrencyImpact.blocksDml,
          note: 'PG ALTER TABLE $ddlType 拿 ACCESS EXCLUSIVE（阻塞读写）。'
              '建议低峰期执行',
        );
      default:
        // CREATE_TABLE / UNKNOWN / 未覆盖 → 保守 unknown。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.unknown,
          concurrencyImpact: ConcurrencyImpact.unknown,
          note: 'PG 未识别的 DDL 类型（$ddlType），保守处理',
        );
    }
  }

  /// SQLite 锁语义推断（B4）。
  ///
  /// SQLite 是单文件库，靠文件锁（RESERVED → PENDING → EXCLUSIVE）+ WAL。
  /// 所有 DDL 都阻塞其他写连接（WAL 的读写分离在 schema change 时失效）。
  /// 无 CONCURRENTLY 等价物，锁模型与版本无关。
  ///
  /// 行为映射（SQLite 无 ALGORITHM 概念，按行为）：
  /// - RENAME / TRUNCATE / DROP / ADD COLUMN(默认值) → 瞬时元数据改 → metadataOnly
  /// - DROP COLUMN / 改类型 / CREATE INDEX → table rebuild / 扫描建索引 → copy
  static DdlAlgorithmResult _inferSqlite(String ddl, String ddlType) {
    switch (ddlType) {
      case 'TRUNCATE_TABLE':
      case 'DROP_TABLE':
      case 'RENAME_TABLE':
      case 'RENAME_COLUMN':
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: 'SQLite 元数据锁（瞬时）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: 'SQLite $ddlType 只改元数据，瞬时完成',
        );
      case 'ADD_COLUMN':
        // ADD COLUMN 带默认值 → 瞬时元数据改；不带默认值的 NOT NULL 列会报错，
        // 但锁语义仍是元数据级（不重写数据）。统一归 metadataOnly。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: 'SQLite 元数据锁（ADD COLUMN 瞬时）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: 'SQLite ADD COLUMN 只改元数据，瞬时完成',
        );
      case 'CREATE_INDEX':
      case 'DROP_INDEX':
        // CREATE INDEX 扫描全表建索引 → 阻塞写连接。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          lockType: 'SQLite EXCLUSIVE 锁（建索引期间阻塞写）',
          concurrencyImpact: ConcurrencyImpact.blocksDml,
          note: 'SQLite $ddlType 扫描全表，阻塞其他写连接',
        );
      case 'ALTER_COLUMN':
      case 'DROP_COLUMN':
        // SQLite 改列类型 / DROP COLUMN 是 table rebuild（建新表+拷贝+改名）。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          lockType: 'SQLite EXCLUSIVE 锁（table rebuild，阻塞写）',
          concurrencyImpact: ConcurrencyImpact.blocksDml,
          note: 'SQLite $ddlType 是 table rebuild（建新表+拷贝+改名），阻塞写',
        );
      default:
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.unknown,
          concurrencyImpact: ConcurrencyImpact.unknown,
          note: 'SQLite 未识别的 DDL 类型（$ddlType），保守处理',
        );
    }
  }

  /// 解析 MySQL 版本字符串 → (major, minor, patch)。
  ///
  /// '8.0.32' → (8,0,32)；'5.7.43' → (5,7,43)。
  /// MariaDB（主版本 ≥ 10，如 '10.5.8-MariaDB'）→ null（INSTANT 支持版本不同，
  /// 本阶段跳过，独立后续）。
  /// null / 无法解析 → null。
  static (int, int, int)? _parseMysqlVersion(String? version) {
    if (version == null) return null;
    // 匹配开头的主.次.修订（忽略 -log / -MariaDB 等后缀）。
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    // MariaDB 主版本号 ≥ 10，跳过（独立后续）。
    if (major >= 10) return null;
    return (major, minor, patch);
  }

  /// 检测显式 ALGORITHM= 子句。用户意图优先于默认推断。
  ///
  /// 同时匹配可选的 LOCK= 子句以细化并发影响：
  /// - `ALGORITHM=INSTANT` → instant
  /// - `ALGORITHM=INPLACE, LOCK=NONE` → inplace + 允许并发
  /// - `ALGORITHM=COPY` → copy + 阻塞
  /// - `ALGORITHM=DEFAULT` → unknown（让 MySQL 自选，无法静态确定）
  static DdlAlgorithmResult? _parseExplicitAlgorithm(String ddl) {
    final upper = ddl.toUpperCase();
    final algoMatch = RegExp(r'ALGORITHM\s*=\s*(\w+)').firstMatch(upper);
    if (algoMatch == null) return null;
    final algo = algoMatch.group(1)!;

    final lockMatch = RegExp(r'LOCK\s*=\s*(\w+)').firstMatch(upper);
    final lock = lockMatch?.group(1);

    final algorithm = switch (algo) {
      'INSTANT' => DdlAlgorithm.instant,
      'INPLACE' => DdlAlgorithm.inplace,
      'COPY' => DdlAlgorithm.copy,
      // DEFAULT / 其它：用户让 MySQL 自选，无法静态确定 → unknown。
      _ => DdlAlgorithm.unknown,
    };

    return DdlAlgorithmResult(
      algorithm: algorithm,
      lockType: lock != null ? '用户指定 LOCK=$lock' : null,
      concurrencyImpact: lock == 'NONE'
          ? ConcurrencyImpact.allowsConcurrentDml
          : algorithm.blocksDml
              ? ConcurrencyImpact.blocksDml
              : (algorithm == DdlAlgorithm.unknown
                  ? ConcurrencyImpact.unknown
                  : ConcurrencyImpact.none),
      note: '用户显式指定 ALGORITHM=$algo',
    );
  }

  /// DDL 类型 → algorithm 映射（核心判定表，design §5 版本矩阵）。
  static DdlAlgorithmResult _inferByDdlType(
    String ddl,
    String ddlType,
    (int, int, int) version,
  ) {
    final (major, minor, patch) = version;
    final mysqlVer = '$major.$minor.$patch';

    switch (ddlType) {
      case 'ADD_COLUMN':
        // MySQL 8.0.12+ ADD COLUMN 末尾 → INSTANT；非末尾（AFTER/FIRST）→ INPLACE。
        if (_supportsInstantAddColumn(major, minor, patch) &&
            _isAddAtEnd(ddl)) {
          return _result(
            DdlAlgorithm.instant,
            'MySQL $mysqlVer ADD COLUMN 末尾默认 INSTANT（秒级无锁）',
          );
        }
        return _result(
          DdlAlgorithm.inplace,
          _isAddAtEnd(ddl)
              ? 'MySQL $mysqlVer ADD COLUMN 走 INPLACE（LOCK=NONE 允许并发 DML）'
              : 'MySQL $mysqlVer ADD COLUMN 带 AFTER/FIRST 强制 INPLACE（允许并发 DML）',
        );

      case 'DROP_COLUMN':
        // MySQL 8.0.29+ DROP COLUMN → INSTANT；之前 → INPLACE。
        if (_supportsInstantDropColumn(major, minor, patch)) {
          return _result(
            DdlAlgorithm.instant,
            'MySQL $mysqlVer DROP COLUMN 默认 INSTANT（秒级无锁）',
          );
        }
        return _result(
          DdlAlgorithm.inplace,
          'MySQL $mysqlVer DROP COLUMN 走 INPLACE（允许并发 DML）',
        );

      case 'ALTER_COLUMN': // MODIFY COLUMN / ALTER COLUMN TYPE
        // 改字符集/排序规则 → COPY（全表重建）；改列类型 → 通常 COPY（数据需转换）。
        if (_isCharsetChange(ddl)) {
          return _result(
            DdlAlgorithm.copy,
            '改字符集/排序规则退化 COPY（全表锁，阻塞写）',
          );
        }
        return _result(
          DdlAlgorithm.copy,
          '改列类型通常退化 COPY（全表锁，建议低峰期）',
        );

      case 'CREATE_INDEX':
        return _result(
          DdlAlgorithm.inplace,
          'CREATE INDEX 走 INPLACE（LOCK=NONE 允许并发 DML，MySQL 5.6+ Online DDL）',
        );

      case 'DROP_INDEX':
        return _result(
          DdlAlgorithm.inplace,
          'DROP INDEX 走 INPLACE（允许并发 DML）',
        );

      case 'TRUNCATE_TABLE':
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: '元数据锁（瞬间，但清空数据）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: 'TRUNCATE 只改元数据，瞬间完成，但数据不可恢复',
        );

      case 'DROP_TABLE':
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: '元数据锁（瞬间，但删除表结构+数据）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: 'DROP TABLE 只改元数据，瞬间完成，但数据不可恢复',
        );

      case 'RENAME_TABLE':
      case 'RENAME_COLUMN':
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          lockType: '元数据锁（瞬间）',
          concurrencyImpact: ConcurrencyImpact.none,
          note: '重命名只改元数据，瞬间完成',
        );

      default:
        // UNKNOWN / CREATE_TABLE / 未覆盖 → 保守 unknown。
        return DdlAlgorithmResult(
          algorithm: DdlAlgorithm.unknown,
          concurrencyImpact: ConcurrencyImpact.unknown,
          note: '未识别的 DDL 类型（$ddlType），保守处理',
        );
    }
  }

  /// MySQL 8.0.12+ 支持 ADD COLUMN INSTANT。
  /// 注意：MySQL 8.0 的 INSTANT 阈值在 patch 位（minor 固定为 0）。
  static bool _supportsInstantAddColumn(int major, int minor, int patch) {
    // MySQL 8.0.12+
    if (major == 8 && minor == 0 && patch >= 12) return true;
    // MySQL 9.x+（假设延续支持）
    if (major > 8) return true;
    return false;
  }

  /// MySQL 8.0.29+ 支持 DROP COLUMN INSTANT。
  static bool _supportsInstantDropColumn(int major, int minor, int patch) {
    if (major == 8 && minor == 0 && patch >= 29) return true;
    if (major > 8) return true;
    return false;
  }

  /// ADD COLUMN 是否在末尾（无 AFTER/FIRST 子句）。
  /// 有 AFTER/FIRST 时 MySQL 强制 INPLACE（INSTANT 不支持指定位置）。
  static bool _isAddAtEnd(String ddl) {
    final upper = ddl.toUpperCase();
    return !upper.contains('AFTER') && !upper.contains('FIRST');
  }

  /// 是否为字符集/排序规则变更（CONVERT TO / CHARACTER SET / COLLATE）。
  static bool _isCharsetChange(String ddl) {
    final upper = ddl.toUpperCase();
    return upper.contains('CHARACTER SET') ||
        upper.contains('CONVERT TO') ||
        upper.contains('COLLATE');
  }

  /// 构造带标准 lockType + concurrencyImpact 的结果。
  static DdlAlgorithmResult _result(DdlAlgorithm algo, String note) {
    return DdlAlgorithmResult(
      algorithm: algo,
      lockType: _lockTypeFor(algo),
      concurrencyImpact: _concurrencyFor(algo),
      note: note,
    );
  }

  static String _lockTypeFor(DdlAlgorithm a) => switch (a) {
        DdlAlgorithm.instant => '无锁（秒级）',
        DdlAlgorithm.inplace => '元数据锁（允许并发 DML）',
        DdlAlgorithm.copy => '全表锁（阻塞所有写操作）',
        DdlAlgorithm.metadataOnly => '元数据锁（瞬间）',
        DdlAlgorithm.unknown => '未知',
      };

  static ConcurrencyImpact _concurrencyFor(DdlAlgorithm a) => switch (a) {
        DdlAlgorithm.instant => ConcurrencyImpact.none,
        DdlAlgorithm.metadataOnly => ConcurrencyImpact.none,
        DdlAlgorithm.inplace => ConcurrencyImpact.allowsConcurrentDml,
        DdlAlgorithm.copy => ConcurrencyImpact.blocksDml,
        DdlAlgorithm.unknown => ConcurrencyImpact.unknown,
      };
}
