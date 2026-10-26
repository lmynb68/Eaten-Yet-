import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'apk_download.dart';
import 'language.dart';
import 'updates.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool busy = false, ready = false;
  AppRelease? release;
  UpdateAsset? asset;
  ApkDownload? download;
  int received = 0;
  String status = '点击检查新版本。更新由你决定，不会自动安装。';
  bool get android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> check() async {
    setState(() { busy = true; ready = false; release = null; asset = null; });
    try {
      final latest = AppRelease.latest(await fetchText(
        'https://api.github.com/repos/lmynb68/Eaten-Yet-/releases?per_page=100', maxBytes: 2000000));
      final abis = android ? await updateChannel.invokeListMethod<String>('abis') ?? <String>[] : <String>[];
      if (!mounted) return;
      setState(() {
        release = latest;
        if (latest == null) {
          status = '暂无已发布版本';
        } else if (compareVersions(latest.version, appVersion) <= 0) {
          status = '当前版本已是最新或高于已发布版本';
        } else if (!android) {
          status = '发现新版本；此设备不支持安卓安装包。';
        } else {
          asset = latest.installer(abis);
          status = asset == null ? '新版本尚未提供适用且带校验值的安装包，请稍后重试。' : '发现新版本，可直接在应用内下载更新。';
        }
      });
    } catch (_) {
      if (mounted) setState(() => status = '检查失败，请确认网络可连接更新服务器后重试。');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> startDownload() async {
    final selected = asset;
    if (selected == null) return;
    setState(() { busy = true; ready = false; received = 0; status = '正在下载安装包，请保持应用打开。'; });
    final task = ApkDownload();
    download = task;
    try {
      final path = await updateChannel.invokeMethod<String>('prepare');
      if (path == null) throw StateError('下载目录不可用');
      await task.save(selected, File(path), (bytes) {
        if (mounted) setState(() => received = bytes);
      });
      download = null;
      if (mounted) setState(() => status = '下载完成，正在校验安装包…');
      await updateChannel.invokeMethod<void>('verify', {'sha256': selected.sha256, 'size': selected.size});
      if (!mounted) return;
      ready = true;
      await install();
    } on UpdateCancelled {
      if (mounted) setState(() => status = '下载已取消，可以重新下载。');
    } on PlatformException catch (e) {
      if (mounted) setState(() => status = e.message ?? '安装包处理失败，请重新下载。');
    } catch (_) {
      if (mounted) setState(() => status = '下载失败或文件不完整。请检查网络和剩余空间后重试。');
    } finally {
      download = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> install() async {
    setState(() => busy = true);
    try {
      final outcome = await updateChannel.invokeMethod<String>('install');
      if (mounted) setState(() => status = outcome == 'permission'
          ? '请允许“吃了么”安装应用，返回后点击“继续安装”。'
          : '已打开系统安装界面，请确认安装。若取消，可点击“继续安装”。');
    } on PlatformException catch (e) {
      if (mounted) setState(() {
        if (e.code == 'VERIFY') ready = false;
        status = e.message ?? '无法启动安装，请重试。';
      });
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  void dispose() { download?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(appBar: AppBar(title: const LText('应用更新')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('${tr(context, '当前版本')} $appVersion ($appBuild)'),
        const SizedBox(height: 16), LText(status), const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : check, child: const LText('检查更新')),
        if (busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: download != null && asset != null ? received / asset!.size : null),
          if (download != null && asset != null) ...[
            Text('${(received / 1048576).toStringAsFixed(1)} / ${(asset!.size / 1048576).toStringAsFixed(1)} MiB'),
            TextButton(onPressed: () {
              download?.cancel();
              setState(() => status = '正在取消下载…');
            }, child: const LText('取消下载')),
          ],
        ],
        if (release != null) ...[
          const SizedBox(height: 24), Text(release!.version), const SizedBox(height: 12),
          SelectableText(release!.notes),
        ],
        if (asset != null) ...[
          const SizedBox(height: 24),
          Text('${asset!.name}\n${(asset!.size / 1048576).toStringAsFixed(1)} MiB'),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : ready ? install : startDownload,
              child: LText(ready ? '继续安装' : '下载并安装更新')),
        ],
        const SizedBox(height: 24),
        const LText('下载安装包后会校验完整性与签名，再由系统询问是否安装。正常覆盖升级保留本地数据，建议更新前导出重要个人菜单。'),
      ])),
  );
}
