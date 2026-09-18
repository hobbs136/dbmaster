// C11 · 渲染器注册化 —— 图表渲染器（原 ResultViewMode.chart 三分支之一）。
//
// 行为与迁移前一致：消费宿主管线产物 rows/columnTypes + AI 趋势回调。
// TD 时序图特化（ts 列 → X 轴语义，见 c03 §4）随后续窗口演进。
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../chart_view.dart';

class ChartResultRenderer implements ResultRendererPlugin {
  const ChartResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'chart-result-renderer',
        icon: LucideIcons.trendingUp,
        displayName: (l10n) => l10n.viewModeChart,
      );

  @override
  String get viewModeId => 'chart';

  @override
  Set<ResultDataShape> get supportedShapes => const {ResultDataShape.sqlRows};

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    return ChartView(
      data: renderContext.rows,
      columnTypes: renderContext.columnTypes,
      onAiTrendRequest: renderContext.onAiTrendRequest,
    );
  }
}
