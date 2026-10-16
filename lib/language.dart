import 'package:flutter/material.dart';
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
  if (value.contains(' · ') || value.startsWith('版本 ') || value.startsWith('校验通过：')) {
    for (final pair in const {
      '官方库':'Official', '个人库':'Personal', '官方 ·':'Official ·','个人 ·':'Personal ·',
      '版本 ':'Version ', ' 家店':' stores',' 个售卖项':' items','整套 ':'Set ', '（含米饭）':'(rice included)',
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
void openSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => const SettingsPage()));
}
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
    return Scaffold(appBar: AppBar(title: const LText('设置')), body: ListView(padding: const EdgeInsets.all(24), children: [
      const LText('语言'), const SizedBox(height: 16),
      for (final item in const [('zh','简体中文'),('en','English')]) ListTile(
        title: Text(item.$2), trailing: controller.code == item.$1 ? const Icon(Icons.check) : null,
        onTap: () async { try { await controller.change(item.$1); } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText('保存失败，请重试')));
        }}),
      const SizedBox(height: 24), const LText('店名、菜名及个人输入保留原文。'),
    ]));
  }
}
const _en = <String,String>{
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
