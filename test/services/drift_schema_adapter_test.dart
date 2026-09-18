//! Unit tests for [driftSchemaJsonToDesktopSnapshot]. The server-side
//! canonical shape (Rust `SchemaSnapshot` per `crates/drift/src/snapshot.rs`)
//! must round-trip into the desktop's flat-list model so the existing
//! SchemaDiffTree / SchemaDiffDetail widgets can render drift.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/drift_schema_adapter.dart';

String _snapshotJson() => jsonEncode({
      'database': 'shop',
      'db_type': 'postgres',
      'tables': {
        'public.users': {
          'schema': 'public',
          'name': 'users',
          'columns': {
            'id': {
              'name': 'id',
              'ordinal': 1,
              'data_type': 'bigint',
              'is_nullable': false,
              'column_default': null,
              'char_max_length': null,
              'numeric_precision': 64,
              'numeric_scale': 0,
            },
            'email': {
              'name': 'email',
              'ordinal': 2,
              'data_type': 'varchar',
              'is_nullable': false,
              'column_default': null,
              'char_max_length': 255,
              'numeric_precision': null,
              'numeric_scale': null,
            },
          },
          'primary_key': {'name': 'users_pkey', 'columns': ['id']},
          'indexes': {
            'users_email_key': {
              'name': 'users_email_key',
              'columns': ['email'],
              'is_unique': true,
            },
          },
          'foreign_keys': {},
        },
        'public.orders': {
          'schema': 'public',
          'name': 'orders',
          'columns': {
            'id': {
              'name': 'id', 'ordinal': 1, 'data_type': 'bigint',
              'is_nullable': false, 'column_default': null,
              'char_max_length': null, 'numeric_precision': 64,
              'numeric_scale': 0,
            },
          },
          'primary_key': {'name': 'orders_pkey', 'columns': ['id']},
          'indexes': {},
          'foreign_keys': {},
        },
      },
    });

void main() {
  group('driftSchemaJsonToDesktopSnapshot', () {
    test('parses tables, columns, indexes, PKs', () {
      final snap = driftSchemaJsonToDesktopSnapshot(
        connectionId: 'c1',
        connectionName: 'src',
        schemaJson: _snapshotJson(),
      );

      expect(snap.connectionId, equals('c1'));
      expect(snap.databaseName, equals('shop'));
      // Two tables, sorted by qualified name.
      expect(snap.tables.map((t) => t.name).toList(),
          equals(['public.orders', 'public.users']));

      final users = snap.tables.firstWhere((t) => t.name == 'public.users');
      // Columns preserve ordinal order, not BTreeMap alphabetical.
      expect(users.columns.map((c) => c.name).toList(), equals(['id', 'email']));
      // PK flagged on the column row (used by _compareColumns).
      final idCol = users.columns.firstWhere((c) => c.name == 'id');
      expect(idCol.isPrimaryKey, isTrue);
      final emailCol = users.columns.firstWhere((c) => c.name == 'email');
      expect(emailCol.isPrimaryKey, isFalse);
      // Type reconstruction merges length/precision into a readable string.
      expect(emailCol.type, equals('varchar(255)'));
      expect(idCol.type, equals('bigint(64)'));

      expect(users.indexes.length, equals(1));
      final idx = users.indexes.single;
      expect(idx.name, equals('users_email_key'));
      expect(idx.columns, equals(['email']));
      expect(idx.isUnique, isTrue);
    });

    test('respects databaseNameOverride', () {
      final snap = driftSchemaJsonToDesktopSnapshot(
        connectionId: 'c1',
        connectionName: 'src',
        schemaJson: _snapshotJson(),
        databaseNameOverride: 'custom-db',
      );
      expect(snap.databaseName, equals('custom-db'));
    });

    test('respects capturedAtIso', () {
      final snap = driftSchemaJsonToDesktopSnapshot(
        connectionId: 'c1',
        connectionName: 'src',
        schemaJson: _snapshotJson(),
        capturedAtIso: '2026-08-01T12:34:56Z',
      );
      expect(snap.capturedAt.toUtc(), equals(DateTime.utc(2026, 8, 1, 12, 34, 56)));
    });

    test('throws FormatException on non-object root', () {
      expect(
        () => driftSchemaJsonToDesktopSnapshot(
          connectionId: 'c1', connectionName: 'src', schemaJson: '[]',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on non-json', () {
      expect(
        () => driftSchemaJsonToDesktopSnapshot(
          connectionId: 'c1', connectionName: 'src', schemaJson: 'not json',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty tables map yields empty snapshot (no crash)', () {
      final empty = jsonEncode({
        'database': 'empty', 'db_type': 'mysql', 'tables': {},
      });
      final snap = driftSchemaJsonToDesktopSnapshot(
        connectionId: 'c1', connectionName: 'src', schemaJson: empty,
      );
      expect(snap.tables, isEmpty);
    });

    test('skips malformed table entries without crashing the whole snapshot',
        () {
      final mixed = jsonEncode({
        'database': 'shop',
        'db_type': 'mysql',
        'tables': {
          'good': {
            'columns': {
              'id': {'ordinal': 1, 'data_type': 'int', 'is_nullable': false}
            },
            'primary_key': null,
            'indexes': {},
          },
          // Foreign-key map shape doesn't matter to the adapter; but if the
          // table value is a non-object (string), it must be skipped.
          'bad': 'not-an-object',
        },
      });
      final snap = driftSchemaJsonToDesktopSnapshot(
        connectionId: 'c1', connectionName: 'src', schemaJson: mixed,
      );
      expect(snap.tables.length, equals(1));
      expect(snap.tables.single.name, equals('good'));
    });
  });
}
