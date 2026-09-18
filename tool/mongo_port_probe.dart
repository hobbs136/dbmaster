// ignore_for_file: avoid_print
// One-off TCP reachability probe: is each port open from this dev machine?
// Confirms whether the new RS ports (27018-27020) are reachable vs the
// known-good single-node Mongo (27017) and a control SQL port (3306).
//
// 开源剥离：目标主机不再硬编码——经命令行参数或 dart-define 提供：
//   dart run --dart-define=DBMASTER_MONGO_HOST=<host> tool/mongo_port_probe.dart
//   dart run tool/mongo_port_probe.dart <host>
import 'dart:io';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty
      ? args.first
      : const String.fromEnvironment('DBMASTER_MONGO_HOST');
  if (host.isEmpty) {
    print('usage: dart run --dart-define=DBMASTER_MONGO_HOST=<host> '
        'tool/mongo_port_probe.dart [host]');
    exit(64);
  }
  const ports = [3306, 27017, 27018, 27019, 27020];
  for (final p in ports) {
    try {
      final s = await Socket.connect(host, p,
          timeout: const Duration(seconds: 3));
      await s.close();
      print('$p : OPEN');
    } catch (e) {
      print('$p : CLOSED/filtered ($e)');
    }
  }
}
