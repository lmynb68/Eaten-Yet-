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
/// Translate interface copy only. Parameters are inserted once and stay verbatim.
String translateText(String value, String code, {Map<String, Object> params = const {}}) {
  var result = code == 'en' ? (_en[value] ?? value) : value;
  if (code == 'en' && result == value) {
    final dish = RegExp(r'^第(\d+)道菜$').firstMatch(value);
    final count = RegExp(r'^(\d+) 个菜品$').firstMatch(value);
    final shops = RegExp(r'^(\d+) 家店铺$').firstMatch(value);
    if (dish != null) result = 'Dish ${dish[1]}';
    if (count != null) result = '${count[1]} items';
    if (shops != null) result = '${shops[1]} stores';
  }
  return result.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) => params[match[1]]?.toString() ?? match[0]!);
}
String tr(BuildContext context, String value, {Map<String, Object> params = const {}}) =>
  translateText(value, context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier?.code ?? 'zh', params: params);
class LText extends StatelessWidget {
  final String data;
  final Map<String, Object> params;
  final TextStyle? style;
  final TextOverflow? overflow;
  const LText(this.data,{super.key,this.params=const {},this.style,this.overflow});
  @override
  Widget build(BuildContext context) => Text(tr(context,data,params:params),style:style,overflow:overflow);
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
      if(onMealSettings!=null) ListTile(leading:const Icon(Icons.schedule),title:const LText('用餐时间'),subtitle:const LText('跟随系统时间 / 手动模式'),onTap:()=>onMealSettings!(context)),
      const LText('语言'), const SizedBox(height: 16),
      for (final item in const [('zh','简体中文'),('en','English')]) ListTile(
        title: Text(item.$2), trailing: controller.code == item.$1 ? const Icon(Icons.check) : null,
        onTap: () async { try { await controller.change(item.$1); } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText('保存失败，请重试')));
        }}),
      const SizedBox(height: 24), const LText('店名、菜名及个人输入保留原文。'),
      const SizedBox(height: 24), const Divider(),
      ListTile(leading: const Icon(Icons.system_update), title: const LText('检查更新'),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UpdatePage()))),
      ListTile(
        leading: const Icon(Icons.code),
        title: const LText('项目与反馈'),
        subtitle: const LText('查看项目，留下问题或建议'),
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
    appBar: AppBar(title: const LText('项目与反馈')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.favorite_outline, size: 48),
      const SizedBox(height: 20),
      LText('感谢每一位贡献者', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const LText('感谢你使用「吃了么」！如果发现菜名或价格有误，欢迎告诉我们，也欢迎留下问题或建议。'),
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
String friendlySaveError(Object error) {
  const messages = {
    '菜单保存后超过容量上限，请减少内容后重试',
    '最多保存500条收藏，请先删除部分记录',
    '收藏超过10MB，请先删除部分含照片的记录',
    '请先选好这一顿',
    '历史记录已满，请先导出并删除部分记录。',
    '历史记录超过10MB，请先导出并删除部分记录。',
  };
  if (error is FormatException && messages.contains(error.message)) return error.message;
  return '保存失败，请重试';
}
const _en = <String,String>{
  '导入': 'Import',
  '中北大学周边': 'Near North University of China',
  '1 份': '1 portion',
  '个人录入': 'Added by you',
  '导出排障数据': 'Export diagnostic data',
  '这份旧菜单超过容量上限。以下内容仅供排障，不能直接导入恢复，请私下保存。': 'This older menu exceeds the size limit. This data is for troubleshooting only and cannot be imported directly. Keep it private.',
  '排障数据已复制，请私下保存。': 'Diagnostic data copied. Keep it private.',

  "份数": "Quantity",
  "减少一份": "Decrease quantity",
  "增加一份": "Increase quantity",
  "{count} 份": "{count} portions",
  "{count} 星": "{count} stars",
  "用餐历史": "Meal history",
  "记录这一顿": "Record this meal",
  "已记录这一顿": "Meal recorded",
  "评价这一顿": "Rate this meal",
  "星级和评价可以稍后再填": "You can add a rating and review later.",
  "写下你的评价": "Write a review",
  "编辑评价": "Edit review",
  "只保存在本机。记录这一顿后，可以评分、写评价。": "Saved on this device only. Record a meal to rate and review it.",
  "历史记录保存失败，原记录已保留。请重试。": "Could not save meal history. Existing records are unchanged. Try again.",
  "导入用餐历史": "Import meal history",
  "导出用餐历史": "Export meal history",
  "粘贴历史备份": "Paste your history backup",
  "历史备份已复制，请私下保存。": "History backup copied. Keep it private.",
  "历史记录暂时读不出来，原数据已保留，请先导出备份。": "Could not read meal history. Your data is still here. Export a backup first.",
  "还没有用餐历史。选好后点击“记录这一顿”。": "No meals recorded yet. Choose a meal, then tap Record this meal.",
  "删除这条用餐记录？": "Delete this meal record?",
  "米饭份数": "Rice portions",
  "套餐份数": "Set meal portions",
  "移除这道菜": "Remove this dish",
  "添加一道菜": "Add a dish",
  "菜品都已锁定，请先解锁一道菜": "All dishes are locked. Unlock one first.",
  "搭配已切换，请重新选菜。": "Meal plan changed. Choose your dishes again.",
  "历史记录已满，请先导出并删除部分记录。": "Meal history is full. Export a backup and remove some records first.",
  "历史记录超过10MB，请先导出并删除部分记录。": "Meal history exceeds 10 MB. Export a backup and remove some records first.",
  "备份后重置历史": "Reset history after backup",
  "重置用餐历史？": "Reset meal history?",
  "请先保存导出的内容。重置后可以导入之前正常的历史备份。": "Save the exported data first. After resetting, you can import an earlier working history backup.",
  "这份菜单不是新版，请选择更新的菜单文件。": "Choose a newer official menu file.",
  "可以用官方菜单选餐，也可以加上自己常吃的菜。": "Pick from the official menu or add dishes you like.",
  "感谢你使用「吃了么」！如果发现菜名或价格有误，欢迎告诉我们，也欢迎留下问题或建议。": "Thank you for using Eaten Yet! Let us know if a dish or price is incorrect, or send us a question or suggestion.",
  "清空后，这些收藏会从列表移除。请先导出一份备份。": "These meals will be removed from your favorites. Export a backup first.",
  "官方菜单和我的菜单分开保存，互不覆盖。": "The official menu and your menu are saved separately.",
  "下载后会先检查安装包是否完整，再由系统确认安装。": "After downloading, the app checks the file and your phone asks you to confirm installation.",
  "收藏读取失败，数据还在。你仍然可以选餐，收藏功能暂时停用。": "Your favorites could not be read. Your data is still here. You can still pick meals.",
  "粘贴菜单文件的内容，检查后再确认替换。": "Paste the contents of your menu file, then review and confirm.",
  "复制菜单内容并保存为文件，就能在其他设备上导入。": "Copy the menu and save it to a file to use on another device.",
  "选择要参与的店铺和主餐。": "Choose stores and mains to include.",
  "新版本还没准备好适合这台手机的安装包，请稍后再试。": "There is no download for this phone yet. Try again later.",
  "已保存。切换到“我的菜单”就能用。": "Saved. Switch to My menu to use it.",
  "可以导入新版菜单文件。": "You can import a newer menu file.",
  "偏好只保存在本机。关闭后随机推荐，收藏不受影响。": "Preferences stay on this device. Turn this off for random picks. Your favorites stay saved.",
  "检查更新失败，请检查网络后再试。": "Could not check for updates. Check your connection and try again.",
  "这个套餐还没选店铺，先选一家。": "Choose a store for this set first.",
  "喜欢这道菜就锁定，再随机选其他菜。": "Lock a dish you like, then shuffle the others.",
  "已取消收藏，推荐不再参考这条。": "Removed from favorites and recommendations.",
  "菜单暂时打不开，本机数据已保留。请重试。": "Could not open your menu. Your data is still here. Try again.",
  "挑一份小食。": "Pick a snack.",
  "收藏已清空，原数据已另存一份。": "Favorites cleared. A local recovery copy was kept.",
  "先选主菜，再决定要不要加小食。": "Pick a main, then add a snack if you like.",
  "所属店铺": "Store",
  "只买小食": "Just a snack",
  "菜单文件内容": "Menu file contents",
  "收藏读取失败，要清空重来吗？": "Clear unreadable favorites and start over?",
  "已切换为随机推荐": "Switched to random picks.",
  "推荐会参考你的收藏": "Recommendations now use your favorites.",
  "正在选菜…": "Choosing dishes…",
  "选菜暂时失败，请重试。": "Could not choose dishes. Please try again.",
  "随机其余菜品": "Shuffle unlocked dishes",
  "菜单范围": "Menu selection",
  "文件读不出来，请换一份菜单文件再试。": "Could not read this file. Try another menu file.",
  "锁定": "Lock",
  "解锁": "Unlock",
  "清除这道菜": "Clear this dish",
  "菜品类别": "Dish category",
  "官方菜单": "Official menu",
  "我的菜单": "My menu",
  "检查菜单": "Check menu",
  "价格可能有变动，以店内为准。": "Prices may change. Check at the store.",
  "信息更新于": "Updated",
  "已保存备份，确认重置": "Backup saved, clear favorites",
  "备份后重置收藏": "Clear favorites after backup",
  "长按拖动调整顺序": "Hold and drag to reorder",
  "导航顺序保存失败，请重试": "Could not save navigation order. Please try again.",
  "筛选餐品": "Filter food",
  "按条件查找": "Find by filters",
  "按你的想法挑": "Make it yours",
  "全部菜单": "All menus",
  "筛选": "Filters",
  "重置": "Reset",
  "我的喜爱": "Favorites",
  "米饭选菜": "Rice dishes",
  "已收藏，再点取消": "Saved, tap to remove",
  "满意，收藏这一顿": "Like and save this meal",
  "根据喜爱调整推荐": "Personalize using favorites",
  "所选店铺没有米饭选菜。": "No rice dishes in the selected stores.",
  "还没有喜爱记录。选好后点击“满意，收藏这一顿”。": "No favorites yet. Choose a meal, then like and save it.",
  "保存满意的一顿，随时回看。记录的是收藏时的价格。": "Save meals you like. Prices are snapshots from when you saved them.",
  "主食分类": "Staple type",
  "米饭": "Rice",
  "面条 / 米粉": "Noodles / rice noodles",
  "饺子 / 馄饨": "Dumplings / wontons",
  "其他主食": "Other staples",
  "不含主食": "No staple",
  "全部主食": "All staple types",
  "添加个人店铺": "Add personal store",
  "给这家店添加菜品": "Add a dish to this store",
  "请填写店铺名称": "Enter a store name",
  "已经有一家同名同位置的店铺": "A store with this name and location already exists",
  "获取官方菜单更新": "Get the latest official menu",
  "从我的菜单移除": "Remove from my menu",
  "添加到我的菜单": "Add to my menu",
  "已保存店铺选择": "Store selection saved",
  "把需要的店铺加进来，不想看时可以移除。": "Add stores you need and remove them whenever you like.",
  "操作失败，请检查网络后重试；原数据保留。": "Operation failed. Check your connection and retry. Existing data is kept.",
  "官方菜单已是最新": "The official menu is up to date.",
  "官方菜单已更新，请选择需要的店铺。": "Official menu updated. Choose the stores you want.",
  "检查更新": "Check for updates",
  "当前版本": "Installed version",
  "暂无已发布版本": "No published releases yet",
  "已是最新版本": "You are up to date.",
  "价格来自现场记录，可能变动，以店内为准。": "Prices were recorded at the stores and may change. Check at the store.",
  "项目与反馈": "Project and feedback",
  "查看项目，留下问题或建议": "View the project or send feedback",
  "感谢每一位贡献者": "Thank you to every contributor",
  "复制仓库地址": "Copy repository URL",
  "仓库地址已复制，可粘贴到浏览器打开": "URL copied. Paste it into your browser to open the repository.",
  "复制失败，可长按地址手动复制": "Could not copy. Touch and hold the URL to copy it manually.",
  "筛选店铺和主餐": "Filter stores and meals",
  "已勾选主餐": "Selected meals",
  "全选": "Select all",
  "清空选择": "Deselect all",
  "应用筛选": "Apply filters",
  "菜单已更新，请重新选一次。": "Menu updated. Please choose again.",
  "套餐数据或范围已更新，请重新选择。": "Set data changed. Please choose again.",
  "填写可选菜品。套餐价格已含米饭，加价菜请另建套餐。官方套餐会复制到我的菜单。": "Enter actual cooked dishes available at the counter. The fixed price includes rice. Create separate sets for surcharges. Official templates are copied to your personal menu.",
  "套餐总价超出预算，原选择保留": "The set exceeds your budget. Current choices are kept.",
  "请重新选择菜品": "Choose dishes again.",
  "可选成品菜尚未补齐，请先维护套餐菜名": "Add available dishes before shuffling.",
  "锁定的菜已不在菜单里，请先解锁": "A locked dish is no longer available. Unlock it first.",
  "设置": "Settings",
  "语言": "Language",
  "保存失败，请重试": "Could not save. Please retry.",
  "店名、菜名及个人输入保留原文。": "Store names, dish names and your entries remain in their original language.",
  "吃什么": "Eat What",
  "中北大学": "NUC",
  "搭一顿": "Pick a meal",
  "餐品菜单": "Menu",
  "店铺": "Stores",
  "菜单管理": "Manage menus",
  "今天，吃什么？": "What shall we eat?",
  "这一顿的预算": "Budget",
  "整份餐品": "Meals",
  "米饭套餐": "Rice sets",
  "小食": "Snacks",
  "随机一份": "Random meal",
  "自己选一份": "Choose a meal",
  "随机小食": "Random snack",
  "自己选小食": "Choose a snack",
  "预算内手选一份": "Choose within budget",
  "预算内没有餐品": "No meals within budget",
  "不选小食": "Remove snack",
  "选择小食": "Choose a snack",
  "剩余预算内没有小食": "No snacks within the remaining budget",
  "合计": "Total",
  "当前选择超出新预算，请重新选择。": "Your selection exceeds the new budget. Please change it.",
  "取消": "Cancel",
  "保存": "Save",
  "关闭": "Close",
  "删除": "Delete",
  "重试": "Retry",
  "全部": "All",
  "饮品": "Drinks",
  "单点菜": "Dishes",
  "费用": "Fees",
  "主餐 / 套餐": "Meal / set",
  "配菜 / 小食": "Side / snack",
  "设好预算，给这一顿找个好搭配。": "Set your budget to choose a meal.",
  "请输入有效预算": "Enter a valid budget.",
  "预算内没有新的可选餐品；原选择保留。": "No different meal fits this budget. Your selection is kept.",
  "已为你选好一份。": "A meal has been selected.",
  "已手选小食。": "Snack selected.",
  "已手选整份餐品。": "Meal selected.",
  "已切换菜单范围。": "Menu selection changed.",
  "按店铺、窗口或菜名查找，点击查看售价和购买说明。": "Search by store, counter or dish. Tap for prices and details.",
  "搜索菜名、店铺、窗口": "Search dishes, stores or counters",
  "清除搜索": "Clear search",
  "暂无符合条件的菜品。可以在“菜单管理”添加自己的菜单。": "No dishes match. Add your own menu in Manage menus.",
  "全部店铺": "All stores",
  "选择店铺，查看它的菜品、窗口和价格。": "Choose a store to view its dishes, counters and prices.",
  "返回全部店铺": "Back to all stores",
  "这家店暂未录入菜品。": "No dishes added for this store.",
  "还没有店铺，先添加一家。": "No stores yet. Add one to get started.",
  "你的菜单，你做主": "Your menu, your choice",
  "导出备份": "Export backup",
  "导入更新": "Import update",
  "导入我的菜单": "Import personal menu",
  "添加个人菜品": "Add personal dish",
  "编辑个人菜品": "Edit personal dish",
  "删除个人菜品？": "Delete personal dish?",
  "菜名": "Dish name",
  "店铺名称": "Store name",
  "位置 / 区域": "Location / area",
  "售价（元）": "Price (CNY)",
  "份量": "Portion",
  "窗口（可留空）": "Counter (optional)",
  "购买规则 / 说明": "Purchase notes",
  "菜品类型": "Category",
  "价格来源": "Price source",
  "直接购买": "Direct purchase",
  "抖音团购": "Douyin offer",
  "在售": "Available",
  "酒精饮品（不参与推荐）": "Alcohol (excluded from recommendations)",
  "请填写菜名、店铺、份量和有效价格": "Enter a dish name, store, portion and valid price.",
  "添加照片": "Add photo",
  "更换照片": "Change photo",
  "移除照片": "Remove photo",
  "照片过大，请选择小于300KB的图片": "Please choose a photo smaller than 300 KB.",
  "编辑我的米饭套餐": "Edit personal rice set",
  "套餐名称": "Set name",
  "餐厅 / 窗口": "Store / counter",
  "整套售价（元，含米饭）": "Set price (CNY, rice included)",
  "保存到我的菜单": "Save to personal menu",
  "复制到我的菜单并补充菜名": "Copy to personal menu and add dishes",
  "编辑这个个人套餐": "Edit this set",
  "新建个人米饭套餐": "Create a rice set",
  "请输入足够的预算后选菜；已选结果保留。": "Increase the budget to choose dishes. Current choices are kept.",
  "这个套餐还没填可选菜。复制一份，补上今天的菜就能用。": "Dish options are not yet recorded. Copy this set to your library and add today’s options.",
  "可选成品菜，用顿号或换行分隔；可留空待补充": "Available dishes, separated by commas or newlines (optional)",
  "复制菜单内容": "Copy menu contents",
  "确认替换菜单": "Replace menu",
  "保存在本机，可随时修改。": "Saved on this device. Edit whenever you like.",
  "吃了么": "Eaten Yet",
  "当前：{meal} · {mode}": "Now: {meal} · {mode}",
  "当前主菜：{dish} · {store}": "Main: {dish} · {store}",
  "已勾选主餐：{count}": "Selected mains: {count}",
  "收藏时合计 ¥{price}": "Total when saved: ¥{price}",
  "{store} · 米饭另计 ¥{price}": "{store} · Rice: ¥{price} extra",
  "{store}店铺实景": "Photo of {store}",
  "导入{menu}": "Import {menu}",
  "导出{menu}": "Export {menu}",
  "已读取：{stores} 家店 · {items} 个菜品": "Read: {stores} stores · {items} items",
  "{stores} 家店 · {items} 个菜品": "{stores} stores · {items} items",
  "{count} 个菜品": "{count} items",
  "删除“{dish}”？": "Delete “{dish}”?",
  "{meal}开始": "{meal} starts",
  "{store} · 已选：{dishes}": "{store} · Selected: {dishes}",
  "已选菜品＋米饭：¥{price}": "Dishes and rice: ¥{price}",
  "用餐时间已切换，请重新选择餐品。": "Meal time changed. Choose a meal again.",
  "用餐时间": "Meal times",
  "选择用餐时间": "Choose meal times",
  "按手机时间自动切换。": "Switch automatically using your phone's time.",
  "跟随系统时间": "Automatic",
  "手动模式": "Manual",
  "跟随系统时间 / 手动模式": "Automatic or manual",
  "早餐": "Breakfast",
  "午餐": "Lunch",
  "晚餐": "Dinner",
  "保存后可在设置中修改。": "You can change this later in Settings.",
  "各餐开始时间": "Meal start times",
  "恢复默认时段": "Restore default times",
  "保存中…": "Saving…",
  "请按早餐、午餐、晚餐的先后顺序设置，开始时间不能相同。": "Set breakfast, lunch and dinner in order, with different start times.",
  "搭配方案": "Meal combination",
  "3素": "3 vegetable dishes",
  "2素1荤": "2 vegetable, 1 meat",
  "1素2荤": "1 vegetable, 2 meat",
  "自由选菜": "Choose freely",
  "鸡蛋算素菜。价格＝米饭＋所选菜品。": "Egg dishes count as vegetable dishes here. Rice and dishes are priced separately.",
  "鸡蛋算素菜。套餐价格已含米饭。": "Egg dishes count as vegetable dishes here. Rice is included in the set price.",
  "套餐（含米饭）": "Set (rice included)",
  "（免费续饭）": " (free rice refills)",
  "当前总价超出预算，请更换菜品或取消小食。": "Over budget. Change a dish or remove the snack.",
  "所选菜品和小食超出预算，原选择保留": "Dishes and snack exceed your budget. Your previous choices are kept.",
  "复制到我的菜单并编辑": "Copy to My menu and edit",
  "套餐来源": "Rice set",
  "我的米饭套餐": "My rice set",
  "请检查套餐名称、价格和菜品。": "Check the set name, price and dishes.",
  "同一道菜的价格必须一致": "Use the same price for the same dish.",
  "小食店铺": "Snack store",
  "已取消收藏": "Removed from favorites.",
  "已收藏到“我的喜爱”": "Saved to Favorites.",
  "删除喜爱记录": "Remove from favorites",
  "删除个人菜品": "Delete personal dish",
  "已下架": "Unavailable",
  "重新读取": "Try loading again",
  "导出备份（排障用）": "Export recovery backup",
  "复制排障备份": "Copy recovery backup",
  "复制失败，请重试。": "Could not copy. Try again.",
  "已复制，请保存备份": "Copied. Save your backup.",
  "照片读取失败，请换一张再试。": "Could not read this photo. Try another one.",
  "菜单保存后超过容量上限，请减少内容后重试": "This menu is too large to save. Remove some content and try again.",
  "最多保存500条收藏，请先删除部分记录": "You can save up to 500 favorites. Remove some first.",
  "收藏超过10MB，请先删除部分含照片的记录": "Favorites exceed 10 MB. Remove some entries with photos first.",
  "请先选好这一顿": "Choose your meal first.",
  "已选好，锁定的菜保持不变。": "Dishes selected. Locked dishes are unchanged.",
  "暂无其他合适搭配，已保留当前选择。": "No other suitable combination. Your choices are kept.",
  "点击检查新版本。更新由你决定，不会自动安装。": "Check for a new version. Updates are optional and will not install automatically.",
  "发现新版本；此设备不支持安卓安装包。": "A new version is available, but this device cannot install Android apps.",
  "发现新版本，可直接在应用内下载更新。": "A new version is available. Download it here to update.",
  "正在下载安装包，请保持应用打开。": "Downloading. Keep the app open.",
  "下载完成，正在检查安装包…": "Download complete. Checking the file…",
  "下载已取消，可以重新下载。": "Download cancelled. You can try again.",
  "安装包处理失败，请重新下载。": "Could not prepare the installer. Download it again.",
  "下载失败或文件不完整。请检查网络和剩余空间后重试。": "Download failed or is incomplete. Check your connection and storage, then retry.",
  "请允许“吃了么”安装应用，返回后点击“继续安装”。": "Allow Eaten Yet to install apps, then return and tap Continue installation.",
  "已打开系统安装界面，请确认安装。若取消，可点击“继续安装”。": "Confirm installation on your phone. If you cancel, tap Continue installation to try again.",
  "无法启动安装，请重试。": "Could not start installation. Try again.",
  "应用更新": "App updates",
  "正在取消下载…": "Cancelling download…",
  "取消下载": "Cancel download",
  "继续安装": "Continue installation",
  "下载并安装更新": "Download and install update",
  "早餐 {breakfast}—{lunch}\n午餐 {lunch}—{dinner}\n晚餐 {dinner}—次日{breakfast}": "Breakfast {breakfast}–{lunch}\nLunch {lunch}–{dinner}\nDinner {dinner}–{breakfast} next day",
  "请按 菜名|价格 填写每道菜": "Enter each dish as name|price.",
  "每道菜填写“菜名|价格”，用顿号或换行分隔。米饭价格单独填写。": "Enter each dish as name|price, separated by commas or newlines. Enter the rice price separately.",
  "排障备份包含本机个人数据，仅供排查问题，请私下保存。不能作为菜单文件导入。": "This backup contains personal data for troubleshooting. Keep it private. It cannot be imported as a menu.",
  "原数据暂时读不出来，请稍后重试。": "The original data could not be read. Please try again later.",
  "单独买小食": "Just snacks",
  "先选店铺，再挑一份喜欢的小食。": "Choose a store, then pick a snack.",
  "这是示例数据，不是真实菜单。": "This is a sample, not a real menu.",
  "示例": "Sample",
  "自己挑，或者交给它随机。": "Pick your dishes or let the app choose.",
  "米饭价格（元）": "Rice price (yuan)",
  "搭配已切换，已选菜品和锁定保持不变。": "Combination changed. Your chosen and locked dishes are unchanged.",
};
