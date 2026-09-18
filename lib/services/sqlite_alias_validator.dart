// SPDX-License-Identifier: Apache-2.0
//
// spec 050：SQLite ATTACH 跨库 alias 校验器。
//
// `ATTACH DATABASE ? AS <alias>` 的 alias 是 SQLite 标识符，**不能参数化**
// （SQLite 不接受标识符占位符），必须手拼进 SQL——这是 ATTACH 路径唯一的注入面。
// 本校验器在 UI 层（attach 前）+ adapter 层（双保险）各调用一次：
// UI 层给友好 SnackBar，adapter 层防绕过。
//
// 校验规则（design §D4）：
//   1. 合法标识符：`^[a-zA-Z_][a-zA-Z0-9_]*$`
//   2. 非 SQLite 内置库名：main / temp
//   3. 非 SQLite 保留字（精简高频子集，避免过度校验误拦合法 alias）
//   4. 不与已附加库重名

/// SQLite ATTACH alias 校验结果。
///
/// 合法返回 `null`；非法返回一个本地化错误 key（对应 app_*.arb 里的条目），
/// 由 UI 层查表翻译成给用户的提示文案。
class SqliteAliasValidator {
  SqliteAliasValidator._();

  /// SQLite 内置库名，不可用作 alias（大小写不敏感）。
  static const _reserved = {'main', 'temp'};

  /// SQLite 关键字精简子集（含 ATTACH/DETACH 相关 + 常见 DDL/DML 关键字）。
  ///
  /// 取自 https://www.sqlite.org/lang_keywords.html 的保留字列表。
  /// 用全量列表会过度校验（如 `action`/`after`/`begin` 等作为 alias 其实合法，
  /// SQLite 会按上下文解析）；这里取「作为 alias 几乎肯定引发歧义」的高频子集。
  /// 遗漏的保留字由 SQLite 原生错误兜底（adapter 层抛错）。
  static const Set<String> _keywords = {
    'abort', 'action', 'add', 'after', 'all', 'alter', 'analyze', 'and', 'as',
    'asc', 'attach', 'autoincrement', 'before', 'begin', 'between', 'by',
    'cascade', 'case', 'cast', 'check', 'collate', 'column', 'commit',
    'conflict', 'constraint', 'create', 'cross', 'current', 'database',
    'default', 'deferrable', 'deferred', 'delete', 'desc', 'detach', 'distinct',
    'drop', 'each', 'else', 'end', 'escape', 'except', 'exclusive', 'exists',
    'explain', 'fail', 'for', 'foreign', 'from', 'full', 'glob', 'group',
    'having', 'if', 'ignore', 'immediate', 'in', 'index', 'indexed',
    'initially', 'inner', 'insert', 'instead', 'intersect', 'into', 'is',
    'isnull', 'join', 'key', 'left', 'like', 'limit', 'match', 'natural', 'no',
    'not', 'notnull', 'null', 'of', 'offset', 'on', 'or', 'order', 'outer',
    'primary', 'query', 'raise', 'references', 'regexp', 'reindex', 'release',
    'rename', 'replace', 'restrict', 'right', 'rollback', 'row', 'savepoint',
    'select', 'set', 'table', 'temporary', 'then', 'to', 'transaction',
    'trigger', 'union', 'unique', 'update', 'using', 'vacuum', 'values',
    'view', 'virtual', 'when', 'where',
  };

  /// 合法标识符正则：字母或下划线开头，后跟字母/数字/下划线。
  static final _validPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  /// 校验 alias。
  ///
  /// [alias] 待校验的附加库名；[existing] 当前已附加的 alias 列表（含 'main'），
  /// 用于查重。
  ///
  /// 返回 `null` 表示合法；返回非空字符串为本地化错误 key：
  ///   - `sqliteAttachAliasInvalid`：含非法字符或为空
  ///   - `sqliteAttachAliasReserved`：是 main/temp（内置库名）
  ///   - `sqliteAttachAliasKeyword`：是 SQLite 保留字
  ///   - `sqliteAttachAliasDuplicate`：与已附加库重名
  static String? validate(String alias, {List<String> existing = const []}) {
    if (alias.isEmpty || !_validPattern.hasMatch(alias)) {
      return 'sqliteAttachAliasInvalid';
    }
    final lower = alias.toLowerCase();
    if (_reserved.contains(lower)) {
      return 'sqliteAttachAliasReserved';
    }
    if (_keywords.contains(lower)) {
      return 'sqliteAttachAliasKeyword';
    }
    if (existing.any((e) => e.toLowerCase() == lower)) {
      return 'sqliteAttachAliasDuplicate';
    }
    return null;
  }
}
