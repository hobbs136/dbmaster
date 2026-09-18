/// 构建渠道编译期开关。
///
/// 直销构建：`--dart-define=DIRECT_BUILD=true`（含离线授权 UI）。
/// MAS 构建不加该 flag——离线授权 UI 物理消失，
/// 避免 Apple 3.1.1（禁止应用内引导外部支付）审核风险。
const bool kDirectBuild = bool.fromEnvironment('DIRECT_BUILD');
