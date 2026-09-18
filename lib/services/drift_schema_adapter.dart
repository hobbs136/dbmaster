//! Adapter: Server-side drift `schema_json` → desktop [SchemaSnapshot].
//!
//! Why this exists: the Server's drift collector (`crates/drift/src/snapshot.rs`)
//! and the desktop's Schema Diff feature (`lib/models/schema_diff_models.dart`)
//! use DIFFERENT snapshot shapes. The Server's is a BTreeMap-keyed canonical
//! struct (only tables/columns/indexes/keys — no views, procs, or CREATE
//! statements, per ADR §4.3.1 D5). The desktop's is a flat list of `DbTable`
//! with optional views / procs / CREATE statements used by the DDL preview
//! panel. To reuse the desktop's `SchemaDiffTree` / `SchemaDiffDetail` widgets
//! to render drift between two Server snapshots, we adapt the Server shape
//! into the desktop shape (lossy: views/procs/CREATE statements are absent).
//!
//! The desktop's `SchemaDiffService.compareSnapshots` reads only
//! `tables[].columns` and `tables[].indexes` to compute table/column/index
//! diffs, so the lossy fields do not affect diff correctness — only the DDL
//! preview panel will be empty.

import 'dart:convert';

import '../models/database_models.dart';
import '../models/schema_diff_models.dart';

/// Convert a Server-side `schema_json` string (canonical Rust `SchemaSnapshot`
/// serialised via serde) into a desktop [SchemaSnapshot] usable by the existing
/// Schema Diff widgets.
///
/// [connectionName] / [databaseNameOverride] are cosmetic — the desktop model
/// expects them for display. The Server snapshot's own `database` field is
/// used as the database label when no override is supplied.
///
/// Throws [FormatException] when [schemaJson] is not valid JSON or is missing
/// the expected top-level fields.
SchemaSnapshot driftSchemaJsonToDesktopSnapshot({
  required String connectionId,
  required String connectionName,
  required String schemaJson,
  String? databaseNameOverride,
  String? capturedAtIso,
}) {
  final dynamic decoded = jsonDecode(schemaJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'drift schema_json: expected JSON object at the root',
    );
  }
  final database =
      databaseNameOverride ?? (decoded['database'] as String?) ?? '<unknown>';

  final tablesRaw = decoded['tables'];
  if (tablesRaw != null && tablesRaw is! Map<String, dynamic>) {
    throw const FormatException(
      'drift schema_json: "tables" must be an object keyed by "schema.name"',
    );
  }
  final tablesMap = (tablesRaw as Map<String, dynamic>?) ?? const {};

  final tables = <DbTable>[];
  for (final entry in tablesMap.entries) {
    final tableJson = entry.value;
    if (tableJson is! Map<String, dynamic>) continue;
    tables.add(_parseTable(entry.key, tableJson));
  }

  // Sort by qualified name so the diff tree is stable across the two snapshots
  // being compared (independent of map iteration order).
  tables.sort((a, b) => a.name.compareTo(b.name));

  return SchemaSnapshot(
    connectionId: connectionId,
    connectionName: connectionName,
    databaseName: database,
    capturedAt: capturedAtIso != null
        ? (DateTime.tryParse(capturedAtIso) ?? DateTime.now())
        : DateTime.now(),
    tables: tables,
    // Server v1 collects no views / procedures / CREATE statements
    // (ADR §4.3.1 D5). The diff tree gracefully omits these sections.
  );
}

DbTable _parseTable(String qualifiedName, Map<String, dynamic> json) {
  // The map key is the canonical "{schema}.{name}" qualified form; use it as
  // the table identity so two snapshots produced by different collectors still
  // line up.
  final pkColumns = _parsePrimaryKeyColumns(json['primary_key']);
  final columns = _parseColumns(json['columns'], pkColumns.toSet());
  final indexes = _parseIndexes(json['indexes']);
  return DbTable(name: qualifiedName, columns: columns, indexes: indexes);
}

List<DbColumn> _parseColumns(dynamic columnsRaw, Set<String> pkNames) {
  if (columnsRaw is! Map<String, dynamic>) return const [];
  // Order columns by `ordinal` (information_schema position). The Server's
  // BTreeMap is keyed by name; sort by ordinal to preserve table DDL order.
  final entries = columnsRaw.entries
      .whereType<MapEntry<String, dynamic>>()
      .where((e) => e.value is Map<String, dynamic>)
      .map((e) => MapEntry(e.key, e.value as Map<String, dynamic>))
      .toList();
  entries.sort((a, b) {
    final ai = (a.value['ordinal'] as num?)?.toInt() ?? 0;
    final bi = (b.value['ordinal'] as num?)?.toInt() ?? 0;
    return ai.compareTo(bi);
  });
  return entries.map((e) => _parseColumn(e.key, e.value, pkNames)).toList();
}

DbColumn _parseColumn(String name, Map<String, dynamic> json, Set<String> pkNames) {
  // Reconstitute a readable "type" string from the server's normalised
  // `data_type` + length/precision fields so the desktop's column chip stays
  // informative (e.g. "varchar(255)" rather than just "varchar").
  final dataType = (json['data_type'] as String?) ?? '';
  final charLen = json['char_max_length'] as num?;
  final numPrec = json['numeric_precision'] as num?;
  final numScale = json['numeric_scale'] as num?;
  final type = _formatColumnType(dataType, charLen, numPrec, numScale);
  return DbColumn(
    name: name,
    type: type,
    isPrimaryKey: pkNames.contains(name),
    isNullable: (json['is_nullable'] as bool?) ?? true,
    defaultValue: json['column_default'] as String?,
  );
}

String _formatColumnType(
  String dataType,
  num? charLen,
  num? numPrec,
  num? numScale,
) {
  if (dataType.isEmpty) return '';
  final buf = StringBuffer(dataType);
  if (charLen != null) {
    buf.write('(${charLen.toInt()})');
  } else if (numPrec != null) {
    if (numScale != null && numScale.toInt() != 0) {
      buf.write('(${numPrec.toInt()},${numScale.toInt()})');
    } else {
      buf.write('(${numPrec.toInt()})');
    }
  }
  return buf.toString();
}

List<DbIndex> _parseIndexes(dynamic indexesRaw) {
  if (indexesRaw is! Map<String, dynamic>) return const [];
  final out = <DbIndex>[];
  for (final entry in indexesRaw.entries) {
    final v = entry.value;
    if (v is! Map<String, dynamic>) continue;
    final cols = v['columns'];
    out.add(DbIndex(
      name: entry.key,
      columns: cols is List
          ? cols.whereType<String>().toList(growable: false)
          : const [],
      isUnique: (v['is_unique'] as bool?) ?? false,
    ));
  }
  return out;
}

List<String> _parsePrimaryKeyColumns(dynamic pkRaw) {
  if (pkRaw is! Map<String, dynamic>) return const [];
  final cols = pkRaw['columns'];
  if (cols is! List) return const [];
  return cols.whereType<String>().toList(growable: false);
}
