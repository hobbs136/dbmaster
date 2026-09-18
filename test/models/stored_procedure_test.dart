import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/stored_procedure.dart';

void main() {
  group('ProcedureType', () {
    test('has 2 values', () {
      expect(ProcedureType.values.length, 2);
    });
  });

  group('ProcedureParameter', () {
    test('defaults to IN mode', () {
      final p = ProcedureParameter(name: 'id_param', dataType: 'INT');
      expect(p.name, 'id_param');
      expect(p.dataType, 'INT');
      expect(p.mode, 'IN');
    });

    test('OUT parameter', () {
      final p = ProcedureParameter(
        name: 'result',
        dataType: 'VARCHAR',
        mode: 'OUT',
      );
      expect(p.mode, 'OUT');
    });

    test('INOUT parameter', () {
      final p = ProcedureParameter(
        name: 'count',
        dataType: 'INT',
        mode: 'INOUT',
      );
      expect(p.mode, 'INOUT');
    });

    test('toString format', () {
      final p = ProcedureParameter(name: 'id', dataType: 'INT', mode: 'IN');
      expect(p.toString(), 'IN id INT');
    });

    test('copyWith updates fields', () {
      final p = ProcedureParameter(name: 'x', dataType: 'INT');
      final copied = p.copyWith(name: 'y', mode: 'OUT');
      expect(copied.name, 'y');
      expect(copied.mode, 'OUT');
      expect(copied.dataType, 'INT');
    });
  });

  group('StoredProcedure', () {
    final proc = StoredProcedure(
      name: 'get_users',
      type: ProcedureType.procedure,
      parameters: [
        ProcedureParameter(name: 'min_age', dataType: 'INT'),
        ProcedureParameter(name: 'status', dataType: 'VARCHAR', mode: 'OUT'),
      ],
      definition:
          'CREATE PROCEDURE get_users(IN min_age INT, OUT status VARCHAR(20)) ...',
      createdAt: DateTime(2026, 6, 1),
      modifiedAt: DateTime(2026, 6, 6),
      body: 'SELECT * FROM users WHERE age >= min_age;',
    );

    test('fields are correctly set', () {
      expect(proc.name, 'get_users');
      expect(proc.type, ProcedureType.procedure);
      expect(proc.parameters.length, 2);
      expect(proc.returnType, isNull); // not a function
    });

    test('function type with returnType', () {
      final func = StoredProcedure(
        name: 'calc_total',
        type: ProcedureType.function,
        returnType: 'DECIMAL(10,2)',
      );
      expect(func.type, ProcedureType.function);
      expect(func.returnType, 'DECIMAL(10,2)');
    });

    test('copyWith preserves unchanged fields', () {
      final copied = proc.copyWith();
      expect(copied.name, proc.name);
      expect(copied.type, proc.type);
    });

    test('copyWith updates specified fields', () {
      final copied = proc.copyWith(
        name: 'get_active_users',
        definition: 'CREATE PROCEDURE get_active_users(...)',
      );
      expect(copied.name, 'get_active_users');
      expect(copied.definition, 'CREATE PROCEDURE get_active_users(...)');
      expect(copied.parameters.length, 2); // unchanged
    });

    test('copyWith replaces parameters', () {
      final newParams = [ProcedureParameter(name: 'id', dataType: 'INT')];
      final copied = proc.copyWith(parameters: newParams);
      expect(copied.parameters.length, 1);
      expect(copied.parameters.first.name, 'id');
    });
  });
}
