# 吃了么 · Eaten Yet?

第一代正式版准备中：**v1.0.0**。面向中北大学的Android选餐工具。

按预算随机或手选主餐，搭配同店小食；支持米饭选菜锁定重抽、收藏、个人菜单与备份。
当前收录9家店，1666个售卖项（1634个规格+32项米饭配菜）。

- [官网](https://lmynb68.github.io/Eaten-Yet-/)
- [已发布安装包](https://github.com/lmynb68/Eaten-Yet-/releases)
- [1.0版本说明](docs/release-v1.0.0.md)

## 构建
运行 `build-android-release.cmd`，依次完成依赖、代码检查、自动测试、ARM64及通用APK构建。
应用名称：吃了么；版本：1.0.0+23；包名保持 `local.eatwhat.campus`。
正式1.0安装包正在准备；在发布页出现对应资产前，请勿将旧版改名视为新版。

菜单由照片与用户核对整理，价格和供应以现场为准。

当前验收状态见 [发布验收](docs/release-checklist.md)。
网站预览：在仓库根目录运行 `python -m http.server 8000 --directory site`。
网站检查：`python scripts/check_site.py`。
安装迁移：[说明](site/install.html)；数据处理：[说明](site/privacy.html)。
正式构建必须配置本地 `android/key.properties`，不允许退回 debug 签名。

## 工具链与验证
本机 SDK 元数据：Flutter 3.47.7 / Dart 3.13.5。Android 使用 Java 17 字节码目标；CI 使用 Temurin JDK 21。本机 JDK 与 CI 运行结果需分别记录，不视为已验证一致。
设置 `FLUTTER_ROOT` 为 Flutter SDK 根目录，确保 Android SDK、Java 可用；执行 `flutter pub get`、`flutter analyze --no-pub lib test`、`flutter test --no-pub`。
本地构建入口为 `build-android-release.cmd`，日志在 `logs/android-release.txt`。遇到 `resolved_executable_name` 启动错误时，当前进程无法运行 SDK，需在本机终端运行同一入口；不得把旧日志当作新测试结果。
CI 对主分支和 PR 执行分析、测试及 Android debug 编译，并验证缺少正式签名时 release 构建必须失败。正式签名构建仅在受控本机运行。
