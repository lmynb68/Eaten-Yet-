# 吃了么项目官网

本地预览：双击 index.html。无需安装依赖，不需要后端或数据库。

页面包含：首页、核心功能、运行展示、技术实现、项目成果、下载与联系。
联系人入口：GitHub Issues。没有收集访客信息、登录或表单服务。

## 内容状态
- 名称：吃了么 / Eaten Yet?，明确说明应用内当前名称为“吃什么”。
- 数据：7 家餐厅、1190 个售卖项（含不同规格及32项米饭配菜）。
- 应用版本：0.16.0+20；静态检查和74项自动测试通过。
- 下载：本目录 downloads 内包含已验证的 ARM64 和通用 APK，使用相对链接。
- Windows 与 Android 实际运行截图暂缺，按用户要求明确预留，不使用模拟图冒充。
- 不提供当前版本 Windows 或 iOS 安装包，不暗示已通过真机验证。

## 替换运行截图
把真实截图放进 assets，例如 windows-running.png 和 android-running.png。
在 index.html 的 showcase 区域，把对应 div.empty 替换成 img，保留 figure、顶部平台标题及 figcaption。
示例：<img src="assets/android-running.png" alt="Android 实机选餐界面" loading="lazy">
应同时更新“实机截图待补充”的说明，并注明截图对应的应用版本。

## GitHub Pages 部署
部署 ZIP 内已按仓库结构组织：site/ 放页面和资源，.github/workflows/project-pages.yml 放工作流。
1. 将 ZIP 解压至目标仓库根目录，保留 site 与 .github 目录结构。若仓库已有 Pages 工作流，应先合并配置，避免重复部署。
2. 提交并推送到实际默认分支；示例工作流使用 main，若不同请修改 branches。
3. 在仓库 Settings → Pages 中将 Source 设为 GitHub Actions。
4. 在 Actions 中运行 Deploy project website，完成后以部署返回的页面地址为准。

部署方式依据 GitHub 官方文档：
https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages

未执行远程推送，未开启 Pages，尚未上线。

## 验证范围
JavaScript 语法检查通过；静态资源/锚点/下载包校验见 verification.txt。
已使用 Chrome 完成桌面与移动视口检查：1440、768、390、320 像素宽度无横向溢出，手机菜单展开及点击后收起正常。
已查看桌面及手机整页预览。网页预览图为官网截图，不是应用实机截图；真实手机设备、外网部署与在线下载尚未验证。

