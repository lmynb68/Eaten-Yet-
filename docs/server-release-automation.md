# 正式 APK 自动同步到网站

状态（2026-10-31）：已启用。服务器专用账号 eaten-deploy、website-server 环境、部署 Secrets 和 SITE_ROOT 均已配置。目标仍为内部预览站，不开放公网网站。

验收：使用已发布正式版 v1.0.0+25 手动触发完整工作流成功，[运行记录](https://github.com/lmynb68/Eaten-Yet-/actions/runs/41161657789)。8 项回归测试通过，签名/包名/版本/架构校验通过；Nginx 首页 HTTP 200，通过内部 HTTP 下载的两份 APK 大小和 SHA256 均匹配。尚未通过发布一个新的正式版本验证 release 事件；该触发器已配置。

流程：GitHub 发布正式 Release → 验证正式证书、包名、版本、最低系统及 GitHub SHA256 → 上传到独立临时目录 → 服务器再次核对大小和 SHA256 → 保存 APK → 原子替换 release.json。失败保留旧版下载信息。旧 APK 不自动删除。

传输使用 rsync，以构建号划分上传目录，支持断点续传；校验一致的既有文件可复用。跨境传输可能较慢，工作流总时限为 90 分钟；中断后可重跑同一标签，下载清单只在校验成功后切换。临时上传目录和历史 APK 当前保留，需按实际磁盘用量定期清理。

## 发布约定

- 先在草稿上传 ARM64、通用版两个 APK，再点 Publish。预发布不部署。
- 标签必须是 `v版本+构建号`，如 `v1.0.0+27`，与两份 APK 一致。
- 文件名分别为 `EatenYet-...-android-arm64.apk`、`EatenYet-...-android-universal.apk`。
- GitHub API 必须提供两份附件的 SHA256 digest。签名必须是现有正式签名。
- 不要改已发布构建的文件；修复请增加构建号。同版本不同构建支持升级，旧构建不能覆盖新构建。
- 发布时附件尚未齐全会失败；补齐后可从 Actions 手动运行并填原标签。
- 用 GITHUB_TOKEN 创建 Release 可能不会触发后续工作流；这类发布应显式调用手动工作流或调整发布授权，不要假设必然触发。

## 服务器准备记录（已执行，无需重复）

以下仅用于现有内部预览目录；不开放端口、不改 Nginx、不配置域名。

```bash
sudo adduser --disabled-password --gecos '' eaten-deploy
sudo install -d -m 700 -o eaten-deploy -g eaten-deploy /home/eaten-deploy/.ssh
sudo install -d -m 755 -o eaten-deploy -g eaten-deploy /home/eaten-deploy/uploads
sudo chown eaten-deploy:eaten-deploy /var/www/eaten-yet-staging
sudo chown -R eaten-deploy:eaten-deploy /var/www/eaten-yet-staging/downloads
```

解释：`sudo` 使用管理员权限；`adduser` 创建专用账号，禁用密码登录；`install -d` 创建目录，`-m` 设置权限，`-o/-g` 设置所属用户/组；`chown` 允许专用账号写入网站目录。该账号不加入 sudo 组。

已生成专用于 GitHub Actions 的 SSH 密钥，将公钥加入该账号的 authorized_keys，目录700、文件600，并添加 `restrict` 公钥选项（禁止转发/PTY）。未使用 root 运维密钥。部署私钥及口令存入独立 GitHub Secrets，不提交仓库、不发聊天；任务结束销毁临时 SSH agent。用户本次授权直接执行配置。

## GitHub 设置

创建 Environment：`website-server`。Secrets：

| 名称 | 内容 |
|---|---|
| DEPLOY_HOST | 服务器地址 |
| DEPLOY_USER | eaten-deploy |
| DEPLOY_SSH_KEY | 新的部署专用私钥 |
| DEPLOY_SSH_PASSPHRASE | 部署私钥的口令，任务通过临时 SSH agent 解锁 |
| DEPLOY_KNOWN_HOSTS | 经服务器指纹核验的 SSH known_hosts 完整记录，不是单独的 SHA256 指纹 |

Environment Variable `SITE_ROOT` 填 `/var/www/eaten-yet-staging`。备案审核期间保留回环监听；此工作流不会公开网站。

将工作流和脚本合入 main，下一次正式标签也必须包含工作流。首次联调可使用已有正式 Release：只允许同构建、相同 APK 元数据从旧下载地址迁移到按构建号分目录的地址；同构建更换文件仍会拒绝。

## 验证和边界

服务器中检查 release.json 的 build、两个下载地址和 HTTP 响应，再验证两份下载内容。失败查看 Actions 日志。自动同步无需重载 Nginx。

只更新这台服务器上的 APK 和 release.json，不提交网站仓库、不部署页面设计、不更新 GitHub Pages，也不自动改变 APP 内的联网地址。没有 JavaScript 时首页现有静态链接仍指向旧发布；应以页面成功加载 release.json 后显示的链接为准。

如需回退，在确认旧 APK 仍存在后，由用户将 release.previous.json 复制为临时文件，再用 mv 替换 release.json。工作流拒绝自动降级；回退需单独人工处理。
