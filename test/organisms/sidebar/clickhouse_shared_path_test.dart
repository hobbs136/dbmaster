// C18 · ClickHouse 侧边栏共享路径守卫（§11 泛 SQL 路径验收的类型层证据）。
//
// CH 现状 = 零专属 UI（无 builder/无内联分支/零测试，c04 §11）：树与菜单
// 全部走 sidebar_tree 共享泛 SQL 装配 + port 能力位门控。CH adapter 是
// gateway-backed（全代理网关，无本地驱动）——T29 第三批（2026-08-26）
// 已收编到 /api/gw 壳（clickhouse_adapter.dart），真库链路验证见
// integration_test/clickhouse_integration_test.dart；本文件锚定「C18 重建
// 后 CH 仍零专属、共享路径成员资格与能力位不被破坏」。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/services/ports/capability_table.dart';

void main() {
  group('ClickHouse 侧边栏共享路径（c04 §11）', () {
    test('CH ∈ isSQL —— 共享泛 SQL 树装配成员资格（§2.5 路径）', () {
      expect(DatabaseType.clickhouse.isSQL, isTrue,
          reason: 'CH 掉出 isSQL 集合 = 库级子树装配静默消失（回归守卫）');
    });

    test('CH 无 per-type 侧边栏插件 —— 泛 SQL 分支零专属（现状锚定）', () {
      final plugins = defaultPluginRegistry.sidebarPluginsFor(
        DatabaseType.clickhouse,
      );
      // 仅 core（通用能力菜单层）——无任何 CH 专属树/能力件。
      expect(
        plugins.where((p) => p.descriptor.supportedTypes.isNotEmpty),
        isEmpty,
        reason: 'CH 出现 per-type 插件 = 超出 §11 泛 SQL 裁定，需更新矩阵',
      );
    });

    test('CH 能力位（port 真值表）—— 共享菜单门控数据面不缺位', () {
      // 共享泛 SQL 路径消费的核心位（§12.2 getter 表 ch 列镜像）
      expect(CapabilityTable.has(DatabaseType.clickhouse, 'sql.query'), isTrue);
      expect(CapabilityTable.has(DatabaseType.clickhouse, 'view.list'), isTrue);
      expect(
        CapabilityTable.has(DatabaseType.clickhouse, 'table.editColumns'),
        isTrue,
      );
      // CH 专有预留位（c01 §3：ch.dictionary 预留恒 false）
      expect(
        CapabilityTable.has(DatabaseType.clickhouse, 'ch.dictionary'),
        isFalse,
      );
    });
  });
}
