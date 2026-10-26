# 吃了么 · Eaten Yet?

面向中北大学的 Android 选餐工具。当前正式版：**1.0.0（构建 25）**，支持 Android 7.0 及以上。

按预算随机或手选主餐，搭配同店小食；支持米饭选菜、收藏、独立个人菜单及应用内更新。菜单来自照片与用户核对，价格和供应以现场为准。

- [官网与下载](https://lmynb68.github.io/Eaten-Yet-/)
- [正式安装包](https://github.com/lmynb68/Eaten-Yet-/releases/tag/v1.0.0%2B25)
- [版本说明](docs/release-v1.0.0.md) · [发布验收](docs/release-checklist.md)
- [安装与迁移](site/install.html) · [隐私说明](site/privacy.html)

## 开发与构建

设置 `FLUTTER_ROOT`，准备 Android SDK 和 Java。验证过的 Flutter / Dart 版本为 3.47.7 / 3.13.5，CI 使用 JDK 21；Android Java 字节码目标为 17。

| 入口 | 用途 |
| --- | --- |
| `check.cmd` | 代码分析与测试 |
| `build-android.cmd` | 分析、测试和 Android 调试包 |
| `build-android-release.cmd` | 分析、测试和正式 ARM64 / 通用包 |
| `run.ps1 -Target doctor` | Flutter 环境诊断 |

正式构建需要本地 `android/key.properties` 和专用签名密钥，缺失时构建失败；密钥和密码不得提交。日志在 `logs/`，具体见 [安卓构建](docs/安卓版构建.md)。

官网预览：`python -m http.server 8000 --directory site`。网站检查：`python scripts/check_site.py`。浏览器专项检查：`node scripts/browser-qa.cjs`。

## 仓库结构

`lib/` 应用代码，`android/` 安卓工程，`assets/` 菜单与公开素材，`test/` 自动测试，`site/` 官网，`scripts/` 验证工具，`docs/` 当前说明与菜单维护记录。

仅维护 Android 版本。旧平台工程和阶段性版本记录已从当前目录移除，历史仍可在 Git 提交记录中查询。
