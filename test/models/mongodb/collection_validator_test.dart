import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/collection_validator.dart';

void main() {
  group('CollectionValidator', () {
    test('should create instance with no validator', () {
      final validator = CollectionValidator.none('test_collection');

      expect(validator.collectionName, equals('test_collection'));
      expect(validator.validatorType, equals(ValidatorType.none));
      expect(validator.jsonSchema, isNull);
      expect(validator.validationLevel, equals(ValidationLevel.off));
      expect(validator.validationAction, equals(ValidationAction.warn));
      expect(validator.hasRules, isFalse);
    });

    test('should create instance with JSON schema', () {
      final schema = {
        'bsonType': 'object',
        'required': ['name'],
        'properties': {
          'name': {'bsonType': 'string'},
        },
      };

      final validator = CollectionValidator.withSchema(
        collectionName: 'users',
        schema: schema,
        level: ValidationLevel.strict,
        action: ValidationAction.error,
      );

      expect(validator.collectionName, equals('users'));
      expect(validator.validatorType, equals(ValidatorType.jsonSchema));
      expect(validator.jsonSchema, isNotNull);
      expect(validator.validationLevel, equals(ValidationLevel.strict));
      expect(validator.validationAction, equals(ValidationAction.error));
      expect(validator.hasRules, isTrue);
    });

    test('should serialize to JSON', () {
      final validator = CollectionValidator(
        collectionName: 'products',
        validatorType: ValidatorType.jsonSchema,
        jsonSchema: {
          '\$jsonSchema': {
            'bsonType': 'object',
            'required': ['sku'],
          },
        },
        validationLevel: ValidationLevel.moderate,
        validationAction: ValidationAction.warn,
      );

      final json = validator.toJson();
      expect(json['collectionName'], equals('products'));
      expect(json['validatorType'], equals('jsonSchema'));
      expect(json['validationLevel'], equals('moderate'));
      expect(json['validationAction'], equals('warn'));
    });

    test('should deserialize from JSON', () {
      final json = {
        'collectionName': 'orders',
        'validatorType': 'jsonSchema',
        'jsonSchema': {
          '\$jsonSchema': {
            'bsonType': 'object',
            'required': ['orderId'],
          },
        },
        'validationLevel': 'strict',
        'validationAction': 'error',
      };

      final parsed = CollectionValidator.fromJson(json);
      expect(parsed.collectionName, equals('orders'));
      expect(parsed.validatorType, equals(ValidatorType.jsonSchema));
      expect(parsed.hasRules, isTrue);
      expect(parsed.validationLevel, equals(ValidationLevel.strict));
    });

    test('should generate collMod command correctly', () {
      final validator = CollectionValidator.withSchema(
        collectionName: 'test',
        schema: {
          'bsonType': 'object',
          'required': ['field'],
        },
        level: ValidationLevel.strict,
        action: ValidationAction.error,
      );

      final command = validator.toCollModCommand();
      expect(command['validator'], isNotNull);
      expect(command['validationLevel'], equals('strict'));
      expect(command['validationAction'], equals('error'));
    });

    test('should generate collMod command for removing validator', () {
      final validator = CollectionValidator.none('test');
      final command = validator.toCollModCommand();

      expect(command['validator'], equals({}));
      expect(command['validationLevel'], equals('off'));
    });

    test('should handle all validation levels', () {
      for (final level in ValidationLevel.values) {
        final validator = CollectionValidator(
          collectionName: 'test',
          validatorType: ValidatorType.none,
          validationLevel: level,
        );
        expect(validator.validationLevel, equals(level));
      }
    });

    test('should handle all validation actions', () {
      for (final action in ValidationAction.values) {
        final validator = CollectionValidator(
          collectionName: 'test',
          validatorType: ValidatorType.none,
          validationAction: action,
        );
        expect(validator.validationAction, equals(action));
      }
    });
  });

  group('CollectionValidator Edge Cases', () {
    test('should throw on jsonSchema with ValidatorType.none', () {
      expect(
        () => CollectionValidator(
          collectionName: 'test',
          validatorType: ValidatorType.none,
          jsonSchema: {'\$jsonSchema': {}},
        ),
        throwsAssertionError,
      );
    });

    test('should throw on null jsonSchema with ValidatorType.jsonSchema', () {
      expect(
        () => CollectionValidator(
          collectionName: 'test',
          validatorType: ValidatorType.jsonSchema,
          jsonSchema: null,
        ),
        throwsAssertionError,
      );
    });

    test('should handle complex nested schema', () {
      final complexSchema = {
        'bsonType': 'object',
        'required': ['name', 'email'],
        'properties': {
          'name': {
            'bsonType': 'string',
            'minLength': 2,
            'maxLength': 50,
          },
          'email': {
            'bsonType': 'string',
            'pattern': r'^[\w-\.]+@[\w-]+\.[a-z]{2,4}$',
          },
          'age': {
            'bsonType': 'int',
            'minimum': 0,
            'maximum': 120,
          },
        },
      };

      final validator = CollectionValidator.withSchema(
        collectionName: 'users',
        schema: complexSchema,
      );

      expect(validator.hasRules, isTrue);
      expect(validator.jsonSchema?['\$jsonSchema'], equals(complexSchema));
    });

    test('should handle schema with no required fields', () {
      final schema = {
        'bsonType': 'object',
        'properties': {
          'optionalField': {'bsonType': 'string'},
        },
      };

      final validator = CollectionValidator.withSchema(
        collectionName: 'logs',
        schema: schema,
        level: ValidationLevel.moderate,
      );

      expect(validator.validationLevel, equals(ValidationLevel.moderate));
      expect(validator.validationAction, equals(ValidationAction.error)); // default
    });
  });

  group('ValidatorType', () {
    test('should have all expected values', () {
      expect(ValidatorType.jsonSchema, isNotNull);
      expect(ValidatorType.none, isNotNull);
    });
  });

  group('ValidationLevel', () {
    test('should have all expected values', () {
      expect(ValidationLevel.strict, isNotNull);
      expect(ValidationLevel.moderate, isNotNull);
      expect(ValidationLevel.off, isNotNull);
    });
  });

  group('ValidationAction', () {
    test('should have all expected values', () {
      expect(ValidationAction.error, isNotNull);
      expect(ValidationAction.warn, isNotNull);
    });
  });
}
