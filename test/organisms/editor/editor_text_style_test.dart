import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/editor/editor_text_style.dart';

void main() {
  group('EditorTextStyle（编辑器字体常量）', () {
    test('字体栈使用 JetBrains Mono + 桌面回退', () {
      expect(EditorTextStyle.fontFamily, 'JetBrains Mono');
      expect(EditorTextStyle.fontFamilyFallback, contains('Consolas'));
      expect(EditorTextStyle.fontFamilyFallback, contains('Courier New'));
      expect(EditorTextStyle.fontFamilyFallback, contains('monospace'));
    });

    test('字号与行高', () {
      expect(EditorTextStyle.fontSize, 13.0);
      expect(EditorTextStyle.lineHeight, 1.6);
    });

    test('行号字号', () {
      expect(EditorTextStyle.lineNumberFontSize, 11.0);
    });

    test('baseStyle 携带字体栈', () {
      expect(EditorTextStyle.baseStyle.fontFamily, EditorTextStyle.fontFamily);
      expect(EditorTextStyle.baseStyle.fontSize, EditorTextStyle.fontSize);
      expect(EditorTextStyle.baseStyle.height, EditorTextStyle.lineHeight);
    });
  });
}
