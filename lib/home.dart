import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'repository.dart';
import 'rice.dart';
import 'rice_panel.dart';
import 'photos.dart';
import 'snacks.dart';
import 'meal_filter.dart';
import 'language.dart';

class CampusHome extends StatefulWidget {
  const CampusHome({super.key});
  @override
  State<CampusHome> createState() => _CampusHomeState();
}
class _CampusHomeState extends State<CampusHome> {
  MenuRepository? repo;
  String? loadError;
  final budget = TextEditingController(text: '20');
  Scope scope = Scope.merged;
  bool busy = false;
  Entry? snack;
  Set<String>? mealFilter;
  int filterRevision = 0;
  String mealCategory = 'main';
  String browseCategory = 'all';
  int tab = 0;
  String? selectedStore;
  String query = '', message = '设好预算，给这一顿找个好搭配。';
  List<Entry?> selection = [null, null, null];
  final random = Random();
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { budget.dispose(); super.dispose(); }
  Future<void> load() async {
    try { final r = await MenuRepository.load(); if (mounted) setState(() { repo = r; loadError = null; }); }
    catch (e) { if (mounted) setState(() => loadError = '菜单加载失败，未覆盖本地数据：$e'); }
  }
  List<Entry> get pool => entries(repo!.official, repo!.personal, scope);
  void notify(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(text))); }
  Future<bool> save(MenuDb db) async {
    setState(() => busy = true);
    try { await repo!.replace(db); if (mounted) setState(() {
      snack = null; selection = [null,null,null];
      message = '菜单已更新；请重新生成。已有锁定项会核对价格和来源。';
    }); return true; }
    catch (e) { notify('保存失败：$e'); return false; }
    finally { if (mounted) setState(() => busy = false); }
  }
  List<Entry> get wholeMeals => pool.where((e) => (mealCategory != 'main' || matchesMealFilter(mealFilter, e.key)) && e.offer.kind == mealCategory && !e.offer.addonOnly && e.offer.available &&
    !e.offer.alcohol && e.offer.channel == 'regular').toList();
  void draw() {
    final cents = parseMoney(budget.text);
    if (cents == null || cents <= 0) { setState(() => message = '请输入有效预算'); return; }
    final candidates = wholeMeals.where((e) => mealCostWithSnack(e, snack) <= cents && e.key != selection[0]?.key).toList();
    setState(() {
      if (candidates.isEmpty) { message = '预算内没有新的可选餐品；原选择保留。'; return; }
      final picked = candidates[random.nextInt(candidates.length)];
      if (snack?.placeKey != picked.placeKey) snack = null;
      selection = [picked, null, null];
      message = '已为你选好一份。';
    });
  }
  Future<void> chooseWhole() async {
    final cents = parseMoney(budget.text);
    if (cents == null || cents <= 0) { setState(() => message='请输入有效预算'); return; }
    final choices = wholeMeals.where((e) => mealCostWithSnack(e, snack) <= cents).toList();
    final chosen = await showDialog<Entry>(context: context, builder: (ctx) => AlertDialog(
      title: const LText('预算内手选一份'), content: SizedBox(width: 520, height: 420,
        child: choices.isEmpty ? const LText('预算内没有餐品') : ListView.builder(itemCount: choices.length,
          itemBuilder: (ctx,i) => ListTile(leading: DishPhoto(data: choices[i].offer.photo), title: LText(choices[i].offer.name),
            subtitle: LText('${choices[i].place.name} ${choices[i].offer.window} · ¥${money(choices[i].offer.priceCents)}'),
            onTap: () => Navigator.pop(ctx,choices[i])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消'))]));
    if (chosen != null && mounted) setState(() { if (snack?.placeKey != chosen.placeKey) snack=null; selection=[chosen,null,null]; message=mealCategory == 'side' ? '已手选小食。' : '已手选整份餐品。'; });
  }
  Map<String,String> get storeChoices => {
    if (scope != Scope.personal) for (final p in repo!.official.places) 'official:${p.id}': p.name,
    if (scope != Scope.official) for (final p in repo!.personal.places) 'personal:${p.id}': p.name,
  };
  List<(String, RicePlan)> get ricePlans => [
    if (scope != Scope.personal) ...repo!.official.ricePlans.map((p) => ('official:${p.id}',p)),
    if (scope != Scope.official) ...repo!.personal.ricePlans.map((p) => ('personal:${p.id}',p)),
  ];
  Future<void> filterMeals() async {
    final targets = <MealTarget>[
      for (final e in pool.where((e) => e.offer.kind == 'main' && e.offer.available && e.offer.channel == 'regular'))
        MealTarget(e.key, e.placeKey, e.place.name, e.offer.name),
      for (final p in ricePlans)
        MealTarget('rice:${p.$1}', riceStoreKey(p.$2, storeChoices) ?? 'unknown:${p.$1}',
          storeChoices[riceStoreKey(p.$2, storeChoices)] ?? p.$2.location, p.$2.name),
    ];
    final selected = await showMealFilter(context, targets, mealFilter);
    if (selected != null && mounted) setState(() {
      mealFilter=selected; filterRevision++; selection=[null,null,null]; snack=null;
    });
  }
  Future<bool> saveRice(RicePlan plan) {
    final db=repo!.personal;
    return save(MenuDb(source: db.source, revision: db.revision+1, places: db.places,
      foods: db.foods, offers: db.offers, ricePlans: [...db.ricePlans.where((p) => p.id != plan.id),plan]));
  }
  Widget title(String heading, String detail) => Padding(padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LText(heading, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6), LText(detail, style: const TextStyle(color: Color(0xff70665c))),
    ]));
  Widget scopePicker() => DropdownButtonFormField<Scope>(initialValue: scope, isExpanded: true,
    decoration: InputDecoration(labelText: tr(context, '使用哪个菜单库')),
    items: const [DropdownMenuItem(value: Scope.merged, child: LText('官方库 + 个人库', overflow: TextOverflow.ellipsis)),
      DropdownMenuItem(value: Scope.official, child: LText('仅官方库')),
      DropdownMenuItem(value: Scope.personal, child: LText('仅个人库'))],
    onChanged: (v) => setState(() { scope = v!; mealFilter=null; filterRevision++; selectedStore=null; snack=null; selection=[null,null,null]; message = '范围已改变；重新生成时会检查锁定项。'; }));
  Widget decide() {
    final chosen=selection[0];
    final plans = ricePlans.where((p) => matchesMealFilter(mealFilter, 'rice:${p.$1}')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('今天，吃什么？', '整份餐品、米饭套餐、小食分开选。'),
      Row(children: [Expanded(child: TextField(controller: budget, onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr(context, '本顿预算'),prefixText: '¥ '))),
        const SizedBox(width: 12), Expanded(child: scopePicker())]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final item in const [('main','整份餐品'),('rice','米饭套餐'),('side','小食')])
          ChoiceChip(key: ValueKey('meal-category-${item.$1}'), label: LText(item.$2), selected: mealCategory == item.$1,
            onSelected: (_) => setState(() { mealCategory=item.$1; snack=null; selection=[null,null,null]; message='已切换分类，请选择餐品。'; })),
      ]),
      const SizedBox(height: 12),
      if (mealCategory != 'side') ...[
        OutlinedButton.icon(onPressed: filterMeals, icon: const Icon(Icons.filter_list), label: const LText('筛选店铺和主餐')),
        if (mealFilter != null) Text('${tr(context,"已勾选主餐")}：${mealFilter!.length}'),
        if (mealFilter != null) TextButton(onPressed: () => setState(() { mealFilter=null; filterRevision++; selection=[null,null,null]; snack=null; }), child: LText('清除筛选')),
        if (mealFilter != null && mealFilter!.isEmpty) const LText('未勾选主餐，请调整筛选。'),
      ],
      if (mealCategory == 'side') const Padding(padding: EdgeInsets.only(bottom: 12),
        child: LText('单独选择一份小食，按当前预算计费；不与套餐自动合并。仅限加料的项目不参与。')),
      if (mealCategory == 'rice') RicePanel(key: ValueKey('rice-filter-$filterRevision'), stores: storeChoices, plans: plans, budget: parseMoney(budget.text), savePersonal: saveRice, snacks: pool)
      else ...[
        if (chosen != null) Card(child: ListTile(leading: DishPhoto(data: chosen.offer.photo), onTap: () => detail(chosen), title: LText(chosen.offer.name),
          subtitle: LText('${chosen.place.name} ${chosen.offer.window}'),
          trailing: LText('¥${money(chosen.offer.priceCents)}'))),
        if (chosen != null && (chosen.offer.priceCents + (snack?.offer.priceCents ?? 0)) > (parseMoney(budget.text) ?? 0))
          const LText('当前选择超出新预算，请重新选择。',style: TextStyle(color: Colors.red)),
        FilledButton.icon(onPressed: draw,icon: const Icon(Icons.shuffle), label: LText(mealCategory == 'side' ? '随机小食' : '随机一份')),
        TextButton(onPressed: chooseWhole, child: LText(mealCategory == 'side' ? '自己选小食' : '自己选一份')),
        LText(message,key: const Key('status')),
        if (mealCategory == 'main' && chosen != null) SnackPanel(placeKey: chosen.placeKey, pool: pool, budget: parseMoney(budget.text), mainPrice: chosen.offer.priceCents, selected: snack, onChanged: (v) => setState(() => snack=v)),
      ],
      const SizedBox(height: 12), const LText('数据来自10月15日；预算不含打包、配送费用。'),
    ]);
  }
  void detail(Entry e) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: LText(e.offer.name),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        DishPhoto(data: e.offer.photo, large: true), const SizedBox(height: 16),
        LText('${e.place.name} · ${e.place.area}\n${e.offer.portion} · ¥${money(e.offer.priceCents)}\n价格记录：${e.offer.updatedAt}\n${e.offer.available ? '库内标记：在售（非实时）' : '已下架'}'),
        const SizedBox(height: 12), LText('${kindNames[e.offer.kind]} · ${e.offer.window}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}\n${e.offer.notes}\n来源：${e.offer.evidence}\n拍摄日期：${e.offer.observedAt.isEmpty ? '截图未显示' : e.offer.observedAt}'),
        if (e.offer.example) const LText('这是示例数据，不是真实菜单。'),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('关闭'))]));
  }
  bool matchesCategory(Entry e) => browseCategory == 'all' ||
    e.offer.kind == browseCategory && (browseCategory != 'side' || !e.offer.addonOnly);
  Widget categoryFilter() => Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, children: [
    for (final item in const [('all','全部'),('main','整份餐品 / 套餐'),('side','小食'),('drink','饮品'),('dish','单点菜'),('fee','费用')])
      ChoiceChip(label: LText(item.$2), selected: browseCategory == item.$1,
        onSelected: (_) => setState(() => browseCategory=item.$1)),
  ]));
  Widget shopPhoto(String storeKey, {bool thumbnail = false}) {
    if (storeKey != 'official:sf') return SizedBox(width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200, child: const ColoredBox(color: Color(0xffeee7df), child: Icon(Icons.storefront)));
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(
      'assets/stores/shiweifang.jpg', key: ValueKey(thumbnail ? 'sf-thumbnail' : 'sf-cover'),
      width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200,
      fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: '食味坊店铺实景',
      errorBuilder: (_, error, stackTrace) => const SizedBox(height: 56, child: Icon(Icons.storefront)),
    ));
  }
  Widget catalog() {
    final visible = pool.where((e) => matchesCategory(e) && (query.isEmpty || e.offer.name.contains(query) || e.place.name.contains(query) || e.offer.window.contains(query))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('餐品菜单', '按店铺、窗口或菜名查找，点击查看售价和购买说明。'), scopePicker(), const SizedBox(height: 14), categoryFilter(),
      TextFormField(key: ValueKey('search-$query'), initialValue: query,
        decoration: InputDecoration(labelText: tr(context, '搜索菜名、店铺、窗口'), prefixIcon: Icon(Icons.search)),
        onFieldSubmitted: (v) => setState(() => query = v.trim())),
      const SizedBox(height: 8), if (query.isNotEmpty) TextButton(onPressed: () => setState(() => query = ''), child: const LText('清除搜索')),
      LText('${visible.length} 个售卖项'),
      for (final e in visible) Card(child: ListTile(leading: DishPhoto(data: e.offer.photo), onTap: () => detail(e), title: LText(e.offer.name),
        subtitle: LText('${e.place.name} ${e.offer.window} · ${kindNames[e.offer.kind]}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}\n${e.db.source == Source.official ? '官方库' : '个人库'}${e.offer.example ? ' · 示例' : ''}${e.offer.available ? '' : ' · 已下架'}'),
        trailing: LText('¥${money(e.offer.priceCents)}'))),
      if (visible.isEmpty) const Padding(padding: EdgeInsets.all(20), child: LText('暂无符合条件的菜品。可在“菜单库”录入个人菜单。')),
    ]);
  }
  Widget stores() {
    final shops = <(String, Place, MenuDb)>[
      if (scope != Scope.personal) ...repo!.official.places.map((p) => ('official:${p.id}', p, repo!.official)),
      if (scope != Scope.official) ...repo!.personal.places.map((p) => ('personal:${p.id}', p, repo!.personal)),
    ];
    final selected = shops.where((s) => s.$1 == selectedStore).firstOrNull;
    final dishes = selected == null ? <Entry>[] : selected.$3.offers
      .where((o) => o.placeId == selected.$2.id).map((o) => Entry(o, selected.$3)).where(matchesCategory).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title(selected == null ? '全部店铺' : selected.$2.name,
        selected == null ? '选择店铺，查看它的菜品、窗口和价格。' : selected.$2.area),
      scopePicker(), const SizedBox(height: 12),
      if (selected == null) ...[
        LText('${shops.length} 家店铺'),
        for (final shop in shops) Card(child: ListTile(
          key: ValueKey('store-${shop.$1}'), leading: shopPhoto(shop.$1, thumbnail: true),
          title: LText(shop.$2.name), subtitle: LText('${shop.$2.area}\n${shop.$3.source == Source.official ? '官方库' : '个人库'} · ${shop.$3.offers.where((o) => o.placeId == shop.$2.id).length} 个售卖项'),
          trailing: const Icon(Icons.chevron_right), onTap: () => setState(() { selectedStore=shop.$1; browseCategory='all'; }))),
        if (shops.isEmpty) const LText('当前菜单库还没有店铺，可在菜单库中添加个人餐品。'),
      ] else ...[
        TextButton.icon(onPressed: () => setState(() => selectedStore=null), icon: const Icon(Icons.arrow_back), label: const LText('返回全部店铺')),
        shopPhoto(selected.$1),
        const SizedBox(height: 12), categoryFilter(),
        LText('${dishes.length} 个售卖项'),
        for (final e in dishes) Card(child: ListTile(leading: DishPhoto(data: e.offer.photo), onTap: () => detail(e), title: LText(e.offer.name),
          subtitle: LText('${e.offer.window} · ${kindNames[e.offer.kind]}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}${e.offer.available ? '' : ' · 暂不可选'}'),
          trailing: LText('¥${money(e.offer.priceCents)}'))),
        if (dishes.isEmpty) const LText('这家店暂未录入菜品。'),
      ],
    ]);
  }
  Future<void> transfer(Source source, bool importing) async {
    final db = source == Source.official ? repo!.official : repo!.personal;
    final controller = TextEditingController(text: importing ? '' : db.encode());
    String? error;
    MenuDb? parsed;
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: LText('${importing ? '导入' : '导出'}${source == Source.official ? '官方' : '个人'}库'),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        LText(importing ? '粘贴 JSON 数据包。先校验，再确认替换这个库；另一个库不受影响。建议先导出备份。' : '复制 JSON 保存为 UTF-8 文件，之后可在另一台设备导入。'),
        if (source == Source.official && importing) const LText('原型仅支持手动数据包；“官方”是库类型标记，尚无服务器签名认证。'),
        const SizedBox(height: 12), TextField(controller: controller, readOnly: !importing, minLines: 6, maxLines: 12,
          onChanged: (_) => refresh(() { parsed = null; error = null; }), decoration: InputDecoration(labelText: tr(context, 'JSON 数据包'))),
        if (error != null) LText(error!, style: const TextStyle(color: Colors.red)),
        if (parsed != null) LText('校验通过：版本 ${parsed!.revision} · ${parsed!.places.length} 家店 · ${parsed!.offers.length} 个售卖项'),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const LText('关闭')),
        if (!importing) FilledButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: controller.text)); notify('已复制，请保存备份'); }, child: const LText('复制数据')),
        if (importing) TextButton(onPressed: () { try {
          final data = MenuDb.decode(controller.text, source);
          if (source == Source.official && data.revision <= db.revision) throw const FormatException('官方更新版本必须高于当前版本');
          refresh(() { parsed = data; error = null; });
        } catch (e) { refresh(() { parsed = null; error = '校验失败：$e'; }); } }, child: const LText('校验数据')),
        if (importing) FilledButton(onPressed: parsed == null ? null : () => Navigator.pop(ctx, true), child: const LText('确认替换此库')),
      ])));
    // Controllers remain alive until the closing dialog animation has finished.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (accepted == true && parsed != null && mounted) await save(parsed!);
  }
  Future<void> editOffer([Offer? old]) async {
    final db = repo!.personal;
    final place = old == null ? null : db.places.firstWhere((p) => p.id == old.placeId);
    final name = TextEditingController(text: old?.name ?? '');
    final shop = TextEditingController(text: place?.name ?? '');
    final area = TextEditingController(text: place?.area ?? '中北大学周边');
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final portion = TextEditingController(text: old?.portion ?? '1 份');
    final window = TextEditingController(text: old?.window ?? '');
    final notes = TextEditingController(text: old?.notes ?? '');
    String photo = old?.photo ?? '';
    bool picking = false;
    String kind = old?.kind ?? 'main', channel = old?.channel ?? 'regular';
    bool addon = old?.addonOnly ?? false, alcohol = old?.alcohol ?? false;
    bool available = old?.available ?? true;
    String? error;
    final accepted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => Scaffold(
      appBar: AppBar(title: LText(old == null ? '添加个人菜品' : '编辑个人菜品')), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Column(mainAxisSize: MainAxisSize.min, children: [
        DishPhoto(data: photo, large: true),
        Wrap(spacing: 12, children: [TextButton.icon(onPressed: picking ? null : () async {
          refresh(() => picking=true);
          try { final picked = await pickDishPhoto(); if (ctx.mounted && picked != null) refresh(() => photo=picked); }
          catch (e) { if (ctx.mounted) refresh(() => error=e.toString()); }
          finally { if (ctx.mounted) refresh(() => picking=false); }
        }, icon: const Icon(Icons.photo_library_outlined), label: LText(photo.isEmpty ? '添加照片' : '更换照片')),
        if (photo.isNotEmpty) TextButton(onPressed: () => refresh(() => photo=''), child: const LText('移除照片'))]),
        const SizedBox(height: 20),
        for (final field in [(name, '菜名'), (shop, '店铺名称'), (area, '位置 / 区域'), (price, '售价（元）'), (portion, '份量'), (window, '窗口（可留空）'), (notes, '购买规则 / 说明')])
          Padding(padding: const EdgeInsets.only(bottom: 20), child: TextField(controller: field.$1, decoration: InputDecoration(labelText: tr(context, field.$2)))),
        DropdownButtonFormField<String>(initialValue: kind, decoration: InputDecoration(labelText: tr(context, '售卖类型')),
          items: kindNames.entries.map((e) => DropdownMenuItem(value: e.key, child: LText(e.value))).toList(),
          onChanged: (v) => refresh(() { kind = v!; addon = false; alcohol = false; })),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(initialValue: channel, decoration: InputDecoration(labelText: tr(context, '价格渠道')),
          items: const [DropdownMenuItem(value: 'regular', child: LText('直接购买')), DropdownMenuItem(value: 'douyin', child: LText('抖音团购'))],
          onChanged: (v) => refresh(() => channel = v!)),
        const SizedBox(height: 16),
        if (kind == 'drink') CheckboxListTile(title: const LText('酒精饮品（不自动推荐）'), value: alcohol, onChanged: (v) => refresh(() => alcohol = v!)),
        CheckboxListTile(title: const LText('在售'), value: available, onChanged: (v) => refresh(() => available = v!)),
        if (error != null) LText(error!, style: const TextStyle(color: Colors.red)),
      ]))))), bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const LText('取消')),
        FilledButton(onPressed: picking ? null : () {
          if (name.text.trim().isEmpty || shop.text.trim().isEmpty || portion.text.trim().isEmpty ||
            (parseMoney(price.text) ?? 0) <= 0) {
            refresh(() => error = '请填写菜名、店铺、份量和有效价格'); return;
          }
          Navigator.pop(ctx, true);
        }, child: const LText('保存')),
      ])))))));
    if (accepted == true && mounted) {
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final places = [...db.places], foods = [...db.foods];
      final found = places.where((p) => p.name == shop.text.trim() && p.area == area.text.trim()).firstOrNull;
      final chosenPlace = found ?? Place('p$stamp', shop.text.trim(), area.text.trim());
      if (found == null) places.add(chosenPlace);
      final offer = Offer(id: old?.id ?? 'o$stamp', placeId: chosenPlace.id, name: name.text.trim(),
        portion: portion.text.trim(), priceCents: parseMoney(price.text)!, roles: old?.roles ?? {}, foodIds: old?.foodIds ?? {},
        updatedAt: DateTime.now().toIso8601String(), ingredientsKnown: old?.ingredientsKnown ?? false, available: available,
        example: old?.example ?? false, kind: kind, channel: channel, window: window.text.trim(),
        photo: photo, notes: notes.text.trim(), addonOnly: addon, alcohol: alcohol,
        evidence: old?.evidence ?? '个人录入', observedAt: old?.observedAt ?? '');
      await save(MenuDb(source: Source.personal, revision: db.revision + 1, places: places, foods: foods,
        ricePlans: db.ricePlans, offers: [...db.offers.where((o) => o.id != old?.id), offer]));
    }
    Future<void>.delayed(const Duration(seconds: 1), () { for (final c in [name, shop, area, price, portion, window, notes]) { c.dispose(); } });
  }
  Future<void> deleteOffer(Offer offer) async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const LText('删除个人菜品？'),
      content: LText('将删除“${offer.name}”，官方库不受影响。'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const LText('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const LText('删除'))]));
    if (accepted != true || !mounted) return;
    final db = repo!.personal;
    await save(MenuDb(source: db.source, revision: db.revision + 1, places: db.places, foods: db.foods, ricePlans: db.ricePlans, offers: db.offers.where((o) => o.id != offer.id).toList()));
  }
  Widget libraries() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    title('你的菜单，你做主', '官方库和个人库独立保存，可单独使用，也可合并推荐。'),
    for (final db in [repo!.official, repo!.personal]) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LText(db.source == Source.official ? '官方菜单库' : '我的个人库', style: Theme.of(context).textTheme.titleLarge),
      LText('版本 ${db.revision} · ${db.places.length} 家店 · ${db.offers.length} 个售卖项'),
      const SizedBox(height: 10), LText(db.source == Source.official ? '内置照片菜单；可导入团队维护的更高版本数据包。' : '仅存于本机，支持录入、修改、下架及备份迁移。'),
      Wrap(spacing: 8, children: [TextButton(onPressed: busy ? null : () => transfer(db.source, false), child: const LText('导出备份')),
        TextButton(onPressed: busy ? null : () => transfer(db.source, true), child: LText(db.source == Source.official ? '导入更新' : '导入个人库'))]),
    ]))),
    const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : () => editOffer(), icon: const Icon(Icons.add), label: const LText('添加个人菜品')),
    const SizedBox(height: 12),
    for (final o in repo!.personal.offers) Card(child: ListTile(leading: DishPhoto(data: o.photo), title: LText(o.name), subtitle: LText('¥${money(o.priceCents)} · ${o.available ? '在售' : '已下架'}'),
      onTap: busy ? null : () => editOffer(o), trailing: IconButton(tooltip: '删除个人菜品', onPressed: busy ? null : () => deleteOffer(o), icon: const Icon(Icons.delete_outline)))),
    const SizedBox(height: 12), const LText('跨库同名店铺暂按不同来源处理，不自动合并身份。官方更新不会覆盖个人数据。当前不含云同步、实时价格或商家营业验证。'),
  ]);
  @override
  Widget build(BuildContext context) {
    if (repo == null) return Scaffold(body: Center(child: loadError == null ? const CircularProgressIndicator() :
      Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [LText(loadError!), TextButton(onPressed: load, child: const LText('重试'))]))));
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final page = SingleChildScrollView(key: ValueKey(tab), padding: EdgeInsets.all(wide ? 32 : 16),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: [decide, catalog, stores, libraries][tab]())));
    return Scaffold(appBar: AppBar(actions: [IconButton(tooltip: tr(context,'设置'), onPressed: () => openSettings(context), icon: const Icon(Icons.settings_outlined))], title: Row(children: [Image.asset('assets/icon.png', width: 36, height: 36), const SizedBox(width: 10), const LText('吃什么'), const SizedBox(width: 12), const Flexible(child: LText('中北大学', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14)))])),
      body: AbsorbPointer(absorbing: busy, child: Row(children: [if (wide) NavigationRail(selectedIndex: tab, labelType: NavigationRailLabelType.all,
        onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
          NavigationRailDestination(icon: Icon(Icons.shuffle), label: LText('搭一顿')),
          NavigationRailDestination(icon: Icon(Icons.restaurant_menu), label: LText('餐品菜单')),
          NavigationRailDestination(icon: Icon(Icons.storefront), label: LText('店铺')),
          NavigationRailDestination(icon: Icon(Icons.storage), label: LText('菜单库'))]), Expanded(child: page)])),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: tab, onDestinationSelected: (i) { if (!busy) setState(() => tab = i); }, destinations: [
        NavigationDestination(icon: Icon(Icons.shuffle), label: tr(context, '搭一顿')), NavigationDestination(icon: Icon(Icons.restaurant_menu), label: tr(context, '餐品菜单')),
        NavigationDestination(icon: Icon(Icons.storefront), label: tr(context, '店铺')),
        NavigationDestination(icon: Icon(Icons.storage), label: tr(context, '菜单库'))]),
    );
  }
}
