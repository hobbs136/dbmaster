import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MockAppProvider extends AppProvider {
  @override
  bool get isAiPanelOverlay => false;
}

Widget _buildTestableWidget(Widget child) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: MockAppProvider(),
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders toolCall message', (tester) async {
    final msg = AiMessage(
      id: '1',
      isUser: false,
      content: '',
      type: AiMessageType.toolCall,
      toolName: 'execute_sql',
      toolArguments: {'sql': 'SELECT 1'},
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(
      _buildTestableWidget(
        AiMessageItem(
          message: msg,
          onExecuteSql: (_, _) {},
          onOpenInNewQuery: (_) {},
          onToggleBookmark: (_) {},
          onBranchFromMessage: (_, _) {},
        ),
      ),
    );
    // toolCall 使用折叠卡片，默认折叠，检查卡片标题
    expect(find.byIcon(LucideIcons.wrench), findsOneWidget);
  });

  testWidgets('renders toolResult message', (tester) async {
    final msg = AiMessage(
      id: '2',
      isUser: false,
      content: 'rows: 1',
      type: AiMessageType.toolResult,
      toolName: 'execute_sql',
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(
      _buildTestableWidget(
        AiMessageItem(
          message: msg,
          onExecuteSql: (_, _) {},
          onOpenInNewQuery: (_) {},
          onToggleBookmark: (_) {},
          onBranchFromMessage: (_, _) {},
        ),
      ),
    );
    // toolResult 使用可缩放容器，检查标题图标
    expect(find.byIcon(LucideIcons.wrench), findsOneWidget);
  });

  testWidgets('renders extracted SQL commands with action buttons', (
    tester,
  ) async {
    final msg = AiMessage(
      id: '3',
      isUser: false,
      content: '分析：查询订单数量\n\n<sql>\nSELECT COUNT(*) FROM orders;\n</sql>',
      extractedCommands: ['SELECT COUNT(*) FROM orders;'],
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(
      _buildTestableWidget(
        AiMessageItem(
          message: msg,
          onExecuteSql: (_, _) {},
          onOpenInNewQuery: (_) {},
          onToggleBookmark: (_) {},
          onBranchFromMessage: (_, _) {},
        ),
      ),
    );
    // 应该显示 SQL 卡片（HighlightView 使用 RichText，所以用 find.byType）
    expect(find.byType(HighlightView), findsOneWidget);
  });
}
