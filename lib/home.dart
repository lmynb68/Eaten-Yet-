import 'dart:math';
import 'dart:async';
import 'meal_period.dart';
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
import 'official_library.dart';
import 'favorites.dart';
import 'filter_sheet.dart';
import 'navigation_order.dart';

class CampusHome extends StatefulWidget {
  const CampusHome({super.key});
  @override
  State<CampusHome> createState() => _CampusHomeState();
}
class _CampusHomeState extends State<CampusHome> with WidgetsBindingObserver {
  String mealChoice="auto";
  String currentPeriod=clockPeriod(DateTime.now());
  Timer? mealTimer;
  bool mealPromptOpen=false;
  MenuRepository? repo;
  FavoriteStore? favorites;
  String mainMode = 'main';
  String? sideStore;
  String? catalogStore;
  String? mealStore;
  Entry? standaloneSide;
  String? loadError;
  final budget = TextEditingController(text: '20');
  Scope scope = Scope.merged;
  bool busy = false;
  Entry? snack;
  Set<String>? mealFilter;
  int filterRevision = 0;
  String mealCategory = 'main';
  String browseCategory = 'all';
  String stapleFilter = 'all';
  int tab = 0;
  List<int> navigationOrder = [0, 1, 2, 3, 4];
  bool savingNavigation = false;
  String? selectedStore;
  String query = '', message = '设好预算，给这一顿找个好搭配。';
  List<Entry?> selection = [null, null, null];
  final random = Random();
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); load(); }
  @override
  void dispose() { mealTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); budget.dispose(); super.dispose(); }
  Future<void> load() async {
    try { final r = await MenuRepository.load(); final f = await FavoriteStore.load(r.preferences); if (mounted) setState(() { favorites = f; repo = r; mealChoice=readMealChoice(r.preferences); currentPeriod=mealChoice=="auto"?clockPeriod(DateTime.now(),readMealSchedule(r.preferences)):mealChoice; navigationOrder = readNavigationOrder(r.preferences); loadError = null; });
      if(mounted) scheduleMealClock();
      if(mounted && !hasMealChoice(r.preferences) && !mealPromptOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted) configureMeal(first:true);});
      }
    }
    catch (e) { if (mounted) setState(() => loadError = '菜单加载失败，未覆盖本地数据：$e'); }
  }
  Future<void> reorderNavigation(int oldIndex, int newIndex) async {
    if (busy || savingNavigation) return;
    if (oldIndex == newIndex) return;
    final previous = List<int>.of(navigationOrder);
    final updated = List<int>.of(previous);
    updated.insert(newIndex, updated.removeAt(oldIndex));
    setState(() { navigationOrder = updated; savingNavigation = true; });
    try { await saveNavigationOrder(repo!.preferences, updated); }
    catch (_) {
      if (mounted) {
        setState(() => navigationOrder = previous);
        notify('导航顺序保存失败，请重试');
      }
    } finally { if (mounted) setState(() => savingNavigation = false); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed) refreshMealPeriod();
  }
  void scheduleMealClock() {
    mealTimer?.cancel();
    if(mealChoice=='auto') mealTimer=Timer.periodic(const Duration(seconds:30),(_)=>refreshMealPeriod());
  }
  void refreshMealPeriod() {
    if(!mounted || repo==null) return;
    final next=mealChoice=='auto'?clockPeriod(DateTime.now(),readMealSchedule(repo!.preferences)):mealChoice;
    if(next==currentPeriod) return;
    setState(() {currentPeriod=next; resetMealSelection();});
  }
  void resetMealSelection() {
    selection=[null,null,null]; snack=null; standaloneSide=null; mealStore=null; sideStore=null;
    mealFilter=null; mealCategory='main'; mainMode='main'; filterRevision++;
    message='已切换到${periodNames[currentPeriod]}，请重新选择餐品。';
  }
  Future<void> configureMeal({bool first=false, BuildContext? dialogContext}) async {
    if(mealPromptOpen || repo==null) return;
    mealPromptOpen=true;
    try {
      final value=await showMealChoice(dialogContext ?? context,repo!.preferences,first:first);
      if(value!=null && mounted) setState(() {
        mealChoice=value; currentPeriod=value=='auto'?clockPeriod(DateTime.now(),readMealSchedule(repo!.preferences)):value;
        resetMealSelection();
        scheduleMealClock();
      });
    } finally {mealPromptOpen=false;}
  }
  List<Entry> get pool => allPool.where((e)=>e.offer.mealPeriods.contains(currentPeriod)).toList();
  List<Entry> get allPool => entries(repo!.activeOfficial, repo!.personal, scope);
  void notify(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(text))); }
  Future<bool> save(MenuDb db) async {
    setState(() => busy = true);
    try { await repo!.replace(db); if (mounted) setState(() {
      snack = null; selection = [null,null,null]; standaloneSide=null; sideStore=null; filterRevision++;
      message = '菜单已更新；请重新生成。已有锁定项会核对价格和来源。';
    }); return true; }
    catch (e) { notify('保存失败：$e'); return false; }
    finally { if (mounted) setState(() => busy = false); }
  }
  List<Entry> get wholeMeals => pool.where((e) => (mealCategory != 'main' || mealStore == null || e.placeKey == mealStore) && (mealCategory != 'side' || sideStore == null || e.placeKey == sideStore) && (mealCategory != 'main' || matchesMealFilter(mealFilter, e.key)) && e.offer.kind == mealCategory && (mealCategory != 'main' || stapleFilter == 'all' || e.offer.stapleType == stapleFilter) && !e.offer.addonOnly && e.offer.available &&
    !e.offer.alcohol && e.offer.channel == 'regular').toList();
  void draw() {
    final cents = parseMoney(budget.text);
    if (cents == null || cents <= 0) { setState(() => message = '请输入有效预算'); return; }
    final candidates = wholeMeals.where((e) => mealCostWithSnack(e, snack) <= cents && e.key != (mealCategory == 'side' ? standaloneSide : selection[0])?.key).toList();
    setState(() {
      if (candidates.isEmpty) { message = '预算内没有新的可选餐品；原选择保留。'; return; }
      final picked = weightedPick(candidates, random, (e) => favorites!.score([e.key, if (snack?.placeKey == e.placeKey) snack!.key]));
      if (snack?.placeKey != picked.placeKey) snack = null;
      if (mealCategory == 'side') { standaloneSide = picked; } else { selection = [picked, null, null]; }
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
          itemBuilder: (ctx,i) => ListTile(leading: DishPhoto(asset: dishAssetForEntry(choices[i]), data: choices[i].offer.photo), title: LText(choices[i].offer.name),
            subtitle: LText('${choices[i].place.name} ${choices[i].offer.window} · ¥${money(choices[i].offer.priceCents)}'),
            onTap: () => Navigator.pop(ctx,choices[i])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消'))]));
    if (chosen != null && mounted && chosen.offer.mealPeriods.contains(currentPeriod)) setState(() { if (snack?.placeKey != chosen.placeKey) snack=null; if (mealCategory == 'side') { standaloneSide=chosen; } else { selection=[chosen,null,null]; } message=mealCategory == 'side' ? '已手选小食。' : '已手选整份餐品。'; });
  }
  Map<String,String> get storeChoices => {
    if (scope != Scope.personal) for (final p in repo!.activeOfficial.places) 'official:${p.id}': p.name,
    if (scope != Scope.official) for (final p in repo!.personal.places) 'personal:${p.id}': p.name,
  };
  List<(String, RicePlan)> get ricePlans => allRicePlans.where((p)=>currentPeriod!='breakfast' || p.$1.startsWith('personal:')).toList();
  List<(String, RicePlan)> get allRicePlans => [
    if (scope != Scope.personal) ...repo!.activeOfficial.ricePlans.where((p) => riceStoreKey(p, storeChoices) == 'official:sf').map((p) => ('official:${p.id}',p)),
    if (scope != Scope.official) ...repo!.personal.ricePlans.where((p) => !{'official:community','official:jml'}.contains(riceStoreKey(p, storeChoices))).map((p) => ('personal:${p.id}',p)),
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
  Widget scopePicker() => DropdownButtonFormField<Scope>(key: ValueKey(scope), initialValue: scope, isExpanded: true,
    decoration: InputDecoration(labelText: tr(context, '使用哪个菜单库')),
    items: const [DropdownMenuItem(value: Scope.merged, child: LText('官方库 + 个人库', overflow: TextOverflow.ellipsis)),
      DropdownMenuItem(value: Scope.official, child: LText('仅官方库')),
      DropdownMenuItem(value: Scope.personal, child: LText('仅个人库'))],
    onChanged: (v) => setState(() { scope = v!; mealStore=null; catalogStore=null; standaloneSide=null; sideStore=null; mealFilter=null; filterRevision++; selectedStore=null; snack=null; selection=[null,null,null]; message = '范围已改变；重新生成时会检查锁定项。'; }));
  Widget staplePicker() => Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, children: [
    for (final item in {'all': '全部主食', ...stapleNames}.entries) ChoiceChip(
      label: LText(item.value), selected: stapleFilter == item.key, onSelected: (_) => setState(() {
        stapleFilter=item.key; selection=[null,null,null]; snack=null; filterRevision++;
      })),
  ]));
  Future<void> editFilters({required bool browsing}) async {
    final allStores = <String,String>{
      for (final p in repo!.activeOfficial.places) 'official:${p.id}': p.name,
      for (final p in repo!.personal.places) 'personal:${p.id}': p.name,
    };
    final riceOnly = !browsing && mealCategory == 'rice';
    if (riceOnly) {
      final eligibleStores = {
        for (final p in repo!.activeOfficial.ricePlans)
          if (riceStoreKey(p, allStores) == 'official:sf') riceStoreKey(p, allStores),
        for (final p in repo!.personal.ricePlans)
          if (!{'official:community', 'official:jml'}.contains(riceStoreKey(p, allStores))) riceStoreKey(p, allStores),
      };
      allStores.removeWhere((key, value) => !eligibleStores.contains(key));
    }
    final result = await showBrowseFilters(context, scope: scope, staple: stapleFilter,
      store: browsing ? catalogStore : mealStore, stores: allStores, advanced: !browsing && !riceOnly, riceOnly: riceOnly);
    if (result == null || !mounted) return;
    setState(() {
      final sourceChanged = scope != result.scope;
      scope = result.scope; stapleFilter = result.staple;
      if (result.clearMeals) mealFilter = null;
      if (browsing) { catalogStore = result.store; } else { mealStore = result.store; }
      if (sourceChanged) {
        mealFilter = null; sideStore = null; standaloneSide = null; selectedStore = null;
        if (browsing) { mealStore = null; } else { catalogStore = null; }
      }
      selection = [null,null,null]; snack = null; filterRevision++;
      if (mealCategory == 'rice' && !ricePlans.any((p) => mealStore == null || riceStoreKey(p.$2, storeChoices) == mealStore)) {
        mealCategory = 'main'; mainMode = 'main';
      }
    });
    if (result.advanced && mounted) await filterMeals();
  }
  Widget filterSummary({required bool browsing}) {
    final store = browsing ? catalogStore : mealStore;
    final source = scope == Scope.merged ? '全部菜单' : scope == Scope.official ? '仅官方库' : '仅个人库';
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: LText(browsing ? '按条件查找' : '按你的想法挑', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton.icon(key: ValueKey(browsing ? 'catalog-filters' : 'meal-filters'),
            onPressed: () => editFilters(browsing: browsing), icon: const Icon(Icons.tune, size: 17), label: const LText('筛选'))]),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final text in [storeChoices[store] ?? '全部店铺', if (browsing || mealCategory != 'rice') stapleNames[stapleFilter] ?? '全部主食', source,
            if (!browsing && mealFilter != null) '已勾选主餐：${mealFilter!.length}'])
            Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
              label: LText(text, style: const TextStyle(fontSize: 12)),
              onPressed: () => editFilters(browsing: browsing))),
        ])),
      ]));
  }
  Widget decide() {
    final chosen=mealCategory == 'side' ? standaloneSide : selection[0];
    final riceMode = mealCategory == 'rice' || (mealCategory == 'side' && mainMode == 'rice');
    final attachedSide = mealCategory == 'side' && mainMode == 'main' && selection[0] != null;
    final plans = ricePlans.where((p) => (mealStore == null || riceStoreKey(p.$2, storeChoices) == mealStore) && matchesMealFilter(mealFilter, 'rice:${p.$1}')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('今天，吃什么？', '先选主菜，再搭配同店小食。'),
      Padding(padding:const EdgeInsets.only(bottom:12),child:Text('当前：${periodNames[currentPeriod]} · ${mealChoice=="auto"?"跟随系统时间":"手动模式"}')),
      Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: TextField(controller: budget, onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xff914f35)),
          decoration: InputDecoration(labelText: tr(context, '本顿预算'), prefixText: '¥ ', border: InputBorder.none,
            enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.zero))),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [
        for (final item in [('main','整份餐品'), if (plans.isNotEmpty) ('rice','米饭选菜'),('side','小食')])
          ChoiceChip(key: ValueKey('meal-category-${item.$1}'), label: LText(item.$2), selected: mealCategory == item.$1,
            onSelected: (_) => setState(() {
              if (item.$1 != 'side' && mainMode != item.$1) {
                mainMode=item.$1; snack=null; selection=[null,null,null]; filterRevision++;
              }
              mealCategory=item.$1; message=item.$1 == 'side' && selection[0] == null && mainMode != 'rice' ? '可在所选店铺内随机或手选小食。' : '主菜确定后，小食仅从同店选择。';
            })),
      ])),
      const SizedBox(height: 12),
      if (mealCategory != 'side') filterSummary(browsing: false),
      if (mealCategory == 'side') ...[
        if (riceMode || attachedSide)
          TextButton(onPressed: () => setState(() { mainMode='side'; message='可在所选店铺内随机或手选小食。'; snack=null; selection=[null,null,null]; standaloneSide=null; filterRevision++; }),
            child: const LText('只买小食（结束当前搭配）'))
        else ...[
          const SizedBox(height: 8),
          const LText('单独买小食', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const LText('先选店铺，再挑一份喜欢的小食。', style: TextStyle(fontSize: 12, color: Color(0xff777972))),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(key: ValueKey('side-store-$sideStore'), initialValue: sideStore ?? '',
            isExpanded: true, decoration: const InputDecoration(labelText: '小食店铺'),
            items: [const DropdownMenuItem(value: '', child: LText('全部店铺')),
              for (final store in storeChoices.entries) DropdownMenuItem(value: store.key, child: Text(store.value))],
            onChanged: (v) => setState(() { sideStore=v == '' ? null : v; standaloneSide=null; })),
          const SizedBox(height: 20),
        ],
      ],
      if (riceMode) RicePanel(key: ValueKey('rice-filter-$filterRevision'), stores: storeChoices,
        plans: plans, budget: parseMoney(budget.text), savePersonal: saveRice, snacks: pool,
        preferences: favorites, onFavorite: favoriteRice, snacksOnly: mealCategory == 'side')
      else if (attachedSide) ...[
        LText('当前主菜：${selection[0]!.offer.name} · ${selection[0]!.place.name}'),
        wholeSnackPanel(selection[0]!), favoriteButton(selection[0]!),
      ]
      else ...[
        if (chosen != null && (chosen.offer.priceCents + (snack?.offer.priceCents ?? 0)) > (parseMoney(budget.text) ?? 0))
          const LText('当前选择超出新预算，请重新选择。',style: TextStyle(color: Colors.red)),
        FilledButton.icon(onPressed: draw,icon: const Icon(Icons.shuffle), label: LText(mealCategory == 'side' ? '随机小食' : '随机一份')),
        TextButton(onPressed: chooseWhole, child: LText(mealCategory == 'side' ? '自己选小食' : '自己选一份')),
        LText(message,key: const Key('status')),
        if (chosen != null) Card(child: InkWell(onTap: () => detail(chosen),
          borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (chosen.offer.photo.isNotEmpty || dishAssetForEntry(chosen).isNotEmpty) ...[
              DishPhoto(asset: dishAssetForEntry(chosen), data: chosen.offer.photo, large: true), const SizedBox(height: 12)],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: LText(chosen.offer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12), LText('¥${money(chosen.offer.priceCents)}', style: const TextStyle(color: Color(0xff914f35), fontWeight: FontWeight.w600)),
            ]), const SizedBox(height: 6),
            LText('${chosen.place.name} ${chosen.offer.window}', style: const TextStyle(fontSize: 12, color: Color(0xff777972))),
          ])))),

        if (mealCategory == 'main' && chosen != null) wholeSnackPanel(chosen),
        if (chosen != null) favoriteButton(chosen),
      ],
      const SizedBox(height: 12), const LText('基础数据来自10月15日；社区食堂更新于10月16日。预算不含打包、配送费用。', style: TextStyle(fontSize: 11, color: Color(0xff777972))),
    ]);
  }
  Widget wholeSnackPanel(Entry main) => SnackPanel(placeKey: main.placeKey, pool: pool,
    budget: parseMoney(budget.text), mainPrice: main.offer.priceCents, selected: snack,
    weight: (e) => favorites!.score([main.key, e.key]), onChanged: (v) => setState(() => snack=v));
  Future<void> favoriteAction(Future<void> Function() action, String success) async {
    if (busy) return;
    setState(() => busy=true);
    try { await action(); if (mounted) { setState(() {}); notify(success); } }
    catch (e) { notify('保存失败：$e'); }
    finally { if (mounted) setState(() => busy=false); }
  }
  Widget favoriteButton(Entry main) => OutlinedButton.icon(icon: const Icon(Icons.favorite_border),
    label: const LText('满意，收藏这一顿'), onPressed: () => favoriteAction(() => favorites!.save(FavoriteMeal(
      storeKey: main.placeKey, storeName: main.place.name, kind: main.offer.kind == 'side' ? '小食' : '整份餐品',
      savedAt: DateTime.now().toIso8601String(), items: [FavoriteItem.entry(main),
        if (main.offer.kind != 'side' && snack?.placeKey == main.placeKey) FavoriteItem.entry(snack!)],
    )), '已收藏到“我的喜爱”；重复收藏不会叠加权重。'));
  Future<void> favoriteRice(RicePlan p, List<String> names, Entry? side) => favoriteAction(() {
    final store = riceStoreKey(p, storeChoices);
    if (store == null || (side != null && side.placeKey != store)) throw StateError('主菜与小食必须属于同一家店');
    return favorites!.save(FavoriteMeal(storeKey: store, storeName: storeChoices[store]!, kind: '米饭选菜',
      savedAt: DateTime.now().toIso8601String(), ricePrice: p.priceCents, baseLabel: p.pricedByDish ? '米饭' : '套餐（含米饭）',
      items: [for (final name in names) FavoriteItem(riceDishKey(p, name), name,
        p.pricedByDish ? p.dishPrices[name]! : 0, asset: p.dishPhotos[name] ?? ''),
        if (side != null) FavoriteItem.entry(side)]));
  }, '已收藏到“我的喜爱”；重复收藏不会叠加权重。');
  Widget favoritePage() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    title('我的喜爱', '保存满意的一顿，随时回看。价格为收藏时记录。'),
    SwitchListTile(key: const Key('preference-learning'), title: const LText('根据喜爱调整推荐'),
      subtitle: const LText('仅在本机学习。关闭后等概率随机，收藏仍保留。'), value: favorites!.enabled,
      onChanged: (v) => favoriteAction(() => favorites!.setEnabled(v), v ? '已开启偏好加权' : '已恢复等概率随机')),
    if (favorites!.meals.isEmpty) const Padding(padding: EdgeInsets.all(20), child: LText('还没有喜爱记录。选好后点击“满意，收藏这一顿”。')),
    for (final meal in favorites!.meals) Card(key: ValueKey('favorite:${meal.id}'), child: Padding(
      padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(contentPadding: EdgeInsets.zero, title: Text('${meal.storeName} · ${meal.kind}'),
          subtitle: Text(meal.savedAt.replaceFirst('T', ' ').split('.').first),
          trailing: IconButton(tooltip: '删除喜爱记录', icon: const Icon(Icons.delete_outline),
            onPressed: () => favoriteAction(() => favorites!.remove(meal.id), '已删除，也已撤销这条记录的加权影响'))),
        for (final item in meal.items) ListTile(leading: DishPhoto(asset: item.asset, data: item.photo), title: Text(item.name),
          trailing: item.price > 0 ? Text('¥${money(item.price)}') : null),
        if (meal.ricePrice > 0) Text('${meal.baseLabel} ¥${money(meal.ricePrice)}'),
        Text('收藏时合计 ¥${money(meal.total)}'),
      ]))),
  ]);
  void detail(Entry e) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: LText(e.offer.name),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo, large: true), const SizedBox(height: 16),
        LText('${e.place.name} · ${e.place.area}\n${e.offer.portion} · ¥${money(e.offer.priceCents)}\n价格记录：${e.offer.updatedAt}\n${e.offer.available ? '库内标记：在售（非实时）' : '已下架'}'),
        const SizedBox(height: 12), LText('${kindNames[e.offer.kind]} · ${e.offer.window}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}\n${e.offer.notes}\n来源：${e.offer.evidence}\n拍摄日期：${e.offer.observedAt.isEmpty ? '截图未显示' : e.offer.observedAt}'),
        if (e.offer.example) const LText('这是示例数据，不是真实菜单。'),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('关闭'))]));
  }
  bool matchesCategory(Entry e) => (browseCategory == 'all' ||
    e.offer.kind == browseCategory && (browseCategory != 'side' || !e.offer.addonOnly)) &&
    (stapleFilter == 'all' || e.offer.stapleType == stapleFilter);
  Widget categoryFilter() => Padding(padding: const EdgeInsets.only(bottom: 12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [
    for (final item in const [('all','全部'),('main','整份餐品'),('side','小食'),('drink','饮品'),('dish','单点菜'),('fee','费用')])
      Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(
        color: browseCategory == item.$1 ? const Color(0xff914f35) : Colors.transparent, width: 2))),
        child: TextButton(onPressed: () => setState(() => browseCategory=item.$1),
          style: TextButton.styleFrom(foregroundColor: browseCategory == item.$1 ? const Color(0xff914f35) : const Color(0xff777972)),
          child: LText(item.$2, style: TextStyle(fontWeight: browseCategory == item.$1 ? FontWeight.w700 : FontWeight.w400)))),
  ])));
  Widget shopPhoto(String storeKey, {bool thumbnail = false}) {
    final source = storeKey.startsWith('official:') ? repo!.official : repo!.personal;
    final place = source.places.where((p) => '${source.source.name}:${p.id}' == storeKey).firstOrNull;
    if (place != null && place.photo.isNotEmpty) return DishPhoto(data: place.photo, large: !thumbnail);
    if (!['official:sf','official:community','official:jml','official:btk','official:btz','official:zxb'].contains(storeKey)) return SizedBox(width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200, child: const ColoredBox(color: Color(0xffeee7df), child: Icon(Icons.storefront)));
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(
      storeKey == 'official:fw' ? 'assets/stores/fengwei.jpg' : storeKey == 'official:zxb' ? 'assets/stores/zhongxiaobei.jpg' : storeKey == 'official:btz' ? 'assets/stores/baite-chinese.jpg' : storeKey == 'official:btk' ? 'assets/stores/baite.jpg' : storeKey == 'official:wy' ? 'assets/stores/wenying.jpg' : storeKey == 'official:sy' ? 'assets/stores/shiyue.jpg' : storeKey == 'official:sf' ? 'assets/stores/shiweifang.webp' : storeKey == 'official:jml' ? 'assets/stores/jinmianlang.png' : 'assets/stores/community.webp', key: ValueKey('${storeKey.split(':').last}-${thumbnail ? 'thumbnail' : 'cover'}'),
      width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200,
      cacheWidth: thumbnail ? 180 : 1280, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: '${place?.name ?? '店铺'}店铺实景',
      errorBuilder: (_, error, stackTrace) => const SizedBox(height: 56, child: Icon(Icons.storefront)),
    ));
  }
  List<(RicePlan, String)> riceCatalog({String? store}) => [
    if ((browseCategory == 'all' || browseCategory == 'dish') &&
        (stapleFilter == 'all' || stapleFilter == 'rice'))
      for (final item in allRicePlans)
        if (item.$2.pricedByDish && (store == null || item.$2.storeKey == store))
          for (final name in item.$2.options.expand((v) => v).toSet())
            if (query.isEmpty || name.contains(query) || item.$2.location.contains(query)) (item.$2, name),
  ];
  Widget riceDishTile((RicePlan, String) item) {
    final (p, name) = item;
    return Card(key: ValueKey('rice-dish:${p.storeKey}:${p.id}:$name'), child: ListTile(leading: DishPhoto(asset: p.dishPhotos[name] ?? ''),
      title: LText(name), subtitle: LText('${p.location} · 米饭另计 ¥${money(p.priceCents)}'),
      trailing: Text('¥${money(p.dishPrices[name]!)}'), onTap: () => showDialog<void>(
        context: context, builder: (ctx) => AlertDialog(title: LText(name),
          content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DishPhoto(asset: p.dishPhotos[name] ?? '', large: true), const SizedBox(height: 12),
            LText('${p.location} · ¥${money(p.dishPrices[name]!)}\n米饭 ¥${money(p.priceCents)}${p.riceRefill ? '，免费续饭' : ''}'),
          ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('关闭'))]))));
  }
  Widget catalog() {
    final riceItems = riceCatalog(store: catalogStore);
    final visible = allPool.where((e) => (catalogStore == null || e.placeKey == catalogStore) && matchesCategory(e) && (query.isEmpty || e.offer.name.contains(query) || e.place.name.contains(query) || e.offer.window.contains(query))).toList();
    return CustomScrollView(key: const PageStorageKey('catalog-scroll'), slivers: [
      SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('餐品菜单', '按店铺、窗口或菜名查找，点击查看售价和购买说明。'),
      TextFormField(key: ValueKey('search-$query'), initialValue: query,
        decoration: InputDecoration(labelText: tr(context, '搜索菜名、店铺、窗口'), prefixIcon: Icon(Icons.search)),
        onFieldSubmitted: (v) => setState(() => query = v.trim())),
      const SizedBox(height: 8), if (query.isNotEmpty) TextButton(onPressed: () => setState(() => query = ''), child: const LText('清除搜索')),
      const SizedBox(height: 12), categoryFilter(), filterSummary(browsing: true),
      LText('${visible.length + riceItems.length} 个售卖项', style: const TextStyle(fontSize: 12, color: Color(0xff777972))),
      ])),
      SliverList.builder(itemCount: visible.length, itemBuilder: (context, index) {
        final e = visible[index];
        return Card(key: ValueKey(e.key), child: ListTile(leading: DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo), onTap: () => detail(e), title: LText(e.offer.name),
        subtitle: LText('${e.place.name} ${e.offer.window} · ${e.offer.mealPeriods.map((p)=>periodNames[p]).join("/")} · ${kindNames[e.offer.kind]}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}\n${e.db.source == Source.official ? '官方库' : '个人库'}${e.offer.example ? ' · 示例' : ''}${e.offer.available ? '' : ' · 已下架'}'),
        trailing: LText('¥${money(e.offer.priceCents)}')));
      }),
      SliverList.builder(itemCount: riceItems.length, itemBuilder: (context, index) => riceDishTile(riceItems[index])),
      if (visible.isEmpty && riceItems.isEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: LText('暂无符合条件的菜品。可在“菜单库”录入个人菜单。'))),
    ]);
  }
  Widget stores() {
    final shops = <(String, Place, MenuDb)>[
      if (scope != Scope.personal) ...repo!.activeOfficial.places.map((p) => ('official:${p.id}', p, repo!.activeOfficial)),
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
        FilledButton.icon(onPressed: addStore, icon: const Icon(Icons.add_business), label: const LText('添加个人店铺')),
        LText('${shops.length} 家店铺'),
        for (final shop in shops) Card(child: ListTile(
          key: ValueKey('store-${shop.$1}'), leading: shopPhoto(shop.$1, thumbnail: true),
          title: LText(shop.$2.name), subtitle: LText('${shop.$2.area}\n${shop.$3.source == Source.official ? '官方库' : '个人库'} · ${shop.$3.offers.where((o) => o.placeId == shop.$2.id).length} 个售卖项'),
          trailing: const Icon(Icons.chevron_right), onTap: () => setState(() { selectedStore=shop.$1; query=''; browseCategory='all'; stapleFilter='all'; }))),
        if (shops.isEmpty) const LText('当前菜单库还没有店铺，可在菜单库中添加个人餐品。'),
      ] else ...[
        TextButton.icon(onPressed: () => setState(() => selectedStore=null), icon: const Icon(Icons.arrow_back), label: const LText('返回全部店铺')),
        shopPhoto(selected.$1),
        if (selected.$3.source == Source.personal) TextButton.icon(onPressed: () => editOffer(null, selected.$2), icon: const Icon(Icons.add), label: const LText('给这家店添加菜品')),
        const SizedBox(height: 12), categoryFilter(), staplePicker(),
        LText('${dishes.length + riceCatalog(store: selected.$1).length} 个售卖项'),
        for (final e in dishes) Card(child: ListTile(leading: DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo), onTap: () => detail(e), title: LText(e.offer.name),
          subtitle: LText('${e.offer.window} · ${kindNames[e.offer.kind]}${e.offer.channel == 'douyin' ? ' · 抖音团购' : ''}${e.offer.available ? '' : ' · 暂不可选'}'),
          trailing: LText('¥${money(e.offer.priceCents)}'))),
        for (final item in riceCatalog(store: selected.$1)) riceDishTile(item),
        if (dishes.isEmpty && riceCatalog(store: selected.$1).isEmpty) const LText('这家店暂未录入菜品。'),
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
  Future<void> editOffer([Offer? old, Place? preselected]) async {
    final db = repo!.personal;
    final place = old == null ? preselected : db.places.firstWhere((p) => p.id == old.placeId);
    final name = TextEditingController(text: old?.name ?? '');
    final shop = TextEditingController(text: place?.name ?? '');
    final area = TextEditingController(text: place?.area ?? '中北大学周边');
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final portion = TextEditingController(text: old?.portion ?? '1 份');
    final window = TextEditingController(text: old?.window ?? '');
    final notes = TextEditingController(text: old?.notes ?? '');
    String photo = old?.photo ?? '';
    bool picking = false;
    String staple = old?.stapleType ?? 'rice';
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
        DropdownButtonFormField<String>(initialValue: staple, decoration: InputDecoration(labelText: tr(context, '主食分类')),
          items: stapleNames.entries.map((e) => DropdownMenuItem(value: e.key, child: LText(e.value))).toList(),
          onChanged: (v) => refresh(() => staple=v!)),
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
      final offer = Offer(mealPeriods:old?.mealPeriods ?? const {'breakfast','lunch','dinner'}, id: old?.id ?? 'o$stamp', placeId: chosenPlace.id, name: name.text.trim(),
        portion: portion.text.trim(), priceCents: parseMoney(price.text)!, roles: old?.roles ?? {}, foodIds: old?.foodIds ?? {},
        updatedAt: DateTime.now().toIso8601String(), ingredientsKnown: old?.ingredientsKnown ?? false, available: available,
        example: old?.example ?? false, staple: kind == 'main' ? staple : 'none', kind: kind, channel: channel, window: window.text.trim(),
        photo: photo, notes: notes.text.trim(), addonOnly: addon, alcohol: alcohol,
        evidence: old?.evidence ?? '个人录入', observedAt: old?.observedAt ?? '');
      await save(MenuDb(source: Source.personal, revision: db.revision + 1, places: places, foods: foods,
        ricePlans: db.ricePlans, offers: [...db.offers.where((o) => o.id != old?.id), offer]));
    }
    Future<void>.delayed(const Duration(seconds: 1), () { for (final c in [name, shop, area, price, portion, window, notes]) { c.dispose(); } });
  }
  Future<void> manageOfficial() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OfficialLibraryPage(repository: repo!)));
    if (mounted) setState(() { selection=[null,null,null]; snack=null; standaloneSide=null; sideStore=null; selectedStore=null; mealFilter=null; filterRevision++; });
  }
  Future<void> addStore() async {
    final name=TextEditingController(), area=TextEditingController();
    String photo='', error=''; bool picking=false;
    final accepted=await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => Scaffold(
      appBar: AppBar(title: const LText('添加个人店铺')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        DishPhoto(data: photo, large: true),
        TextButton(onPressed: picking ? null : () async {
          refresh(() => picking=true);
          try { final result=await pickDishPhoto(); if (ctx.mounted && result != null) refresh(() => photo=result); }
          catch (e) { if (ctx.mounted) refresh(() => error=e.toString()); }
          finally { if (ctx.mounted) refresh(() => picking=false); }
        }, child: const LText('添加照片')),
        const SizedBox(height: 20), TextField(controller: name, decoration: InputDecoration(labelText: tr(context,'店铺名称'))),
        const SizedBox(height: 20), TextField(controller: area, decoration: InputDecoration(labelText: tr(context,'位置 / 区域'))),
        const SizedBox(height: 20), LText(error),
        FilledButton(onPressed: picking ? null : () {
          if (name.text.trim().isEmpty) { refresh(() => error='请填写店铺名称'); return; }
          Navigator.pop(ctx,true);
        }, child: const LText('保存')),
      ])))));
    if (accepted == true && mounted) {
      final db=repo!.personal;
      if (db.places.any((p) => p.name == name.text.trim() && p.area == area.text.trim())) {
        notify('同名同位置的店铺已存在');
      } else {
        final place=Place('p${DateTime.now().microsecondsSinceEpoch}',name.text.trim(),area.text.trim(),photo:photo);
        final ok=await save(MenuDb(source: db.source,revision: db.revision+1,places:[...db.places,place],foods:db.foods,offers:db.offers,ricePlans:db.ricePlans));
        if (ok && mounted) setState(() { scope=Scope.merged;tab=2;selectedStore='personal:${place.id}';stapleFilter='all';browseCategory='all'; });
      }
    }
    Future<void>.delayed(const Duration(seconds:1), () { name.dispose();area.dispose(); });
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
    OutlinedButton.icon(onPressed: manageOfficial, icon: const Icon(Icons.download), label: const LText('管理官方店铺')),
    title('你的菜单，你做主', '官方库和个人库独立保存，可单独使用，也可合并推荐。'),
    for (final db in [repo!.official, repo!.personal]) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LText(db.source == Source.official ? '官方菜单库' : '我的个人库', style: Theme.of(context).textTheme.titleLarge),
      LText('版本 ${db.revision} · ${db.places.length} 家店 · ${db.offers.length} 个售卖项'),
      const SizedBox(height: 10), LText(db.source == Source.official ? '内置照片菜单；可导入团队维护的更高版本数据包。' : '仅存于本机，支持录入、修改、下架及备份迁移。'),
      Wrap(spacing: 8, children: [TextButton(onPressed: busy ? null : () => transfer(db.source, false), child: const LText('导出备份')),
        TextButton(onPressed: busy ? null : () => transfer(db.source, true), child: LText(db.source == Source.official ? '导入更新' : '导入个人库'))]),
    ]))),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: busy ? null : addStore, icon: const Icon(Icons.add_business), label: const LText('添加个人店铺')),
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
    final page = tab == 1
      ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 914),
          child: Padding(padding: EdgeInsets.all(wide ? 32 : 16), child: catalog())))
      : SingleChildScrollView(key: ValueKey(tab), padding: EdgeInsets.all(wide ? 32 : 16),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: [decide, catalog, stores, libraries, favoritePage][tab]())));
    return Scaffold(appBar: AppBar(actions: [IconButton(tooltip: tr(context,'设置'), onPressed: () => openSettings(context, onMealSettings:(ctx)=>configureMeal(dialogContext:ctx)), icon: const Icon(Icons.settings_outlined))], title: Row(children: [Image.asset('assets/icon.png', width: 36, height: 36), const SizedBox(width: 10), const LText('吃了么'), const SizedBox(width: 12), const Flexible(child: LText('中北大学', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14)))])),
      body: AbsorbPointer(absorbing: busy, child: Row(children: [if (wide) NavigationRail(
        selectedIndex: navigationOrder.indexOf(tab), labelType: NavigationRailLabelType.all,
        onDestinationSelected: (i) => setState(() => tab = navigationOrder[i]), destinations: [
          for (final id in navigationOrder)
            NavigationRailDestination(icon: Icon(navigationIcons[id]), label: LText(navigationLabels[id])),
        ]), Expanded(child: page)])),
      bottomNavigationBar: wide ? null : SortableNavigationBar(
        order: navigationOrder, selected: tab, enabled: !busy && !savingNavigation,
        onSelected: (id) => setState(() => tab = id), onReorder: reorderNavigation),
    );
  }
}
