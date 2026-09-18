import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/ai_tree_node_context.dart';

void main() {
  group('AiTreeNodeContext', () {
    test('displayLabel 包含数据库和节点名', () {
      const ctx = AiTreeNodeContext(
        type: AiTreeNodeType.table,
        connectionId: 'conn-1',
        databaseName: 'my_db',
        nodeName: 'users',
      );
      expect(ctx.displayLabel, 'my_db.users');
    });

    test('displayLabel 仅使用节点名当数据库为空', () {
      const ctx = AiTreeNodeContext(
        type: AiTreeNodeType.connection,
        connectionId: 'conn-1',
        nodeName: 'localhost',
      );
      expect(ctx.displayLabel, 'localhost');
    });

    test('isMySqlDialect 为 true', () {
      const ctx = AiTreeNodeContext(
        type: AiTreeNodeType.table,
        connectionId: 'conn-1',
        databaseName: 'my_db',
        nodeName: 'users',
      );
      expect(ctx.isMySqlDialect, isTrue);
    });
  });
}
