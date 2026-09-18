# lucide_icons_flutter（dbmaster vendor 副本）

上游：[vqh2602/lucide-flutter-main](https://github.com/vqh2602/lucide-flutter-main)
v3.1.15（pub.dev `lucide_icons_flutter`）。

## 为什么 vendor（#31 T15 体积瘦身）

上游 pubspec 声明了 7 个字体文件（主字体 `lucide.ttf` 842KB + 6 个字重
变体 `LucideVariable-w100..w600` 共 2.69MB），Flutter 会把依赖包 pubspec
声明的**全部**字体打进产物——而本 app 只用 `LucideIcons.*` 常量（主
`Lucide` family，字重变体类零引用）。Font 体积无法在消费方裁剪，只能
vendor 后改包内 pubspec。

与上游的差异（升级时逐项核对）：

1. **pubspec 只声明 `Lucide` 主字体**，指向子集化后的 `assets/lucide.ttf`
   （仅含 app 实际用到的图标字形，约 25KB）。上游的字重变体声明整体删除
   ——`lib/lucide_icons.dart` 里的 `xxx100`-`xxx600` 常量仍保留（与上游
   一致），但引用它们会因字体缺失渲染为空框，app 侧零引用故可接受。
2. **`assets/lucide-full.ttf`**：上游原版完整字体（842KB），仅作为子集化
   的源文件保留在仓库，**不在 pubspec 字体声明内、不会打进产物**。
3. `lib/lucide_icons.dart` 与上游 3.1.15 逐字节一致，未做任何修改。

## 如何重新生成子集字体

在 dbmaster-flutter 仓库根目录：

```bash
dart run tool/subset_lucide_font.dart
```

脚本会扫描 `lib/`、`test/`、`integration_test/` 中的 `LucideIcons.*`
引用，从 `lucide-full.ttf` 抽取对应字形生成 `assets/lucide.ttf`，并同步
再生成守卫清单 `test/icons/lucide_subset_manifest.g.dart`
（`test/icons/lucide_subset_guard_test.dart` 用它拦截「新增图标未进子集」
的回归）。需要本机有 Python 3 + fonttools（脚本自动探测常见安装位置，
可用环境变量 `DBMASTER_PYTHON` 指定）。

## 升级上游流程

1. 覆盖 `lib/lucide_icons.dart` 与 `assets/lucide-full.ttf` 为新版本；
2. 重跑 `dart run tool/subset_lucide_font.dart`；
3. 核对本 pubspec 的字体段仍只声明 `Lucide` 主字体；
4. 跑 `flutter test test/icons/lucide_subset_guard_test.dart`。
