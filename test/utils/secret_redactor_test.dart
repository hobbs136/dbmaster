import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/secret_redactor.dart';

void main() {
  test('masks password= and pwd=', () {
    expect(
      redactSecrets('Server=x;Password=secret123;User=u'),
      'Server=x;***;User=u',
    );
    expect(redactSecrets('pwd=hunter2'), '***');
  });

  test('masks quoted passwords containing spaces', () {
    expect(redactSecrets("Password='my complex pass'"), '***');
    expect(redactSecrets('pwd="ab cd"'), '***');
  });

  test('masks user:pass@host in connection uri', () {
    expect(
      redactSecrets('mysql://root:p@ssw0rd@127.0.0.1:3306'),
      'mysql://root:***@127.0.0.1:3306',
    );
  });

  test('masks Authorization Bearer', () {
    expect(
      redactSecrets('Authorization: Bearer abc.def.ghi'),
      'Authorization: Bearer ***',
    );
  });

  test('masks api_key and apikey', () {
    expect(redactSecrets('api_key=sk-test123'), '***');
    expect(redactSecrets('apikey=xyz'), '***');
  });

  test('SQL is NOT masked unless redactSql=true', () {
    const sql = "INSERT INTO t VALUES ('secret-data')";
    expect(redactSecrets(sql), sql);
    expect(redactSecrets(sql, redactSql: true), contains('VALUES (***)'));
  });
}
