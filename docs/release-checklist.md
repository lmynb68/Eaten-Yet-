# 当前发布验收入口

吃了么 v1.0.0+23 已于 2026-10-25 发布。剩余专项检查不等同于发布失败。

## 已完成
- [正式附件](https://github.com/lmynb68/Eaten-Yet-/releases/tag/v1.0.0)：ARM64、通用 APK 及 SHA256SUMS.txt；大小与 SHA-256 已核对。
- 对应应用源码 `6b77ebdbcc06dfede426a9a3e72ce64371d25288`：本机静态分析、84 项测试及正式签名构建通过。
- 两个 APK 的包名、1.0.0+23、最低 SDK 24、非 debuggable、正式证书及内置菜单检查通过。
- 用户确认真机新安装打开正常、旧版导出的个人菜单导入成功且内容正确。
- 官网发布元数据已同步，Pages 部署成功；资源、锚点、JavaScript 语法与附件检查已加入部署流程。
- 安装迁移、隐私说明及公开素材检查已完成；密钥和私人资料不进入仓库。

## 后续专项检查
- 手机浏览器菜单、复制链接、窄屏及弱网检查：见后续验证记录，不能用静态检查替代。
- 新增保存失败测试覆盖返回 false 和抛异常、状态保留与后续队列恢复；2026-10-26 全量 88 项测试通过；不改写发布时的 84 项记录。
- 完整收藏和设置迁移未覆盖。菜单导出不是完整备份；换签名不能覆盖旧测试版。

## 构建与回滚
本地配置 android/key.properties 后运行 build-android-release.cmd；签名文件及密码不得上传。
官网本地预览：python -m http.server 8000 --directory site。
静态检查：python scripts/check_site.py；远端附件检查追加 --online，使用临时 GITHUB_TOKEN 避免匿名限流。
网站通过 git revert 回滚；不得覆盖已发布的同名 APK。详细版本和校验值见 release-v1.0.0.md 与 site/release.json。

## 发布后专项验证（2026-10-26）
- 新增 test/save_failure_test.dart：4 个保存失败用例已通过，全量 88 项测试通过；不计入正式包原有的 84 项。
- scripts/browser-qa.cjs：检查 320/360/390/768 宽度、菜单、复制成功/拒绝处理、400ms 延迟及 50KB/s 模拟网络。需 Node.js（支持 WebSocket）与 Chrome，可通过 CHROME_PATH 指定浏览器。
- 运行 node scripts/browser-qa.cjs，结果写入 browser-qa-result.json。它是桌面浏览器模拟，不代替手机实测；剪贴板使用注入模拟，不证明系统权限行为。
- 用户于本机运行验证脚本后，已核对日志：88 项应用测试全部通过；10 项桌面 Chrome 模拟检查全部通过。模拟弱网下页面就绪约 1.31 秒，仅为本地站点单次结果，不代表线上或手机性能。真实手机浏览器、系统剪贴板权限、完整收藏及设置迁移仍未覆盖。
