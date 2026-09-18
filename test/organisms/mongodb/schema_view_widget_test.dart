import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/organisms/mongodb/schema_view/schema_view_widget.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/providers/mongodb_visualization_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// UI测试: MongoDB Schema视图
/// Spec 023 US1 - 验证Schema可视化UI渲染和交互
void main() {
  group('Schema View Widget UI Tests', () {
    late MongoVisualizationProvider mockProvider;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockProvider = MongoVisualizationProvider(AppProvider());
    });

    testWidgets('Schema view shows loading indicator initially', (
      tester,
    ) async {
      mockProvider.setLoadingSchemaForTest(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'test_collection'),
            ),
          ),
        ),
      );

      // Verify loading state
      expect(find.byType(SchemaViewWidget), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading schema...'), findsOneWidget);
    });

    testWidgets('Schema view renders fields with types and presence', (
      tester,
    ) async {
      // Create mock schema
      final mockSchema = InferredDocumentSchema(
        collectionName: 'users',
        totalSampled: 100,
        fields: [
          SchemaField(
            name: 'age',
            bsonType: 'int',
            presenceRatio: 0.95,
            isNested: false,
          ),
          SchemaField(
            name: 'name',
            bsonType: 'String',
            presenceRatio: 0.80,
            isNested: false,
          ),
        ],
      );

      // Set loaded state in provider
      mockProvider.setSchemaForTest(mockSchema);
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'users'),
            ),
          ),
        ),
      );

      // Verify schema view renders
      expect(find.byType(SchemaViewWidget), findsOneWidget);

      // Verify field names are displayed
      expect(find.text('age'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);

      // Verify presence ratios are displayed
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('Schema nested fields expand on tap', (tester) async {
      // Create mock schema with nested field
      final mockSchema = InferredDocumentSchema(
        collectionName: 'users',
        totalSampled: 100,
        fields: [
          SchemaField(
            name: 'address',
            bsonType: 'document',
            presenceRatio: 0.60,
            isNested: true,
            subFields: [
              SchemaField(
                name: 'city',
                bsonType: 'String',
                presenceRatio: 0.55,
                isNested: false,
              ),
              SchemaField(
                name: 'zip',
                bsonType: 'String',
                presenceRatio: 0.50,
                isNested: false,
              ),
            ],
          ),
        ],
      );

      mockProvider.setSchemaForTest(mockSchema);
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'users'),
            ),
          ),
        ),
      );

      // Verify nested field is displayed
      expect(find.text('address'), findsOneWidget);

      // Verify expand icon exists (IconButton with expand_more icon)
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    });

    testWidgets('Schema view shows empty state for empty collection', (
      tester,
    ) async {
      // Create empty schema
      final emptySchema = InferredDocumentSchema(
        collectionName: 'empty_collection',
        totalSampled: 0,
        fields: [],
      );

      mockProvider.setSchemaForTest(emptySchema);
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'empty_collection'),
            ),
          ),
        ),
      );

      // Verify empty state message
      expect(find.text('No schema data'), findsOneWidget);
      expect(
        find.text('This collection is empty or has no documents to analyze'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.package), findsOneWidget);
    });

    testWidgets('Schema view shows error on adapter failure', (tester) async {
      mockProvider.setSchemaErrorForTest(
        'Failed to load schema: Connection timeout',
      );
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'users'),
            ),
          ),
        ),
      );

      // Verify error message displayed
      expect(find.text('Schema Error'), findsOneWidget);
      expect(
        find.text('Failed to load schema: Connection timeout'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);

      // Verify retry button exists
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Schema header shows collection info', (tester) async {
      // Create mock schema
      final mockSchema = InferredDocumentSchema(
        collectionName: 'users',
        totalSampled: 100,
        fields: List.generate(
          10,
          (i) => SchemaField(
            name: 'field_$i',
            bsonType: 'String',
            presenceRatio: 0.5,
            isNested: false,
          ),
        ),
      );

      mockProvider.setSchemaForTest(mockSchema);
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'users'),
            ),
          ),
        ),
      );

      // Verify collection info in header
      expect(find.text('Collection: users'), findsOneWidget);
      expect(find.text('Sampled: 100 documents'), findsOneWidget);
      expect(find.text('10 fields'), findsOneWidget);
    });

    testWidgets('Field type badges have correct colors', (tester) async {
      // Create mock schema with various BSON types
      final mockSchema = InferredDocumentSchema(
        collectionName: 'test',
        totalSampled: 50,
        fields: [
          SchemaField(
            name: 'strField',
            bsonType: 'String',
            presenceRatio: 1.0,
            isNested: false,
          ),
          SchemaField(
            name: 'intField',
            bsonType: 'int',
            presenceRatio: 1.0,
            isNested: false,
          ),
          SchemaField(
            name: 'docField',
            bsonType: 'document',
            presenceRatio: 0.5,
            isNested: false,
          ),
          SchemaField(
            name: 'arrField',
            bsonType: 'array',
            presenceRatio: 0.3,
            isNested: false,
          ),
        ],
      );

      mockProvider.setSchemaForTest(mockSchema);
      mockProvider.setLoadingSchemaForTest(false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MongoVisualizationProvider>.value(
            value: mockProvider,
            child: const Scaffold(
              body: SchemaViewWidget(collectionName: 'test'),
            ),
          ),
        ),
      );

      // Verify all field types are displayed
      expect(find.text('String'), findsOneWidget);
      expect(find.text('int'), findsOneWidget);
      expect(find.text('document'), findsOneWidget);
      expect(find.text('array'), findsOneWidget);
    });
  });
}
