import 'package:flutter/material.dart';
import 'update_page.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends ChangeNotifier {
  String code = 'zh';
  bool _closed = false;
  @override
  void dispose() { _closed = true; super.dispose(); }
  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString('eat_what.language');
      if (_closed) return;
      code = saved == 'en' ? 'en' : 'zh'; notifyListeners();
    } catch (_) { /* Keep Chinese if preferences cannot be read. */ }
  }
  Future<void> change(String value) async {
    final saved = await (await SharedPreferences.getInstance()).setString('eat_what.language',value);
    if (!saved) throw StateError('Language could not be saved');
    code = value; notifyListeners();
  }
}
class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({super.key, required LanguageController controller, required super.child}) : super(notifier: controller);
}
String tr(BuildContext context, String value) {
  if (context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier?.code != 'en') return value;
  if (_en.containsKey(value)) return _en[value]!;
  final count = RegExp(r'^(\d+) 个售卖项$').firstMatch(value);
  if (count != null) return '${count[1]} items';
  final shops = RegExp(r'^(\d+) 家店铺$').firstMatch(value);
  if (shops != null) return '${shops[1]} stores';
  if (value.startsWith('导入') || value.startsWith('导出')) {
    return value.replaceAll('导入','Import ').replaceAll('导出','Export ').replaceAll('官方库','official menu').replaceAll('个人库','personal menu');
  }
  if (value.startsWith('已选菜品＋米饭：')) return value.replaceFirst('已选菜品＋米饭：','Selected dishes + rice: ');
  if (value.contains(' · ') || value.startsWith('版本 ') || value.startsWith('校验通过：')) {
    for (final pair in const {
      '官方库':'Official', '个人库':'Personal', '官方 ·':'Official ·','个人 ·':'Personal ·',
      '版本 ':'Version ', ' 家店':' stores',' 个售卖项':' items','按菜计价':'Dish prices + rice','米饭 ¥':'Rice ¥','（免费续饭）':' (free refills)','已选菜品＋米饭：':'Selected dishes + rice: ','整套 ':'Set ', '（含米饭）':'(rice included)',
      '主餐 / 套餐':'Meal / set','配菜 / 小食':'Side / snack','单点菜':'Dish','饮品':'Drink','费用':'Fee',
      '抖音团购':'Douyin offer','已下架':'Unavailable','在售':'Available','暂不可选':'Unavailable','示例':'Example',
      '价格记录：':'Price recorded: ','库内标记：':'Recorded status: ','（非实时）':' (not live)',
      '来源：':'Source: ','拍摄日期：':'Photo date: ','截图未显示':'Not recorded','校验通过：':'Validated: ',
    }.entries) { value = value.replaceAll(pair.key,pair.value); }
  }
  return value;
}
class LText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextOverflow? overflow;
  const LText(this.data,{super.key,this.style,this.overflow});
  @override
  Widget build(BuildContext context) => Text(tr(context,data),style:style,overflow:overflow);
}
void openSettings(BuildContext context, {Future<void> Function(BuildContext)? onMealSettings}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => SettingsPage(onMealSettings:onMealSettings)));
}
class SettingsPage extends StatelessWidget {
  final Future<void> Function(BuildContext)? onMealSettings;
  const SettingsPage({super.key,this.onMealSettings});
  @override
  Widget build(BuildContext context) {
    final controller = context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
    return Scaffold(appBar: AppBar(title: const LText('设置')), body: ListView(padding: const EdgeInsets.all(24), children: [
      if(onMealSettings!=null) ListTile(leading:const Icon(Icons.schedule),title:const Text('餐次设置'),subtitle:const Text('跟随系统时间 / 手动模式'),onTap:()=>onMealSettings!(context)),
      const LText('语言'), const SizedBox(height: 16),
      for (final item in const [('zh','简体中文'),('en','English')]) ListTile(
        title: Text(item.$2), trailing: controller.code == item.$1 ? const Icon(Icons.check) : null,
        onTap: () async { try { await controller.change(item.$1); } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText('保存失败，请重试')));
        }}),
      const SizedBox(height: 24), const LText('店名、菜名及个人输入保留原文。'),
      const SizedBox(height: 24), const Divider(),
      ListTile(leading: const Icon(Icons.system_update), title: const LText('官方最新版本'),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UpdatePage()))),
      ListTile(
        leading: const Icon(Icons.code),
        title: const LText('GitHub 仓库与贡献'),
        subtitle: const LText('查看项目地址，欢迎反馈与贡献'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const RepositoryPage())),
      ),
    ]));
  }
}

class RepositoryPage extends StatelessWidget {
  static const repositoryUrl = 'https://github.com/lmynb68/Eaten-Yet-';
  const RepositoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('GitHub 仓库与贡献')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.favorite_outline, size: 48),
      const SizedBox(height: 20),
      LText('感谢每一位贡献者', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const LText('感谢你使用「吃什么」！每一次问题反馈、菜单补充、价格纠正和代码贡献，都让它变得更好。欢迎在 GitHub 提出建议、提交 Issue 或 Pull Request，一起让中北的每一顿更好选。'),
      const SizedBox(height: 24),
      const SelectableText(repositoryUrl),
      const SizedBox(height: 12),
      FilledButton.icon(icon: const Icon(Icons.copy), label: const LText('复制仓库地址'),
        onPressed: () async {
          try {
            await Clipboard.setData(const ClipboardData(text: repositoryUrl));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: LText('仓库地址已复制，可粘贴到浏览器打开')));
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: LText('复制失败，可长按地址手动复制')));
          }
        }),
    ]),
  );
}
const _en = <String,String>{
  '长按拖动调整顺序':'Hold and drag to reorder',
  '导航顺序保存失败，请重试':'Could not save navigation order. Please try again.',
  '筛选餐品':'Filter food', '菜单来源':'Menu source', '按条件查找':'Find by filters',
  '按你的想法挑':'Make it yours', '全部菜单':'All menus',
  '筛选':'Filters', '重置':'Reset',
  '我的喜爱':'Favorites', '米饭选菜':'Rice dishes',
  '满意，收藏这一顿':'Like and save this meal',
  '根据喜爱调整推荐':'Personalize using favorites',
  '仅在本机学习。关闭后等概率随机，收藏仍保留。':'Learn on this device only. Turn off for uniform random picks; favorites are kept.',
  '先选主菜，再搭配同店小食。':'Pick a main, then a snack from the same store.',
  '所选店铺没有米饭选菜。':'No rice dishes in the selected stores.',
  '请先回到米饭选菜，选好主菜。':'Choose rice dishes before adding a snack.',
  '只买小食（结束当前搭配）':'Snack only (end this meal)',
  '单独买小食：可先筛选店铺，不会与另一顿饭自动合并。':'Buying a snack separately: filter stores first. It will not be added to another meal.',
  '还没有喜爱记录。选好后点击“满意，收藏这一顿”。':'No favorites yet. Choose a meal, then like and save it.',
  '保存满意的一顿，随时回看。价格为收藏时记录。':'Save meals you like. Prices are snapshots from when you saved them.',
  "主食分类":"Staple type",
  "米饭":"Rice",
  "面条 / 米粉":"Noodles / rice noodles",
  "饺子 / 馄饨":"Dumplings / wontons",
  "其他主食":"Other staples",
  "不含主食":"No staple",
  "全部主食":"All staple types",
  "添加个人店铺":"Add personal store",
  "给这家店添加菜品":"Add a dish to this store",
  "请填写店铺名称":"Enter a store name",
  "同名同位置的店铺已存在":"A store with this name and location already exists",
  "管理官方店铺":"Manage official stores",
  "获取官方店铺更新":"Refresh official catalog",
  "从我的菜单移除":"Remove from my menu",
  "添加到我的菜单":"Add to my menu",
  "已保存店铺选择":"Store selection saved",
  "添加需要的店铺到我的菜单；移除后不再参与推荐。店铺目录保留，可随时重新添加。个人菜品不受影响。":"Add stores to your menu. Removed stores are excluded from recommendations and can be added again. Personal dishes are unaffected.",
  "操作失败，请检查网络后重试；原数据保留。":"Operation failed. Check your connection and retry. Existing data is kept.",
  "官方菜单已是最新":"Official catalog is up to date",
  "官方目录已更新；已移除的店铺不会自动添加，新店铺请自行选择。":"Catalog updated. Removed stores stay removed. Choose new stores to add them.",
  "官方最新版本":"Official latest version",
  "当前版本":"Installed version",
  "检查更新":"Check for updates",
  "测试版本":"Pre-release",
  "打开官方发布页面":"Open official releases",
  "复制地址":"Copy URL",
  "点击检查以获取官方最新版本；不会在启动时弹窗。":"Check for the latest official release. No startup pop-ups.",
  "暂无已发布版本":"No published releases yet",
  "发现新版本，可自行选择是否更新。":"A newer version is available. Updating is optional.",
  "当前版本已是最新或高于已发布版本":"Your version is up to date or newer than published releases",
  "检查失败，请检查网络或访问发布页面。":"Check failed. Check your connection or visit releases.",
  "无法打开浏览器，请复制地址后打开。":"Could not open a browser. Copy and open the URL manually.",
  "iPhone 请通过发布说明中的 App Store 或 TestFlight 链接更新；安卓安装包无法用于 iPhone。":"On iPhone, use an App Store or TestFlight link provided in the release notes. Android packages cannot run on iPhone.",
  "打开发布页面后下载适用的安装包，并按系统提示安装。更新由你决定，不会自动安装。安卓覆盖安装需相同签名。":"Download a compatible package from the release page and follow system prompts. Updates are optional. Android upgrades require matching signatures.",
  "基础数据来自10月15日；社区食堂更新于10月16日。预算不含打包、配送费用。":"Base data: October 15. Community canteen: October 16. Packaging and delivery are excluded.",

  'GitHub 仓库与贡献':'GitHub & contributions',
  '查看项目地址，欢迎反馈与贡献':'Project repository, feedback and contributions',
  '感谢每一位贡献者':'Thank you to every contributor',
  '感谢你使用「吃什么」！每一次问题反馈、菜单补充、价格纠正和代码贡献，都让它变得更好。欢迎在 GitHub 提出建议、提交 Issue 或 Pull Request，一起让中北的每一顿更好选。':'Thank you for using Eat What! Every bug report, menu addition, price correction and code contribution makes it better. Share your suggestions, open an issue or submit a pull request on GitHub. Together, we can make choosing a meal at NUC easier.',
  '复制仓库地址':'Copy repository URL',
  '仓库地址已复制，可粘贴到浏览器打开':'URL copied. Paste it into your browser to open the repository.',
  '复制失败，可长按地址手动复制':'Could not copy. Touch and hold the URL to copy it manually.',
  '筛选店铺和主餐':'Filter stores and meals',
  '已勾选主餐':'Selected meals',
  '可多选店铺，或展开店铺勾选主餐；只从勾选项中手选和随机。':'Select multiple stores, or expand a store to select meals. Both manual and random choices use this selection.',
  '全选':'Select all','清空选择':'Deselect all','应用筛选':'Apply filters','清除筛选':'Clear filters',
  '未勾选主餐，请调整筛选。':'No meals selected. Adjust your filters.',
  '所属店铺（用于匹配小食）':'Store (for matching snacks)',
  '请先编辑套餐并关联店铺，才能选择同店小食。':'Edit the set and link a store to choose snacks from the same store.',
  '菜位类别':'Dish slot category',
  '菜单已更新；请重新生成。已有锁定项会核对价格和来源。':'Menu updated. Please choose again.',
  '套餐数据或范围已更新，请重新选择。':'Set data changed. Please choose again.',
  '已保存到个人库；选择“个人库”或“合并库”后选用。':'Saved. Select the personal or combined library to use it.',
  '填写窗口真实可选的成品菜。整套固定价含米饭；加价菜请另建套餐。官方模板会复制到个人库。':'Enter actual cooked dishes available at the counter. The fixed price includes rice. Create separate sets for surcharges. Official templates are copied to your personal menu.',
  '套餐总价超出预算，原选择保留':'The set exceeds your budget. Current choices are kept.',
  '菜位参数无效':'Invalid dish slots.',
  '可选成品菜尚未补齐，请先维护套餐菜名':'Add available dishes before shuffling.',
  '锁定菜已不在这个菜位的菜单中，请先解锁':'A locked dish is no longer available. Unlock it first.',
  '三个菜位都已锁定，请先解锁':'All three slots are locked. Unlock a slot first.',
  '按套餐总价计费，锁定菜位保持不变。':'Fixed set price. Locked dishes remain unchanged.',
  '搜索达到上限，暂未找到新组合；原选择保留':'Search limit reached. No new combination found; keeping your choices.',
  '没有符合锁定条件的新组合；原选择保留':'No new combination fits your locks. Keeping your choices.',
  '设置':'Settings','语言':'Language','保存失败，请重试':'Could not save. Please retry.',
  '店名、菜名及个人输入保留原文。':'Store names, dish names and your entries remain in their original language.',
  '吃什么':'Eat What','中北大学':'NUC','搭一顿':'Pick a meal','餐品菜单':'Menu','店铺':'Stores','菜单库':'Libraries',
  '今天，吃什么？':'What shall we eat?','整份餐品、米饭套餐、小食分开选。':'Choose a meal or rice set, with an optional snack.',
  '本顿预算':'Budget','使用哪个菜单库':'Menu library','官方库 + 个人库':'Official + personal','仅官方库':'Official only','仅个人库':'Personal only',
  '整份餐品':'Meals','米饭套餐':'Rice sets','小食':'Snacks','随机一份':'Random meal','自己选一份':'Choose a meal',
  '随机小食':'Random snack','自己选小食':'Choose a snack','预算内手选一份':'Choose within budget','预算内没有餐品':'No meals within budget',
  '小食（可不选）':'Optional snack','不选小食':'Remove snack','选择小食':'Choose a snack','剩余预算内没有小食':'No snacks within the remaining budget','合计':'Total',
  '当前选择超出新预算，请重新选择。':'Your selection exceeds the new budget. Please change it.',
  '数据来自10月15日；预算不含打包、配送费用。':'Data as of October 15. Packaging and delivery are excluded.',
  '取消':'Cancel','保存':'Save','关闭':'Close','删除':'Delete','重试':'Retry','全部':'All','饮品':'Drinks','单点菜':'Dishes','费用':'Fees',
  '整份餐品 / 套餐':'Meals / sets','主餐 / 套餐':'Meal / set','配菜 / 小食':'Side / snack',
  '设好预算，给这一顿找个好搭配。':'Set your budget to choose a meal.','请输入有效预算':'Enter a valid budget.',
  '预算内没有新的可选餐品；原选择保留。':'No different meal fits this budget. Your selection is kept.',
  '已为你选好一份。':'A meal has been selected.','已手选小食。':'Snack selected.','已手选整份餐品。':'Meal selected.',
  '已切换分类，请选择餐品。':'Category changed. Choose a meal.',
  '范围已改变；重新生成时会检查锁定项。':'Library changed. Please choose again.',
  '单独选择一份小食，按当前预算计费；不与套餐自动合并。仅限加料的项目不参与。':'Choose a standalone snack within budget. Add-on-only items are excluded.',
  '按店铺、窗口或菜名查找，点击查看售价和购买说明。':'Search by store, counter or dish. Tap for prices and details.',
  '搜索菜名、店铺、窗口':'Search dishes, stores or counters','清除搜索':'Clear search',
  '暂无符合条件的菜品。可在“菜单库”录入个人菜单。':'No matches. Add your dishes in Libraries.',
  '全部店铺':'All stores','选择店铺，查看它的菜品、窗口和价格。':'Choose a store to view its dishes, counters and prices.',
  '返回全部店铺':'Back to all stores','这家店暂未录入菜品。':'No dishes added for this store.',
  '当前菜单库还没有店铺，可在菜单库中添加个人餐品。':'No stores yet. Add a personal dish in Libraries.',
  '你的菜单，你做主':'Your menu, your choice','官方库和个人库独立保存，可单独使用，也可合并推荐。':'Official and personal menus are stored separately. Use either or both.',
  '官方菜单库':'Official menu','我的个人库':'My menu','导出备份':'Export backup','导入更新':'Import update','导入个人库':'Import personal menu',
  '添加个人菜品':'Add personal dish','编辑个人菜品':'Edit personal dish','删除个人菜品？':'Delete personal dish?',
  '菜名':'Dish name','店铺名称':'Store name','位置 / 区域':'Location / area','售价（元）':'Price (CNY)','份量':'Portion',
  '窗口（可留空）':'Counter (optional)','购买规则 / 说明':'Purchase notes','售卖类型':'Category','价格渠道':'Price source',
  '直接购买':'Direct purchase','抖音团购':'Douyin offer','在售':'Available','酒精饮品（不自动推荐）':'Alcohol (excluded from recommendations)',
  '请填写菜名、店铺、份量和有效价格':'Enter a dish name, store, portion and valid price.',
  '添加照片':'Add photo','更换照片':'Change photo','移除照片':'Remove photo','照片过大，请选择小于300KB的图片':'Please choose a photo smaller than 300 KB.',
  '选择米饭套餐':'Choose rice set','维护个人米饭套餐':'Edit personal rice set','套餐名称':'Set name','餐厅 / 窗口':'Store / counter',
  '整套售价（元，含米饭）':'Set price (CNY, rice included)','保存到个人库':'Save to personal menu',
  '随机未锁定菜位':'Shuffle unlocked dishes','复制到个人库并补充菜名':'Copy to personal menu and add dishes','编辑这个个人套餐':'Edit this set',
  '新建个人米饭套餐':'Create a rice set','先选套餐，再选择三个成品菜；米饭包含在套餐中。':'Choose a set, then three dishes. Rice is included.',
  '请输入足够的预算后选菜；已选结果保留。':'Increase the budget to choose dishes. Current choices are kept.',
  '这个套餐的可选菜名待补充。可以复制到个人库，填入当天窗口菜单后使用。':'Dish options are not yet recorded. Copy this set to your library and add today’s options.',
  '可手选或随机，锁定后只换剩余菜位。':'Choose or shuffle dishes. Locked dishes stay unchanged.',
  '已手选，可锁定满意的菜位后随机其余项。':'Dish selected. Lock it to shuffle only the remaining dishes.',
  '可选成品菜，用顿号或换行分隔；可留空待补充':'Available dishes, separated by commas or newlines (optional)',
  'JSON 数据包':'JSON data','复制数据':'Copy data','校验数据':'Validate','确认替换此库':'Replace this library',
  '内置照片菜单；可导入团队维护的更高版本数据包。':'Includes recorded menus. Import newer official data to update.',
  '仅存于本机，支持录入、修改、下架及备份迁移。':'Stored on this device. Add, edit, disable, back up or transfer dishes.',
  '复制 JSON 保存为 UTF-8 文件，之后可在另一台设备导入。':'Copy the JSON into a UTF-8 file to import on another device.',
  '粘贴 JSON 数据包。先校验，再确认替换这个库；另一个库不受影响。建议先导出备份。':'Paste JSON, validate, then replace this library. The other library is unaffected. Back up first.',
  '原型仅支持手动数据包；“官方”是库类型标记，尚无服务器签名认证。':'Manual imports only. The official label identifies the library; server signatures are not yet supported.',
  '跨库同名店铺暂按不同来源处理，不自动合并身份。官方更新不会覆盖个人数据。当前不含云同步、实时价格或商家营业验证。':'Stores from different libraries are kept separate. Official updates preserve personal data. Cloud sync, live prices and opening status are not available.',
};
