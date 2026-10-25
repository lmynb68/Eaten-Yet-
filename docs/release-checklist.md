# 当前发布验收入口

目标：吃了么 v1.0.0+23。当前状态：准备中，不能按正式上线完成验收。

## 已处理
- 官网取消未发布版本的下载大小和架构承诺，明确历史截图与测试记录属于 v0.17.1。
- 专用正式签名配置；release 构建缺少本地签名信息时停止，不使用 debug 签名兜底。
- 安装迁移与隐私说明、canonical、Open Graph 和 sitemap。
- 部署前检查页面资源、锚点、JavaScript 语法及发布元数据；发布状态下进一步核对远程附件大小和 SHA-256。
- 部署产物排除 site/downloads 中的旧 APK；暂不删除仓库历史文件，以便追溯旧链接。

## 仍需验证
- Flutter analyze、全部测试及新签名 APK 构建（旧版 79 项通过不代替新验证）。
- 用 apksigner 核对两个新 APK 的正式证书一致，且与旧测试证书不同。
- 新安装、备份导入、升级与数据保留的真机验证。换签名不支持旧版覆盖升级。
- 发布附件后填写 site/release.json 的日期、最低系统、大小、架构、校验值，统一首页下载信息。
- 移动端菜单、复制链接、窄屏布局及弱网体验的浏览器实测。
- 已增加加载失败时原始数据导出入口及 2 项恢复测试；待 Flutter 环境执行。保存失败专项测试仍待补齐。

## 构建与回滚
工具链采用 Flutter SDK 与 pubspec.lock 对应依赖；Java 字节码目标 17，Android SDK 版本由本机 Flutter 工具链解析。正式验收需记录实际 Flutter、Dart、JDK 和 SDK 版本，不能只写目标版本。
先配置本地 android/key.properties，再运行 build-android-release.cmd。签名文件和密码不得上传或放入发布附件。
官网：python -m http.server 8000 --directory site；检查：python scripts/check_site.py。
网站回滚通过 git revert 对应网站提交再部署；不得用旧安装包覆盖新版本的同名发布附件。

## 本轮本地证据
旧 v0.17.1 APK 已通过 apksigner 检查，证书为 Android Debug，最低 SDK 24。此结果不代替新包检查。
新正式证书 SHA-256：`BA897C5FA7A0B3E55C828D0E6B17B1F9640DFDA37B07ACCCE1B29E53B99A17EF`。
构建脚本现强制检查新包签名、版本、包名及非 debuggable 标志。
本轮 Flutter 启动失败于 `resolved_executable_name`；尚未执行新测试或生成正式 APK。网站本地静态检查通过。
