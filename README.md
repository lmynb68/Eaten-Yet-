# 吃了么 · Eaten Yet?

今天吃什么，交给它选。

吃了么是一款面向中北大学的安卓选餐应用。设好预算，从校园菜单里挑一顿，也可以把常吃的店和菜加入自己的菜单。

**[访问官网](https://lmynb68.github.io/Eaten-Yet-/) · [下载安装包](https://github.com/lmynb68/Eaten-Yet-/releases/latest) · [安装帮助](https://lmynb68.github.io/Eaten-Yet-/install.html)**

## 能做什么

- **按预算选餐**：随机推荐或自己挑选主餐，支持筛选和锁定后重新搭配。
- **搭配同店小食**：主餐选好后，再挑同店小吃或饮品。
- **浏览店铺菜单**：查看店铺、窗口、菜品和价格，支持米饭选菜。
- **收藏喜欢的一顿**：留下想再吃的选择，可开启根据喜好调整推荐。
- **管理自己的菜单**：个人菜单与官方菜单独立保存，支持录入、导入和导出。
- **应用内更新**：在设置中检查更新，下载后按手机提示安装。

菜单来自照片整理及人工核对，仅供选餐参考，价格和供应以店内为准。官网是介绍与下载入口，不提供在线选餐或下单服务。

## 下载与安装

当前正式版为 **1.0**，适用于 **Android 7.0 及以上**，暂不支持 iPhone。

| 安装包 | 适用设备 |
| --- | --- |
| ARM64 版 | 支持 64 位 ARM 应用的安卓手机，安装包较小 |
| 通用版 | 包含 ARM64、ARMv7 和 x86_64；不确定设备架构时可选，功能相同 |

从官网或本仓库 Releases 下载，打开安装包后按系统提示安装。后续同签名的高版本可直接覆盖更新，无需卸载。遇到签名冲突或版本过低时，请先保留原应用，参阅[安装帮助](https://lmynb68.github.io/Eaten-Yet-/install.html)。

## 数据与隐私

菜单、照片、收藏和偏好保存在手机本地，不提供账号或云端同步。检查更新与获取在线菜单时会联网。

**菜单导出不包含收藏和全部设置。** 卸载或清除应用数据前，请保存重要菜单并另外记录需要保留的内容。详见[隐私说明](https://lmynb68.github.io/Eaten-Yet-/privacy.html)。

## 问题反馈

请在 [Issues](https://github.com/lmynb68/Eaten-Yet-/issues) 中描述问题，附上应用版本、手机型号、系统版本、操作步骤和错误提示。截图请遮住私人信息，不要上传个人菜单备份、密码或密钥。

## 开发与维护

应用使用 Flutter，官网位于 `site/`，为纯静态页面。

- 工具链：Flutter 3.47.7、Dart 3.13.5；CI 使用 JDK 21，Android Java 字节码目标为 17。
- 本地准备：安装 Android SDK，设置 `FLUTTER_ROOT` 或将 Flutter 加入 PATH。
- 分析与测试：`flutter pub get`、`flutter analyze --no-pub lib test`、`flutter test --no-pub`。
- 正式构建：运行 `build-android-release.cmd`；需要仓库外的专用签名密钥及本地 `android/key.properties`，缺少签名配置会拒绝构建。详见[安卓构建说明](docs/安卓版构建.md)。
- 官网预览：`python -m http.server 8000 --directory site`。
- 网站检查：`python scripts/check_site.py`（需要 Python 和 Node.js）。
- 浏览器检查：`node scripts/browser-qa.cjs`（需要 Chrome，可通过 `CHROME_PATH` 指定位置）。

每次 PR 和 main 推送会运行应用 CI；网站变更另外运行 GitHub Pages 部署检查。自动测试、模拟浏览器检查与正式 APK 实机验收是不同范围，详见[测试说明](docs/testing.md)和[发布验收记录](docs/release-checklist.md)。

| 目录 | 内容 |
| --- | --- |
| `lib/`、`android/` | 应用代码与安卓工程 |
| `assets/` | 菜单数据和公开素材 |
| `test/` | 自动回归测试 |
| `site/` | 官网、安装帮助与隐私说明 |
| `scripts/`、`docs/` | 检查工具、构建与维护文档 |

## 许可证

项目采用 [MIT License](LICENSE)。
