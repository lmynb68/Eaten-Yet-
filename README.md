# Eaten Yet? · 吃什么

面向中北大学的 Flutter 选餐应用，优先支持 Android / iPhone，保留 Windows 桌面端。

## 功能

- 按预算随机或手选整份餐品。
- 米饭套餐支持三个成品菜位，手选、随机和锁定后局部重选。
- 主餐可附加同店小食，也可不选；总价受预算约束。
- 店铺与主餐多选筛选，支持整店勾选、展开逐项选择。
- 餐品菜单、店铺及其菜品关联浏览。
- 官方库和个人库独立保存，支持 JSON 导入导出。
- 个人菜品添加照片；简体中文 / English 界面切换。

## 当前状态

版本 **0.9.0+9**。2026-10-15 本机验证：代码分析无问题，36 项测试通过，Android debug APK 构建成功。真机交互仍需验证。iPhone 尚未构建签名安装包。

内置食味坊、金面郎中北大学店的菜单，价格来自用户提供的记录，不是实时价格。部分米饭套餐菜名需自行补充。预算不含配送、打包费用。

## 开发与运行

安装 Flutter SDK、Android SDK 和所需开发工具。本项目验证环境为 Flutter 3.47.7 / Dart 3.13.5；依赖版本见 pubspec.lock。

```sh
git clone https://github.com/lmynb68/Eaten-Yet-.git
cd Eaten-Yet-
flutter pub get
flutter analyze lib test
flutter test
flutter run
```

Android 构建：

```sh
flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`。这是测试包，正式分发前需配置自己的签名。

Windows 可运行 `flutter run -d windows`，需要 Visual Studio C++ 桌面构建工具。也可使用项目中的 `.cmd` 脚本；Flutter 应加入 PATH 或配置 FLUTTER_ROOT。

iPhone 需在 Mac 安装 Flutter 和 Xcode，运行 `bash prepare-ios.sh` 生成 iOS 工程，然后用 Xcode 配置开发团队、签名及设备。

## 结构

- `lib/`：界面、数据模型、随机逻辑、筛选及语言设置。
- `assets/`：菜单、图标和店铺图片。
- `test/`：业务逻辑与界面测试。
- `android/`、`windows/`：平台工程。
- `docs/`：产品设计及各版本记录，以 v0.9 为准。

## 许可证

代码采用 [MIT License](LICENSE)。店铺照片、商标及其他第三方素材的权利归原权利人所有，不因本仓库的 MIT 许可证而授予其权利。菜单价格仅作历史参考。
