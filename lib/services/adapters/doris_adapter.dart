// T29：Doris 已随 MySQL 协议族整体迁移到网关壳——实现体在
// mysql_gateway_adapter.dart（DorisAdapter 方言覆写逐行迁入），
// 本文件仅为兼容既有 import 的转发 shim。
export 'mysql_gateway_adapter.dart' show DorisAdapter;
