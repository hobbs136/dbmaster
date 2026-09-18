// T28 · SQL Server adapter 入口 —— 网关壳实现（FFI/sybdb 已整体下线）。
//
// 原条件导出（native FFI / web stub）随 T28 删除：网关壳只依赖 HTTP
// （T27 网关 API），全平台（含 web）同一路径，无需平台分叉。
export 'sqlserver_gateway_adapter.dart';
