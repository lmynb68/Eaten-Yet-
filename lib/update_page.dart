import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'language.dart';
import 'updates.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState()=>_UpdatePageState();
}
class _UpdatePageState extends State<UpdatePage> {
  bool busy=false;
  AppRelease? release;
  String status='点击检查以获取官方最新版本；不会在启动时弹窗。';
  Future<void> check() async {
    setState(()=>busy=true);
    try {
      final latest=AppRelease.latest(await fetchText('https://api.github.com/repos/lmynb68/Eaten-Yet-/releases?per_page=100',maxBytes:2000000));
      if(mounted)setState(() {
        release=latest;
        status=latest == null ? '暂无已发布版本' : compareVersions(latest.version,appVersion)>0 ? '发现新版本，可自行选择是否更新。' : '当前版本已是最新或高于已发布版本';
      });
    } catch (_) { if(mounted)setState(()=>status='检查失败，请检查网络或访问发布页面。'); }
    finally { if(mounted)setState(()=>busy=false); }
  }
  Future<void> open() async {
    try {
      final ok=await launchUrl(Uri.parse(release?.url ?? releasesUrl),mode:LaunchMode.externalApplication);
      if(!ok)throw StateError('browser');
    } catch (_) { if(mounted)setState(()=>status='无法打开浏览器，请复制地址后打开。'); }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const LText('官方最新版本')),
    body:ListView(padding:const EdgeInsets.all(24),children:[
      Text('${tr(context,'当前版本')} $appVersion ($appBuild)'),const SizedBox(height:16),
      LText(status),const SizedBox(height:16),
      FilledButton(onPressed:busy?null:check,child:const LText('检查更新')),
      if(busy)const LinearProgressIndicator(),
      if(release != null)...[
        const SizedBox(height:20),Text('${release!.version}${release!.prerelease ? ' · ${tr(context,"测试版本")}' : ''}'),
        const SizedBox(height:12),SelectableText(release!.notes),
      ],
      const SizedBox(height:24),
      if(defaultTargetPlatform == TargetPlatform.iOS)
        const LText('iPhone 请通过发布说明中的 App Store 或 TestFlight 链接更新；安卓安装包无法用于 iPhone。')
      else const LText('打开发布页面后下载适用的安装包，并按系统提示安装。更新由你决定，不会自动安装。安卓覆盖安装需相同签名。'),
      const SizedBox(height:12),
      OutlinedButton(onPressed:open,child:const LText('打开官方发布页面')),
      SelectableText(release?.url ?? releasesUrl),
      TextButton(onPressed:() async {
        await Clipboard.setData(ClipboardData(text:release?.url ?? releasesUrl));
      },child:const LText('复制地址')),
    ]));
}
