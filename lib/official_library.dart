import 'package:flutter/material.dart';
import 'domain.dart';
import 'repository.dart';
import 'language.dart';
import 'updates.dart';

class OfficialLibraryPage extends StatefulWidget {
  final MenuRepository repository;
  const OfficialLibraryPage({super.key,required this.repository});
  @override
  State<OfficialLibraryPage> createState()=>_OfficialLibraryPageState();
}
class _OfficialLibraryPageState extends State<OfficialLibraryPage> {
  bool busy=false;
  String status='';
  Future<void> perform(Future<void> Function() action) async {
    setState(()=>busy=true);
    try { await action(); }
    catch (_) { if(mounted) setState(()=>status='操作失败，请检查网络后重试；原数据保留。'); }
    finally { if(mounted)setState(()=>busy=false); }
  }
  Future<void> refreshCatalog() async {
    final next=MenuDb.decode(await fetchText(catalogUrl),Source.official);
    if(!mounted)return;
    if(next.revision <= widget.repository.official.revision) {
      setState(()=>status='官方菜单已是最新');return;
    }
    await widget.repository.replace(next);
    if(mounted)setState(()=>status='官方目录已更新；已移除的店铺不会自动添加，新店铺请自行选择。');
  }
  @override
  Widget build(BuildContext context) {
    final repo=widget.repository;
    return Scaffold(appBar:AppBar(title:const LText('管理官方店铺')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        const LText('添加需要的店铺到我的菜单；移除后不再参与推荐。店铺目录保留，可随时重新添加。个人菜品不受影响。'),
        const SizedBox(height:16),
        OutlinedButton.icon(onPressed:busy?null:()=>perform(refreshCatalog),icon:const Icon(Icons.sync),label:const LText('获取官方店铺更新')),
        LText(status),if(busy)const LinearProgressIndicator(),
        for(final place in repo.official.places) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          LText(place.name,style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:6),LText(place.area),
          TextButton(onPressed:busy?null:()=>perform(() async {
            await repo.setStoreInstalled(place.id,!repo.installedStoreIds.contains(place.id));
            if(mounted)setState(()=>status='已保存店铺选择');
          }),child:LText(repo.installedStoreIds.contains(place.id)?'从我的菜单移除':'添加到我的菜单')),
        ]))),
      ]));
  }
}
