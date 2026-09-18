import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/mongodb_shell_parser.dart';

void main() {
  group('MongoShellQueryParser', () {
    group('parseQuery - db.collection.method() 格式', () {
      test('db.products.find().limit(100) 应正确解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().limit(100)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['filter'], <String, dynamic>{});
        expect(result['limit'], 100);
      });

      test('db.orders.find({status: "pending"}).limit(50) 应正确解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.orders.find({status: "pending"}).limit(50)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'orders');
        expect(result['filter'], {'status': 'pending'});
        expect(result['limit'], 50);
      });

      test(
        'db.users.find({age: {\$gte: 18}}, {name: 1}).limit(10) 应正确解析 filter 和 projection',
        () {
          final result = MongoShellQueryParser.parseQuery(
            'db.users.find({age: {\$gte: 18}}, {name: 1}).limit(10)',
          );
          expect(result, isNotNull);
          expect(result!['collection'], 'users');
          expect(result['filter'], {
            'age': {'\$gte': 18},
          });
          expect(result['projection'], {'name': 1});
          expect(result['limit'], 10);
        },
      );

      test('db.products.findOne() 应解析为 limit=1', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.findOne()',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['limit'], 1);
      });

      test('db.products.findOne({id: 1}) 应解析 filter', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.findOne({id: 1})',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['filter'], {'id': 1});
        expect(result['limit'], 1);
      });

      test('db.orders.countDocuments({status: "shipped"}) 应解析为 isCount', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.orders.countDocuments({status: "shipped"})',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'orders');
        expect(result['filter'], {'status': 'shipped'});
        expect(result['isCount'], true);
        expect(result['method'], 'countdocuments');
      });

      test('db.products.countDocuments() 无参数应解析为 isCount', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.countDocuments()',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['filter'], <String, dynamic>{});
        expect(result['isCount'], true);
        expect(result['method'], 'countdocuments');
      });

      test('db.products.count() 应解析为 isCount', () {
        final result = MongoShellQueryParser.parseQuery('db.products.count()');
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['isCount'], true);
        expect(result['method'], 'count');
      });

      test('db.products.estimatedDocumentCount() 应解析为 isCount', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.estimatedDocumentCount()',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['isCount'], true);
        expect(result['method'], 'estimateddocumentcount');
      });

      test(
        'db.orders.aggregate([{\$match: {status: "active"}}]) 应解析为 isAggregate',
        () {
          final result = MongoShellQueryParser.parseQuery(
            'db.orders.aggregate([{\$match: {status: "active"}}])',
          );
          expect(result, isNotNull);
          expect(result!['collection'], 'orders');
          expect(result['isAggregate'], true);
          expect(result['pipeline'], isList);
        },
      );

      test('db.users.distinct("role", {active: true}) 应解析为 isDistinct', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.users.distinct("role", {active: true})',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'users');
        expect(result['field'], 'role');
        expect(result['filter'], {'active': true});
        expect(result['isDistinct'], true);
      });
    });

    group('parseQuery - 链式调用边界', () {
      test('db.my-collection.find().limit(20) 应支持含连字符的 collection name', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.my-collection.find().limit(20)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'my-collection');
        expect(result['limit'], 20);
      });

      test('db.a.b.find().limit(5) 应支持含点的 collection name', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.a.b.find().limit(5)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'a.b');
        expect(result['limit'], 5);
      });

      test('不带 limit 的 find 应使用默认 limit=100', () {
        final result = MongoShellQueryParser.parseQuery('db.products.find()');
        expect(result, isNotNull);
        expect(result!['limit'], 100);
      });

      test('find().sort({createdAt: -1}).limit(10) 应解析 sort', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.orders.find({status: "pending"}).sort({createdAt: -1}).limit(10)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'orders');
        expect(result['sort'], {'createdAt': -1});
        expect(result['limit'], 10);
      });

      test('find().skip(20).limit(10) 应解析 skip', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().skip(20).limit(10)',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['skip'], 20);
        expect(result['limit'], 10);
      });

      test('find().sort({name: 1}).skip(10).limit(5) 应解析 sort+skip+limit', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.users.find().sort({name: 1}).skip(10).limit(5)',
        );
        expect(result, isNotNull);
        expect(result!['sort'], {'name': 1});
        expect(result['skip'], 10);
        expect(result['limit'], 5);
      });

      test('find().sort({a: 1}) 无 limit 时 sort 仍应解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().sort({a: 1})',
        );
        expect(result, isNotNull);
        expect(result!['sort'], {'a': 1});
        expect(result['limit'], 100);
      });

      test('find().skip(50) 无 limit 时 skip 仍应解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().skip(50)',
        );
        expect(result, isNotNull);
        expect(result!['skip'], 50);
        expect(result['limit'], 100);
      });

      test('sort 参数含字符串值 {status: "asc"} 应解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().sort({status: "asc"})',
        );
        expect(result, isNotNull);
        expect(result!['sort'], {'status': 'asc'});
      });

      test('链式顺序无关 .limit().sort() 应同样解析 sort', () {
        final result = MongoShellQueryParser.parseQuery(
          'db.products.find().limit(10).sort({price: -1})',
        );
        expect(result, isNotNull);
        expect(result!['sort'], {'price': -1});
        expect(result['limit'], 10);
      });
    });

    group('parseQuery - 纯 JSON 格式', () {
      test('{"collection":"products","filter":{}} 应解析', () {
        final result = MongoShellQueryParser.parseQuery(
          '{"collection":"products","filter":{}}',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
      });

      test(
        '{"collection":"orders","filter":{"status":"pending"},"limit":50} 应解析',
        () {
          final result = MongoShellQueryParser.parseQuery(
            '{"collection":"orders","filter":{"status":"pending"},"limit":50}',
          );
          expect(result, isNotNull);
          expect(result!['collection'], 'orders');
          expect(result['limit'], 50);
        },
      );
    });

    group('parseQuery - find(collection, filter) 格式', () {
      test('find("products", {id: 1}) 应解析', () {
        final result = MongoShellQueryParser.parseQuery(
          'find("products", {id: 1})',
        );
        expect(result, isNotNull);
        expect(result!['collection'], 'products');
        expect(result['filter'], {'id': 1});
        expect(result['limit'], 100);
      });
    });

    group('parseQuery - 无效输入', () {
      test('空字符串应返回 null', () {
        final result = MongoShellQueryParser.parseQuery('');
        expect(result, isNull);
      });

      test('纯文本应返回 null', () {
        final result = MongoShellQueryParser.parseQuery('hello world');
        expect(result, isNull);
      });

      test('未闭合的括号应返回 null', () {
        final result = MongoShellQueryParser.parseQuery('db.products.find({');
        expect(result, isNull);
      });
    });
  });
}
