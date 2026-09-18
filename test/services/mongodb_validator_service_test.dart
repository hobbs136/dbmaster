import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

void main() {
  group('MongoDB JSON Validation Logic', () {
    test('should validate correct JSON object', () {
      const validJson = '{\n  "name": "test"\n}';

      final result = _validateJson(validJson);

      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('should reject invalid JSON', () {
      const invalidJson = '{\n  "name": test\n}';

      final result = _validateJson(invalidJson);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('should validate JSON schema structure', () {
      const schema = '{\n  "\$jsonSchema": {\n    "bsonType": "object"\n  }\n}';

      final result = _validateJson(schema);

      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('should reject non-object JSON', () {
      const jsonArray = '[\n  {"name": "test"}\n]';

      final result = _validateJson(jsonArray);

      expect(result.isValid, isFalse);
      expect(result.error, contains('must be an object'));
    });

    test('should handle empty object', () {
      const emptyJson = '{}';

      final result = _validateJson(emptyJson);

      expect(result.isValid, isTrue);
    });

    test('should handle nested objects', () {
      const nestedJson = '{\n  "user": {\n    "name": "test",\n    "age": 30\n  }\n}';

      final result = _validateJson(nestedJson);

      expect(result.isValid, isTrue);
    });

    test('should handle arrays in values', () {
      const withArray = '{\n  "tags": ["tag1", "tag2"]\n}';

      final result = _validateJson(withArray);

      expect(result.isValid, isTrue);
    });

    test('should handle special characters in strings', () {
      // fixture 中所有反斜杠均为合法 JSON 转义（\\w、\\.），字符串含正则特殊字符。
      const withSpecialChars = r'{"pattern": "^[\\w-\\.]+@[\\w-]+\\.[a-z]{2,4}$"}';

      final result = _validateJson(withSpecialChars);

      expect(result.isValid, isTrue);
    });

    test('should handle numbers', () {
      const withNumbers = '{\n  "min": 0,\n  "max": 100,\n  "price": 19.99\n}';

      final result = _validateJson(withNumbers);

      expect(result.isValid, isTrue);
    });

    test('should handle booleans', () {
      const withBooleans = '{\n  "active": true,\n  "deleted": false\n}';

      final result = _validateJson(withBooleans);

      expect(result.isValid, isTrue);
    });

    test('should handle null values', () {
      const withNull = '{\n  "optional": null\n}';

      final result = _validateJson(withNull);

      expect(result.isValid, isTrue);
    });

    test('should reject malformed JSON syntax', () {
      const malformed = '{\n  "name": "test",\n  "age": 30\n'; // Missing closing brace

      final result = _validateJson(malformed);

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('should reject unquoted keys', () {
      const unquoted = '{name: "test"}'; // Keys must be quoted in JSON

      final result = _validateJson(unquoted);

      expect(result.isValid, isFalse);
    });

    test('should reject trailing comma', () {
      const trailingComma = '{\n  "name": "test",\n}'; // Trailing comma not allowed

      final result = _validateJson(trailingComma);

      expect(result.isValid, isFalse);
    });
  });

  group('MongoDB Validator Edge Cases', () {
    test('should handle very large JSON', () {
      final largeJson = _generateLargeJson(1000);

      final result = _validateJson(largeJson);

      expect(result.isValid, isTrue);
    });

    test('should handle deeply nested JSON', () {
      final nestedJson = _generateDeeplyNestedJson(10);

      final result = _validateJson(nestedJson);

      expect(result.isValid, isTrue);
    });

    test('should handle unicode characters', () {
      const unicodeJson = '{"name": "用户测试", "emoji": "🎉"}';

      final result = _validateJson(unicodeJson);

      expect(result.isValid, isTrue);
    });

    test('should handle escaped characters', () {
      const escapedJson = r'{"path": "C:\\Users\\test", "quote": "He said \"hello\""}';

      final result = _validateJson(escapedJson);

      expect(result.isValid, isTrue);
    });
  });
}

/// Mock validation result
class _ValidationResult {
  final bool isValid;
  final String? error;

  _ValidationResult({required this.isValid, this.error});
}

/// Validate JSON string
_ValidationResult _validateJson(String jsonString) {
  if (jsonString.trim().isEmpty) {
    return _ValidationResult(isValid: true);
  }

  try {
    final parsed = jsonDecode(jsonString);

    if (parsed is Map<String, Object?>) {
      return _ValidationResult(isValid: true);
    } else {
      return _ValidationResult(
        isValid: false,
        error: 'JSON must be an object',
      );
    }
  } catch (e) {
    return _ValidationResult(
      isValid: false,
      error: 'Invalid JSON: ${e.toString()}',
    );
  }
}

/// Generate large JSON for testing
String _generateLargeJson(int fieldCount) {
  final buffer = StringBuffer('{\n');

  for (int i = 0; i < fieldCount; i++) {
    if (i > 0) buffer.write(',\n');
    buffer.write('  "field$i": "value$i"');
  }

  buffer.write('\n}');
  return buffer.toString();
}

/// Generate deeply nested JSON
String _generateDeeplyNestedJson(int depth) {
  if (depth == 0) {
    return '{"value": "end"}';
  }

  return '{"nested": ${_generateDeeplyNestedJson(depth - 1)}}';
}
