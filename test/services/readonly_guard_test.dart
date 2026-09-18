// Feature 039 — readonly_guard 单元测试（fail-safe + fail-closed + 机器码 toString）。
// 对应 spec FR-003、contracts C1/C2/C5、quickstart 场景 6。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/readonly_guard.dart';

void main() {
  group('ensureNotReadOnly', () {
    test('throws ReadOnlyBlockedException when readOnly=true', () {
      expect(
        () => ensureNotReadOnly(true, operation: 'test'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('passes (no throw) when readOnly=false', () {
      ensureNotReadOnly(false, operation: 'test');
    });
  });

  group('ensureServerNotReadOnly (fail-closed, FR-003)', () {
    DbServer server(bool ro) => DbServer(
          id: 's',
          name: 'n',
          type: DatabaseType.mysql,
          host: 'h',
          port: 3306,
          readOnly: ro,
        );

    test('throws when server is null (fail-closed: 宁可误拒不可漏放)', () {
      expect(
        () => ensureServerNotReadOnly(null, operation: 'test'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('throws when server.readOnly=true', () {
      expect(
        () => ensureServerNotReadOnly(server(true), operation: 'test'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('passes when server.readOnly=false', () {
      ensureServerNotReadOnly(server(false), operation: 'test');
    });
  });

  group('ReadOnlyBlockedException', () {
    test('toString is machine-readable, contains no user-visible text', () {
      final e = ReadOnlyBlockedException(
        databaseType: DatabaseType.redis,
        operation: 'runCommand',
        commandName: 'FLUSHDB',
      );
      final s = e.toString();
      expect(s, contains('ReadOnlyBlockedException'));
      expect(s, contains('operation=runCommand'));
      expect(s, contains('command=FLUSHDB'));
      // 服务层异常不得含用户可见文案（FR-004：UI 映射 AppLocalizations）
      expect(s, isNot(contains('只读')));
    });

    test('carries structured fields for UI/audit', () {
      final e = ReadOnlyBlockedException(
        databaseType: DatabaseType.mysql,
        operation: 'createDatabase',
      );
      expect(e.databaseType, DatabaseType.mysql);
      expect(e.operation, 'createDatabase');
      expect(e.commandName, isNull);
    });
  });
}
