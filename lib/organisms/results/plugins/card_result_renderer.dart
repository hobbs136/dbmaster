// C11 · 渲染器注册化 —— 卡片渲染器（原 ResultViewMode.card 三分支之一，
// 紧凑预览）。行为与迁移前一致：消费宿主管线产物 rows。
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../card_view.dart';

class CardResultRenderer implements ResultRendererPlugin {
  const CardResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'card-result-renderer',
        icon: LucideIcons.layoutGrid,
        displayName: (l10n) => l10n.viewModeCard,
      );

  @override
  String get viewModeId => 'card';

  @override
  Set<ResultDataShape> get supportedShapes => const {ResultDataShape.sqlRows};

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    return CardView(data: renderContext.rows);
  }
}
