# 测试与验收范围

## 自动回归

`.github/workflows/ci.yml` 在每次 PR 和 main 推送先归档当前 Git 提交，在 Linux 解压后执行严格锁文件检查、静态分析及 `flutter test --no-pub`，随后检查安卓 debug 编译和正式签名缺失时拒绝构建。Flutter 固定为 3.47.8，依赖来源与锁文件保持一致。debug 编译不等于正式 APK 验收。

| 范围 | 当前用例 |
| --- | --- |
| 预算、筛选、锁定重抽 | domain_test.dart、meal_flow_test.dart、filter_sheet_test.dart、rice_test.dart |
| 收藏、偏好、并发写入 | favorites_test.dart、release_reliability_test.dart |
| 导入、序列化保存、重新加载 | persistence_flow_test.dart（模拟存储，跨模块） |
| 保存失败（返回 false / 抛异常）、队列恢复 | save_failure_test.dart |
| 损坏数据保留与恢复导出 | recovery_test.dart、release_reliability_test.dart |
| 损坏收藏不阻断选餐、恢复提示可见 | app_test.dart |
| 收藏原值类型错误、连续损坏、备份/重置失败重试及字段校验 | favorite_state_recovery_test.dart、favorite_limits_recovery_test.dart |
| 餐次设置类型错误与界面修复 | meal_period_recovery_test.dart |
| 历史记录恢复、评价与份数；2,000 条记录按需显示 | history_quantity_test.dart、history_quantity_widget_test.dart、history_lazy_list_test.dart |
| 版本筛选、安装包下载失败与校验 | apk_update_test.dart、release_reliability_test.dart |

新增用例的执行结果以对应提交的 CI 为准。模拟存储重新加载不等于手机杀进程重启，组件测试也不等于完整 E2E。

辅助 CI 同时执行发布脚本、源码归档、菜单重建回归、网站静态检查和 PowerShell 语法检查。菜单重建在隔离目录生成候选结果，验证版本、完整记录和麦港 101 项菜品；`python docs/rebuild_catalog.py --check` 不写入正式菜单。

## 尚需设备执行的完整流程

以下为待验收清单，不是通过记录，也尚未建立完整自动化 E2E 套件。

- 首次启动 → 设置预算 → 随机选餐，价格不超过预算。
- 收藏 → 强制停止应用 → 重启，收藏与偏好仍存在。
- 导入旧菜单 → 关闭并重启，菜品、价格及规格一致。
- 关闭网络 → 重启 → 使用本地菜单选餐。
- 更新下载中断或失败 → 返回选餐，现有数据与功能仍可用。
- 正式签名 APK：系统安装确认、安装权限拒绝及重新允许、相册选图、外部浏览器跳转。
- 同签名高版本覆盖安装后核对个人菜单与收藏；既往用户反馈不能代替以上全部场景。

每次验收记录提交、包版本、设备/系统、步骤、实际结果；失败附脱敏错误信息。修复问题后将可自动复现的条件加入回归测试。
