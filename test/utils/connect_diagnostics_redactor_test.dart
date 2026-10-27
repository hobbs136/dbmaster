// UI35-421~423（批4 T8 红测）：connect_diagnostics_redactor 契约测试。
//
// ⚠️ 编译红为预期红态：`lib/utils/connect_diagnostics_redactor.dart` 尚未
// 实现（红测先行）。本文件独立成档，不连累其它测试文件编译；实现批落地
// `String redactConnectDiagnostics(String payload)` 后本文件转绿。
//
// 断言表来源：计划文档 B-06 节第 6 条「边界样例表」13 条（B-06-R 格式规范，
// security-reviewer-max 定稿 2026-10-27），先于实现逐字转译、禁从实现反推；
// 断言逐字精确（expect 相等），禁 contains 弱断言。
import 'package:dbmaster/utils/connect_diagnostics_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI35-421: B-06-R 边界样例表（逐字精确断言，13 组 / 14 行）', () {
    final cases = <(String, String)>[
      // ① 连接串密码掩 *** + IPv4 末段掩 **
      (
        'postgres://alice:s3cret@10.240.18.7:5432/appdb',
        'postgres://alice:***@10.240.18.**:5432/appdb',
      ),
      // ② 密码含 @（R1 贪婪到最后一个 @）+ IPv4 末段
      (
        'mysql://bob:p@ss@192.168.1.50:3306',
        'mysql://bob:***@192.168.1.**:3306',
      ),
      // ③ 裸 IPv4 host:port 末段掩
      (
        'Connection refused: 10.240.18.7:5432',
        'Connection refused: 10.240.18.**:5432',
      ),
      // ④ Windows 用户目录（盘符形态）
      (
        r'C:\Users\hobbs\Documents\db.sqlite',
        r'C:\Users\***\Documents\db.sqlite',
      ),
      // ⑤ macOS /Users
      ('/Users/mary/db.sqlite', '/Users/***/db.sqlite'),
      // ⑥ Linux /home
      ('/home/dev/chinook.sqlite', '/home/***/chinook.sqlite'),
      // ⑦ IPv6 保留按书写顺序前两组，其余整体替换 …
      (
        '2001:db8:1234:5678:9abc:def0:1111:2222 port 5432',
        '2001:db8:… port 5432',
      ),
      // ⑧ localhost / 127.0.0.1 / ::1 三形态原样
      (
        'localhost:5432 / 127.0.0.1:3306 / ::1',
        'localhost:5432 / 127.0.0.1:3306 / ::1',
      ),
      // ⑨ UNC home-share $ 形态（\\server\name$ → \\server\***$）
      (
        r'\\fileserver\hobbs$\db.sqlite',
        r'\\fileserver\***$\db.sqlite',
      ),
      // ⑩ DB 用户名保留，仅掩 IP（排障必需账号名）
      (
        r"Access denied for user 'alice'@'10.240.18.7'",
        r"Access denied for user 'alice'@'10.240.18.**'",
      ),
      // ⑪ password= 值统一 ***（无长度信息）
      ('password=hunter2boojum', '***'),
      // ⑫ 无敏感形态原样不变
      (
        'SSL handshake failed: certificate verify failed',
        'SSL handshake failed: certificate verify failed',
      ),
      // ⑬ ~/db.sqlite 原样（裸 ~ 保留）；~bob/db.sqlite 掩用户名
      ('~/db.sqlite', '~/db.sqlite'),
      ('~bob/db.sqlite', '~***/db.sqlite'),
    ];

    for (final (input, expected) in cases) {
      test('样例「$input」→「$expected」', () {
        expect(redactConnectDiagnostics(input), expected);
      });
    }
  });

  group('UI35-422: 掩码 token 边界（B-06-R 第 2 条：全集仅三种）', () {
    test('IPv4 末段掩码 token = ** 恰两字符，非 ***', () {
      final out =
          redactConnectDiagnostics('Connection refused: 10.240.18.7:5432');
      expect(out.endsWith('10.240.18.**:5432'), isTrue);
      expect(out.contains('10.240.18.***'), isFalse);
    });

    test('凭据掩码 token = *** 恰三字符，非 **', () {
      expect(redactConnectDiagnostics('password=hunter2boojum'), '***');
    });

    test('IPv6 掩码部分 = 单个 U+2026 字符，非 ASCII 三点', () {
      final out = redactConnectDiagnostics(
        '2001:db8:1234:5678:9abc:def0:1111:2222 port 5432',
      );
      expect(out, '2001:db8:… port 5432');
      expect('\u2026'.allMatches(out).length, 1);
      expect(out.contains('...'), isFalse);
    });
  });

  group('UI35-424（批4 修复轮，security P3-①/偏差 D-1）: R4 seg 含空格用户名完整掩', () {
    // B-06-R 冻结原文「seg 至下一路径分隔符（`\` 或 `/`）为止」：seg
    // 字符集不含空格排除——含空格用户名须完整掩到下一分隔符，不得在
    // 空格/冒号处提前截断。既有 13 样例表（UI35-421）为冻结断言不动，
    // 本组为修复轮新增补充样例（三臂各一）。
    final cases = <(String, String)>[
      // Users 臂（盘符形态）：含空格用户名整段掩
      (r'C:\Users\john doe\db.sqlite', r'C:\Users\***\db.sqlite'),
      // home 臂：同款「至下一分隔符」语义
      ('/home/jane doe/chinook.sqlite', '/home/***/chinook.sqlite'),
      // ~ 臂：~ 后名字段同样掩至下一分隔符（裸 ~ 保留不破）
      ('~john doe/db', '~***/db'),
    ];

    for (final (input, expected) in cases) {
      test('含空格用户名「$input」→「$expected」', () {
        expect(redactConnectDiagnostics(input), expected);
      });
    }
  });

  group('UI35-423: 纯函数性与 R1 先行', () {
    test('纯函数：同输入两次调用同输出', () {
      const payload = 'postgres://alice:s3cret@10.240.18.7:5432/appdb';
      expect(
        redactConnectDiagnostics(payload),
        redactConnectDiagnostics(payload),
      );
    });

    test('R1 先行：password= 形态经 redactSecrets 掩 ***（样例⑪同源）', () {
      // R2~R4 均不处理 password= 形态，输出 *** 只能来自 R1 第一步。
      expect(redactConnectDiagnostics('password=hunter2boojum'), '***');
    });
  });
}
