import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/formatter_models.dart';

void main() {
  group('FormatterOptions', () {
    test('defaults are correct', () {
      final opts = const FormatterOptions();
      expect(opts.indentSize, 4);
      expect(opts.useTabs, false);
      expect(opts.uppercaseKeywords, true);
      expect(opts.preserveComments, true);
      expect(opts.maxLineLength, 80);
      expect(opts.commaStyle, 'trailing');
      expect(opts.alignKeywords, true);
      expect(opts.compactMode, false);
      expect(opts.breakBeforeBrackets, false);
    });

    test('toJson/fromJson round-trip', () {
      final opts = FormatterOptions(
        indentSize: 2,
        useTabs: true,
        uppercaseKeywords: false,
        commaStyle: 'leading',
        maxLineLength: 120,
      );
      final restored = FormatterOptions.fromJson(opts.toJson());
      expect(restored.indentSize, 2);
      expect(restored.useTabs, true);
      expect(restored.uppercaseKeywords, false);
      expect(restored.commaStyle, 'leading');
      expect(restored.maxLineLength, 120);
    });

    test('fromJson handles missing fields with defaults', () {
      final restored = FormatterOptions.fromJson({});
      expect(restored.indentSize, 4);
      expect(restored.uppercaseKeywords, true);
    });

    test('copyWith updates specific fields', () {
      final opts = const FormatterOptions();
      final copied = opts.copyWith(indentSize: 8, compactMode: true);
      expect(copied.indentSize, 8);
      expect(copied.compactMode, true);
      expect(copied.useTabs, false); // unchanged
    });

    test('copyWith with no args returns same values', () {
      const opts = FormatterOptions(indentSize: 6);
      final copied = opts.copyWith();
      expect(copied.indentSize, 6);
    });
  });

  group('FormatterPreset', () {
    test('toJson/fromJson round-trip', () {
      final preset = FormatterPreset(
        id: 'preset-1',
        name: 'Compact',
        description: 'Compact formatting',
        options: const FormatterOptions(indentSize: 2, compactMode: true),
        isBuiltIn: true,
        createdAt: DateTime(2026, 6, 1),
      );
      final restored = FormatterPreset.fromJson(preset.toJson());
      expect(restored.id, 'preset-1');
      expect(restored.name, 'Compact');
      expect(restored.options.indentSize, 2);
      expect(restored.isBuiltIn, true);
    });

    test('copyWith updates fields', () {
      final preset = FormatterPreset(
        id: 'p',
        name: 'N',
        description: 'D',
        options: const FormatterOptions(),
      );
      final copied = preset.copyWith(name: 'New Name');
      expect(copied.name, 'New Name');
      expect(copied.id, 'p');
    });
  });

  group('SqlHighlightStyle', () {
    test('defaults are set', () {
      const style = SqlHighlightStyle();
      expect(style.keywordColor, '#569CD6');
      expect(style.stringColor, '#CE9178');
      expect(style.numberColor, '#B5CEA8');
      expect(style.commentColor, '#6A9955');
    });

    test('toJson/fromJson round-trip', () {
      final style = SqlHighlightStyle(
        keywordColor: '#FF0000',
        stringColor: '#00FF00',
      );
      final restored = SqlHighlightStyle.fromJson(style.toJson());
      expect(restored.keywordColor, '#FF0000');
      expect(restored.stringColor, '#00FF00');
      expect(restored.numberColor, '#B5CEA8'); // default
    });
  });

  group('FormatHistory', () {
    test('toJson/fromJson round-trip', () {
      final hist = FormatHistory(
        id: 'hist-1',
        originalSql: 'select * from t',
        formattedSql: 'SELECT * FROM t;',
        options: const FormatterOptions(),
        timestamp: DateTime(2026, 6, 1),
      );
      final restored = FormatHistory.fromJson(hist.toJson());
      expect(restored.id, 'hist-1');
      expect(restored.originalSql, 'select * from t');
      expect(restored.formattedSql, 'SELECT * FROM t;');
      expect(restored.timestamp, DateTime(2026, 6, 1));
    });
  });
}
