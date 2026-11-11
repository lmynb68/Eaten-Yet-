import 'dart:math';
import 'dart:async';
import 'meal_period.dart';
import 'package:flutter/material.dart';
import 'backup_dialog.dart';
import 'backup_import.dart';
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
import 'history.dart';
import 'history_page.dart';
import 'quantity.dart';
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
  HistoryStore? history;
  int quantity=1, snackQuantity=1;
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
    try { final r = await MenuRepository.load(); final f = await FavoriteStore.loadAvailable(r.preferences); final h = await HistoryStore.load(r.preferences); if (mounted) setState(() { history=h; favorites = f; repo = r; mealChoice=readMealChoice(r.preferences); currentPeriod=mealChoice=="auto"?clockPeriod(DateTime.now(),readMealSchedule(r.preferences)):mealChoice; navigationOrder = readNavigationOrder(r.preferences); loadError = null; });
      if(mounted) scheduleMealClock();
      if(mounted && !hasMealChoice(r.preferences) && !mealPromptOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted) configureMeal(first:true);});
      }
    }
    catch (e) { if (mounted) setState(() => loadError = '菜单暂时打不开，本机数据已保留。请重试。'); }
  }
  Future<void> exportRecovery() async {
    try {
      final text = await MenuRepository.exportRecoveryData();
      if (!mounted) return;
      await showBackupExportDialog(context, text: text,
          name: 'eaten-yet-recovery.json', diagnostic: true);
    } catch (_) {
      if (mounted) setState(() => loadError = '原数据暂时读不出来，请稍后重试。');
    }
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
    quantity=1; snackQuantity=1; selection=[null,null,null]; snack=null; standaloneSide=null; mealStore=null; sideStore=null;
    mealFilter=null; mealCategory='main'; mainMode='main'; filterRevision++;
    message='用餐时间已切换，请重新选择餐品。';
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
      message = '菜单已更新，请重新选一次。';
    }); return true; }
    catch (e) { notify(friendlySaveError(e)); return false; }
    finally { if (mounted) setState(() => busy = false); }
  }
  List<Entry> get wholeMeals => pool.where((e) => (mealCategory != 'main' || mealStore == null || e.placeKey == mealStore) && (mealCategory != 'side' || sideStore == null || e.placeKey == sideStore) && (mealCategory != 'main' || matchesMealFilter(mealFilter, e.key)) && e.offer.kind == mealCategory && (mealCategory != 'main' || stapleFilter == 'all' || e.offer.stapleType == stapleFilter) && !e.offer.addonOnly && e.offer.available &&
    !e.offer.alcohol && e.offer.channel == 'regular').toList();
  void draw() {
    final cents = parseMoney(budget.text);
    if (cents == null || cents <= 0) { setState(() => message = '请输入有效预算'); return; }
    final candidates = wholeMeals.where((e) => mealCostWithSnack(e, mealCategory == 'side' ? null : snack, snackQuantity: snackQuantity) <= cents && e.key != (mealCategory == 'side' ? standaloneSide : selection[0])?.key).toList();
    setState(() {
      if (candidates.isEmpty) { message = '预算内没有新的可选餐品；原选择保留。'; return; }
      quantity=1;
      final picked = weightedPick(candidates, random, (e) => favorites!.score([e.key, if (snack?.placeKey == e.placeKey) snack!.key]));
      if (snack?.placeKey != picked.placeKey) snack = null;
      if (mealCategory == 'side') { standaloneSide = picked; } else { selection = [picked, null, null]; }
      message = '已为你选好一份。';
    });
  }
  Future<void> chooseWhole() async {
    final cents = parseMoney(budget.text);
    if (cents == null || cents <= 0) { setState(() => message='请输入有效预算'); return; }
    final choices = wholeMeals.where((e) => mealCostWithSnack(e, mealCategory == 'side' ? null : snack, snackQuantity: snackQuantity) <= cents).toList();
    final chosen = await showDialog<Entry>(context: context, builder: (ctx) => AlertDialog(
      title: const LText('预算内手选一份'), content: SizedBox(width: 520, height: 420,
        child: choices.isEmpty ? const LText('预算内没有餐品') : ListView.builder(itemCount: choices.length,
          itemBuilder: (ctx,i) => ListTile(leading: DishPhoto(asset: dishAssetForEntry(choices[i]), data: choices[i].offer.photo), title: Text(choices[i].offer.name),
            subtitle: LText('${choices[i].place.name} ${choices[i].offer.window} · ¥${money(choices[i].offer.priceCents)}'),
            onTap: () => Navigator.pop(ctx,choices[i])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消'))]));
    if (chosen != null && mounted && chosen.offer.mealPeriods.contains(currentPeriod)) setState(() { quantity=1; if (snack?.placeKey != chosen.placeKey) snack=null; if (mealCategory == 'side') { standaloneSide=chosen; } else { selection=[chosen,null,null]; } message=mealCategory == 'side' ? '已手选小食。' : '已手选整份餐品。'; });
  }
  Map<String,String> get storeChoices => {
    if (scope != Scope.personal) for (final p in repo!.activeOfficial.places) 'official:${p.id}': p.name,
    if (scope != Scope.official) for (final p in repo!.personal.places) 'personal:${p.id}': p.name,
  };
  // A personal plan can still refer to a shop from the official menu.
  // Menu scope selects plans, not the shops and snacks those plans refer to.
  Map<String,String> get riceStores => {
    for (final p in repo!.activeOfficial.places) 'official:${p.id}': p.name,
    for (final p in repo!.personal.places) 'personal:${p.id}': p.name,
  };
  List<Entry> get riceSnacks => entries(repo!.activeOfficial, repo!.personal, Scope.merged)
    .where((e) => e.offer.mealPeriods.contains(currentPeriod)).toList();
  List<(String, RicePlan)> get ricePlans => allRicePlans.where((p)=>currentPeriod!='breakfast' || p.$1.startsWith('personal:')).toList();
  List<(String, RicePlan)> get allRicePlans => [
    if (scope != Scope.personal) ...repo!.activeOfficial.ricePlans.where((p) => riceStoreKey(p, riceStores) == 'official:sf').map((p) => ('official:${p.id}',p)),
    if (scope != Scope.official) ...repo!.personal.ricePlans.where((p) => !{'official:community','official:jml'}.contains(riceStoreKey(p, riceStores))).map((p) => ('personal:${p.id}',p)),
  ];
  Future<void> filterMeals() async {
    final targets = <MealTarget>[
      for (final e in pool.where((e) => e.offer.kind == 'main' && e.offer.available && e.offer.channel == 'regular'))
        MealTarget(e.key, e.placeKey, e.place.name, e.offer.name),
      for (final p in ricePlans)
        MealTarget('rice:${p.$1}', riceStoreKey(p.$2, riceStores) ?? 'unknown:${p.$1}',
          riceStores[riceStoreKey(p.$2, riceStores)] ?? p.$2.location, p.$2.name),
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
  Widget title(String heading, String detail, {bool translate = true}) => Padding(padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(translate ? tr(context, heading) : heading, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6), Text(translate ? tr(context, detail) : detail, style: const TextStyle(color: Color(0xff70665c))),
    ]));
  Widget scopePicker() => DropdownButtonFormField<Scope>(key: ValueKey(scope), initialValue: scope, isExpanded: true,
    decoration: InputDecoration(labelText: tr(context, '菜单范围')),
    items: const [DropdownMenuItem(value: Scope.merged, child: LText('全部菜单', overflow: TextOverflow.ellipsis)),
      DropdownMenuItem(value: Scope.official, child: LText('官方菜单')),
      DropdownMenuItem(value: Scope.personal, child: LText('我的菜单'))],
    onChanged: (v) => setState(() { scope = v!; mealStore=null; catalogStore=null; standaloneSide=null; sideStore=null; mealFilter=null; filterRevision++; selectedStore=null; snack=null; selection=[null,null,null]; message = '已切换菜单范围。'; }));
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
      if (mealCategory == 'rice' && !ricePlans.any((p) => mealStore == null || riceStoreKey(p.$2, riceStores) == mealStore)) {
        mealCategory = 'main'; mainMode = 'main';
      }
    });
    if (result.advanced && mounted) await filterMeals();
  }
  Widget filterSummary({required bool browsing}) {
    final store = browsing ? catalogStore : mealStore;
    final source = scope == Scope.merged ? '全部菜单' : scope == Scope.official ? '官方菜单' : '我的菜单';
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: LText(browsing ? '按条件查找' : '按你的想法挑', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton.icon(key: ValueKey(browsing ? 'catalog-filters' : 'meal-filters'),
            onPressed: () => editFilters(browsing: browsing), icon: const Icon(Icons.tune, size: 17), label: const LText('筛选'))]),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final text in [(browsing || mealCategory != 'rice' ? storeChoices : riceStores)[store] ?? tr(context, '全部店铺'), if (browsing || mealCategory != 'rice') tr(context, stapleNames[stapleFilter] ?? '全部主食'), tr(context, source),
            if (!browsing && mealFilter != null) tr(context, '已勾选主餐：{count}', params: {'count': mealFilter!.length})])
            Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
              label: Text(text, style: const TextStyle(fontSize: 12)),
              onPressed: () => editFilters(browsing: browsing))),
        ])),
      ]));
  }
  Widget decide() {
    final chosen=mealCategory == 'side' ? standaloneSide : selection[0];
    final riceMode = mealCategory == 'rice' || (mealCategory == 'side' && mainMode == 'rice');
    final attachedSide = mealCategory == 'side' && mainMode == 'main' && selection[0] != null;
    final plans = ricePlans.where((p) => (mealStore == null || riceStoreKey(p.$2, riceStores) == mealStore) && matchesMealFilter(mealFilter, 'rice:${p.$1}')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('今天，吃什么？', '先选主菜，再决定要不要加小食。'),
      Padding(padding:const EdgeInsets.only(bottom:12),child:LText('当前：{meal} · {mode}', params: {'meal': tr(context, periodNames[currentPeriod]!), 'mode': tr(context, mealChoice == 'auto' ? '跟随系统时间' : '手动模式')})),
      Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: TextField(controller: budget, onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xff914f35)),
          decoration: InputDecoration(labelText: tr(context, '这一顿的预算'), prefixText: '¥ ', border: InputBorder.none,
            enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.zero))),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [
        for (final item in [('main','整份餐品'), if (plans.isNotEmpty) ('rice','米饭选菜'),('side','小食')])
          ChoiceChip(key: ValueKey('meal-category-${item.$1}'), label: LText(item.$2), selected: mealCategory == item.$1,
            onSelected: (_) => setState(() {
              if (item.$1 != 'side' && mainMode != item.$1) {
                mainMode=item.$1; snack=null; selection=[null,null,null]; filterRevision++;
              }
              mealCategory=item.$1; message=item.$1 == 'side' && selection[0] == null && mainMode != 'rice' ? '挑一份小食。' : '';
            })),
      ])),
      const SizedBox(height: 12),
      if (mealCategory != 'side') filterSummary(browsing: false),
      if (mealCategory == 'side') ...[
        if (riceMode || attachedSide)
          TextButton(onPressed: () => setState(() { mainMode='side'; message='挑一份小食。'; snack=null; selection=[null,null,null]; standaloneSide=null; filterRevision++; }),
            child: const LText('只买小食'))
        else ...[
          const SizedBox(height: 8),
          const LText('单独买小食', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const LText('先选店铺，再挑一份喜欢的小食。', style: TextStyle(fontSize: 12, color: Color(0xff777972))),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(key: ValueKey('side-store-$sideStore'), initialValue: sideStore ?? '',
            isExpanded: true, decoration: InputDecoration(labelText: tr(context, '小食店铺')),
            items: [const DropdownMenuItem(value: '', child: LText('全部店铺')),
              for (final store in storeChoices.entries) DropdownMenuItem(value: store.key, child: Text(store.value))],
            onChanged: (v) => setState(() { sideStore=v == '' ? null : v; standaloneSide=null; })),
          const SizedBox(height: 20),
        ],
      ],
      if (riceMode) RicePanel(key: ValueKey('rice-filter-$filterRevision'), stores: riceStores,
        plans: plans, budget: parseMoney(budget.text), savePersonal: saveRice, snacks: riceSnacks,
        preferences: favorites, onMealFavorite: toggleFavorite, isMealFavorite: isFavorite, onRecord: recordMeal, onFavorite: favoriteRice, favoriteBusy: busy,
        isFavorite: (p, names, side) => isFavorite(riceFavoriteMeal(p, names, side)), snacksOnly: mealCategory == 'side')
      else if (attachedSide) ...[
        LText('当前主菜：{dish} · {store}', params: {'dish': selection[0]!.offer.name, 'store': selection[0]!.place.name}),
        QuantityPicker(value: quantity, onChanged: (n) => setState(() => quantity=n)), wholeSnackPanel(selection[0]!), favoriteButton(selection[0]!),
      ]
      else ...[
        if (chosen != null && mealCostWithSnack(chosen, mealCategory == 'side' ? null : snack, quantity: quantity, snackQuantity: snackQuantity) > (parseMoney(budget.text) ?? 0))
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
              Expanded(child: Text(chosen.offer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12), LText('¥${money(chosen.offer.priceCents)}', style: const TextStyle(color: Color(0xff914f35), fontWeight: FontWeight.w600)),
            ]), const SizedBox(height: 6),
            Text('${chosen.place.name} ${chosen.offer.window}', style: const TextStyle(fontSize: 12, color: Color(0xff777972))),
          ])))),

        if (chosen != null) QuantityPicker(value: quantity, onChanged: (n) => setState(() => quantity=n)),
        if (chosen != null && mealCategory == 'side') Text('${tr(context, "合计")} ¥${money(chosen.offer.priceCents*quantity)}'),
        if (mealCategory == 'main' && chosen != null) wholeSnackPanel(chosen),
        if (chosen != null) favoriteButton(chosen),
      ],
      const SizedBox(height: 12), const LText('价格来自现场记录，可能变动，以店内为准。', style: TextStyle(fontSize: 11, color: Color(0xff777972))),
    ]);
  }
  Widget wholeSnackPanel(Entry main) => SnackPanel(placeKey: main.placeKey, pool: pool,
    budget: parseMoney(budget.text), mainPrice: main.offer.priceCents*quantity, selected: snack, quantity: snackQuantity, onQuantityChanged: (n) => setState(() => snackQuantity=n),
    weight: (e) => favorites!.score([main.key, e.key]), onChanged: (v) => setState(() { snack=v; snackQuantity=1; }));
  Future<void> favoriteAction(Future<void> Function() action, String success) async {
    if (busy) return;
    setState(() => busy=true);
    try { await action(); if (mounted) { setState(() {}); notify(success); } }
    catch (e) { notify(friendlySaveError(e)); }
    finally { if (mounted) setState(() => busy=false); }
  }
  bool isFavorite(FavoriteMeal meal) => favorites!.meals.any((m) => m.id == meal.id);
  Future<void> toggleFavorite(FavoriteMeal meal) {
    final saved = isFavorite(meal);
    return favoriteAction(() => saved ? favorites!.remove(meal.id) : favorites!.save(meal),
      saved ? '已取消收藏' : '已收藏到“我的喜爱”');
  }
  Widget favoriteButton(Entry main) {
    final meal = FavoriteMeal(
      storeKey: main.placeKey, storeName: main.place.name, kind: main.offer.kind == 'side' ? '小食' : '整份餐品',
      savedAt: DateTime.now().toIso8601String(), items: [FavoriteItem.entry(main,quantity: quantity),
        if (main.offer.kind != 'side' && snack?.placeKey == main.placeKey) FavoriteItem.entry(snack!,quantity: snackQuantity)]);
    final saved = isFavorite(meal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[OutlinedButton.icon(key: const Key('meal-favorite'),
      icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
      label: LText(saved ? '已收藏，再点取消' : '满意，收藏这一顿'),
      onPressed: busy ? null : () => toggleFavorite(meal)),
      TextButton.icon(onPressed: busy ? null : () => recordMeal(meal), icon: const Icon(Icons.history), label: const LText('记录这一顿'))]);
  }
  FavoriteMeal riceFavoriteMeal(RicePlan p, List<String> names, Entry? side) {
    final store = riceStoreKey(p, riceStores);
    if (store == null || (side != null && side.placeKey != store)) throw StateError('主菜与小食必须属于同一家店');
    return FavoriteMeal(storeKey: store, storeName: riceStores[store]!, kind: '米饭选菜',
      savedAt: DateTime.now().toIso8601String(), ricePrice: p.priceCents, baseLabel: p.pricedByDish ? '米饭' : '套餐（含米饭）',
      items: [for (final name in names) FavoriteItem(riceDishKey(p, name), name,
        p.pricedByDish ? p.dishPrices[name]! : 0, asset: p.dishPhotos[name] ?? ''),
        if (side != null) FavoriteItem.entry(side)]);
  }
  Future<void> favoriteRice(RicePlan p, List<String> names, Entry? side) =>
    toggleFavorite(riceFavoriteMeal(p, names, side));
  Future<void> recordMeal(FavoriteMeal meal) async {
    if (busy || history == null) return;
    final review = await showMealReview(context,
        onSave: (stars, text) => history!.add(meal, stars: stars, review: text));
    if (review != null && mounted) { setState(() {}); notify('已记录这一顿'); }
  }
  Future<void> resetFavorites() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const LText('收藏读取失败，要清空重来吗？'),
      content: const LText('清空后，这些收藏会从列表移除。请先导出一份备份。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const LText('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const LText('已保存备份，确认重置'))],
    ));
    if (confirmed == true && mounted) {
      await favoriteAction(() => favorites!.resetAfterBackup(), '收藏已清空，原数据已另存一份。');
    }
  }
  Widget favoritePage() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    title('我的喜爱', '保存满意的一顿，随时回看。记录的是收藏时的价格。'),
    TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => HistoryPage(store: history!))), icon: const Icon(Icons.history), label: const LText('用餐历史')),
    if (favorites!.recoveryRequired) ...[
      const LText('收藏读取失败，数据还在。你仍然可以选餐，收藏功能暂时停用。'),
      TextButton(onPressed: exportRecovery, child: const LText('导出备份（排障用）')),
      TextButton(onPressed: load, child: const LText('重新读取')),
      TextButton(onPressed: resetFavorites, child: const LText('备份后重置收藏')),
    ],
    SwitchListTile(key: const Key('preference-learning'), title: const LText('根据喜爱调整推荐'),
      subtitle: const LText('偏好只保存在本机。关闭后随机推荐，收藏不受影响。'), value: favorites!.enabled,
      onChanged: (v) => favoriteAction(() => favorites!.setEnabled(v), v ? '推荐会参考你的收藏' : '已切换为随机推荐')),
    if (!favorites!.recoveryRequired && favorites!.meals.isEmpty) const Padding(padding: EdgeInsets.all(20), child: LText('还没有喜爱记录。选好后点击“满意，收藏这一顿”。')),
    for (final meal in favorites!.meals) Card(key: ValueKey('favorite:${meal.id}'), child: Padding(
      padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(contentPadding: EdgeInsets.zero, title: Text('${meal.storeName} · ${tr(context, meal.kind)}'),
          subtitle: Text(meal.savedAt.replaceFirst('T', ' ').split('.').first),
          trailing: IconButton(tooltip: tr(context, '删除喜爱记录'), icon: const Icon(Icons.delete_outline),
            onPressed: () => favoriteAction(() => favorites!.remove(meal.id), '已取消收藏，推荐不再参考这条。'))),
        for (final item in meal.items) ListTile(leading: DishPhoto(asset: item.asset, data: item.photo), title: Text('${item.name} × ${item.quantity}'),
          trailing: item.price > 0 ? Text('¥${money(item.price*item.quantity)}') : null),
        if (meal.ricePrice > 0) Text('${tr(context, meal.baseLabel)} × ${meal.baseQuantity} ¥${money(meal.ricePrice*meal.baseQuantity)}'),
        LText('收藏时合计 ¥{price}', params: {'price': money(meal.total)}),
      ]))),
  ]);
  Future<void> detail(Entry e) async {
    var count = 1;
    final selected = await showDialog<int>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(title: Text(e.offer.name),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo, large: true), const SizedBox(height: 16),
        Text('${e.place.name} · ${e.place.area}\n${e.offer.portion} · ¥${money(e.offer.priceCents)}'),
        if (!e.offer.available) const LText('已下架'),
        const SizedBox(height: 12), Text('${tr(context, kindNames[e.offer.kind]!)} · ${e.offer.window}${e.offer.channel == 'douyin' ? ' · ${tr(context, '抖音团购')}' : ''}'),
        if (e.offer.notes.isNotEmpty) Text(e.offer.notes),
        const LText('价格可能有变动，以店内为准。'),
        if (DateTime.tryParse(e.offer.updatedAt) case final date?) Text('${tr(context, '信息更新于')} ${MaterialLocalizations.of(context).formatMediumDate(date)}', style: Theme.of(context).textTheme.bodySmall),
        if (e.offer.example) const LText('这是示例数据，不是真实菜单。'),
        QuantityPicker(value: count, onChanged: (n) => refresh(() => count=n)),
        Text('${tr(ctx, '合计')} ¥${money(e.offer.priceCents*count)}'),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('关闭')),
        TextButton(onPressed: () => Navigator.pop(ctx,count), child: const LText('记录这一顿'))])));
    if (selected != null && mounted) await recordMeal(FavoriteMeal(storeKey:e.placeKey,storeName:e.place.name,kind:kindNames[e.offer.kind]!,savedAt:DateTime.now().toIso8601String(),items:[FavoriteItem.entry(e,quantity:selected)]));
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
    const images = {
      'official:mg': 'assets/stores/maigang.webp',
      'official:sf': 'assets/stores/shiweifang.webp',
      'official:community': 'assets/stores/community.webp',
      'official:jml': 'assets/stores/jinmianlang.png',
      'official:btk': 'assets/stores/baite.jpg',
      'official:btz': 'assets/stores/baite-chinese.jpg',
      'official:zxb': 'assets/stores/zhongxiaobei.jpg',
    };
    final image = images[storeKey];
    if (image == null) return SizedBox(width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200, child: const ColoredBox(color: Color(0xffeee7df), child: Icon(Icons.storefront)));
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(
      image, key: ValueKey('${storeKey.split(':').last}-${thumbnail ? 'thumbnail' : 'cover'}'),
      width: thumbnail ? 60 : double.infinity, height: thumbnail ? 56 : 200,
      cacheWidth: thumbnail ? 180 : 1280, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: tr(context, '{store}店铺实景', params: {'store': place?.name ?? tr(context, '店铺')}),
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
      title: Text(name), subtitle: LText('{store} · 米饭另计 ¥{price}', params: {'store': p.location, 'price': money(p.priceCents)}),
      trailing: Text('¥${money(p.dishPrices[name]!)}'), onTap: () async {
        var count=1;
        final selected=await showDialog<int>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(title:Text(name),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            DishPhoto(asset:p.dishPhotos[name] ?? '',large:true),
            LText('{store} · 米饭另计 ¥{price}',params:{'store':p.location,'price':money(p.priceCents)}),
            QuantityPicker(value:count,onChanged:(n)=>refresh(()=>count=n)),
            Text('${tr(ctx,'合计')} ¥${money(p.dishPrices[name]!*count)}'),
          ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const LText('关闭')),
            TextButton(onPressed:()=>Navigator.pop(ctx,count),child:const LText('记录这一顿'))])));
        final store=riceStoreKey(p,riceStores);
        if(selected!=null && mounted && store!=null) await recordMeal(FavoriteMeal(storeKey:store,storeName:riceStores[store]!,kind:'米饭选菜',savedAt:DateTime.now().toIso8601String(),items:[FavoriteItem(riceDishKey(p,name),name,p.dishPrices[name]!,quantity:selected,asset:p.dishPhotos[name] ?? '')]));
      }));
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
      LText('${visible.length + riceItems.length} 个菜品', style: const TextStyle(fontSize: 12, color: Color(0xff777972))),
      ])),
      SliverList.builder(itemCount: visible.length, itemBuilder: (context, index) {
        final e = visible[index];
        return Card(key: ValueKey(e.key), child: ListTile(leading: DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo), onTap: () => detail(e), title: Text(e.offer.name),
        subtitle: Text('${e.place.name} ${e.offer.window} · ${e.offer.mealPeriods.map((p)=>tr(context, periodNames[p] ?? p)).join("/")} · ${tr(context, kindNames[e.offer.kind]!)}${e.offer.channel == 'douyin' ? ' · ${tr(context, '抖音团购')}' : ''}\n${tr(context, e.db.source == Source.official ? '官方菜单' : '我的菜单')}${e.offer.example ? ' · ${tr(context, '示例')}' : ''}${e.offer.available ? '' : ' · ${tr(context, '已下架')}'}'),
        trailing: LText('¥${money(e.offer.priceCents)}')));
      }),
      SliverList.builder(itemCount: riceItems.length, itemBuilder: (context, index) => riceDishTile(riceItems[index])),
      if (visible.isEmpty && riceItems.isEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: LText('暂无符合条件的菜品。可以在“菜单管理”添加自己的菜单。'))),
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
        selected == null ? '选择店铺，查看它的菜品、窗口和价格。' : selected.$2.area, translate: selected == null),
      scopePicker(), const SizedBox(height: 12),
      if (selected == null) ...[
        FilledButton.icon(onPressed: addStore, icon: const Icon(Icons.add_business), label: const LText('添加个人店铺')),
        LText('${shops.length} 家店铺'),
        for (final shop in shops) Card(child: ListTile(
          key: ValueKey('store-${shop.$1}'), leading: shopPhoto(shop.$1, thumbnail: true),
          title: Text(shop.$2.name), subtitle: Text('${shop.$2.area}\n${tr(context, shop.$3.source == Source.official ? '官方菜单' : '我的菜单')} · ${tr(context, '{count} 个菜品', params: {'count': shop.$3.offers.where((o) => o.placeId == shop.$2.id).length})}'),
          trailing: const Icon(Icons.chevron_right), onTap: () => setState(() { selectedStore=shop.$1; query=''; browseCategory='all'; stapleFilter='all'; }))),
        if (shops.isEmpty) const LText('还没有店铺，先添加一家。'),
      ] else ...[
        TextButton.icon(onPressed: () => setState(() => selectedStore=null), icon: const Icon(Icons.arrow_back), label: const LText('返回全部店铺')),
        shopPhoto(selected.$1),
        if (selected.$3.source == Source.personal) TextButton.icon(onPressed: () => editOffer(null, selected.$2), icon: const Icon(Icons.add), label: const LText('给这家店添加菜品')),
        const SizedBox(height: 12), categoryFilter(), staplePicker(),
        LText('${dishes.length + riceCatalog(store: selected.$1).length} 个菜品'),
        for (final e in dishes) Card(child: ListTile(leading: DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo), onTap: () => detail(e), title: Text(e.offer.name),
          subtitle: Text('${e.offer.window} · ${tr(context, kindNames[e.offer.kind]!)}${e.offer.channel == 'douyin' ? ' · ${tr(context, '抖音团购')}' : ''}${e.offer.available ? '' : ' · ${tr(context, '已下架')}'}'),
          trailing: LText('¥${money(e.offer.priceCents)}'))),
        for (final item in riceCatalog(store: selected.$1)) riceDishTile(item),
        if (dishes.isEmpty && riceCatalog(store: selected.$1).isEmpty) const LText('这家店暂未录入菜品。'),
      ],
    ]);
  }
  Future<void> transfer(Source source, bool importing) async {
    final db = source == Source.official ? repo!.official : repo!.personal;
    var diagnostic = false;
    var exportText = '';
    if (!importing) {
      try { exportText = MenuRepository.exportMenu(db); }
      on FormatException { diagnostic = true; exportText = db.encode(compact: true); }
    }
    if (!importing) {
      await showBackupExportDialog(context, text: exportText,
          name: source == Source.official ? 'eaten-yet-official-menu.json' : 'eaten-yet-my-menu.json',
          diagnostic: diagnostic);
      return;
    }
    await showBackupImportDialog<MenuDb>(context,
      title: tr(context, '导入{menu}', params: {'menu': tr(context, source == Source.official ? '官方菜单' : '我的菜单')}),
      inputLabel: '菜单文件内容', checkLabel: '检查菜单', saveLabel: '确认替换菜单',
      maxBytes: MenuDb.maxJsonLength * 4,
      parse: (text) {
        final data = MenuDb.decode(text, source);
        if (source == Source.official && data.revision <= db.revision) {
          throw const FormatException('这份菜单不是新版，请选择更新的菜单文件。');
        }
        return data;
      },
      describe: (data) => tr(context, '已读取：{stores} 家店 · {items} 个菜品',
          params: {'stores': data.places.length, 'items': data.offers.length}),
      onSave: (data) async {
        if (!await save(data)) throw StateError('Menu save failed');
      });
  }
  Future<void> editOffer([Offer? old, Place? preselected]) async {
    final db = repo!.personal;
    final place = old == null ? preselected : db.places.firstWhere((p) => p.id == old.placeId);
    final name = TextEditingController(text: old?.name ?? '');
    final shop = TextEditingController(text: place?.name ?? '');
    final area = TextEditingController(text: place?.area ?? tr(context, '中北大学周边'));
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final portion = TextEditingController(text: old?.portion ?? tr(context, '1 份'));
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
          catch (e) { if (ctx.mounted) refresh(() => error=e is FormatException && e.message == '照片过大，请选择小于300KB的图片' ? e.message : '照片读取失败，请换一张再试。'); }
          finally { if (ctx.mounted) refresh(() => picking=false); }
        }, icon: const Icon(Icons.photo_library_outlined), label: LText(photo.isEmpty ? '添加照片' : '更换照片')),
        if (photo.isNotEmpty) TextButton(onPressed: () => refresh(() => photo=''), child: const LText('移除照片'))]),
        const SizedBox(height: 20),
        for (final field in [(name, '菜名'), (shop, '店铺名称'), (area, '位置 / 区域'), (price, '售价（元）'), (portion, '份量'), (window, '窗口（可留空）'), (notes, '购买规则 / 说明')])
          Padding(padding: const EdgeInsets.only(bottom: 20), child: TextField(controller: field.$1, decoration: InputDecoration(labelText: tr(context, field.$2)))),
        DropdownButtonFormField<String>(initialValue: kind, decoration: InputDecoration(labelText: tr(context, '菜品类型')),
          items: kindNames.entries.map((e) => DropdownMenuItem(value: e.key, child: LText(e.value))).toList(),
          onChanged: (v) => refresh(() { kind = v!; addon = false; alcohol = false; })),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(initialValue: staple, decoration: InputDecoration(labelText: tr(context, '主食分类')),
          items: stapleNames.entries.map((e) => DropdownMenuItem(value: e.key, child: LText(e.value))).toList(),
          onChanged: (v) => refresh(() => staple=v!)),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(initialValue: channel, decoration: InputDecoration(labelText: tr(context, '价格来源')),
          items: const [DropdownMenuItem(value: 'regular', child: LText('直接购买')), DropdownMenuItem(value: 'douyin', child: LText('抖音团购'))],
          onChanged: (v) => refresh(() => channel = v!)),
        const SizedBox(height: 16),
        if (kind == 'drink') CheckboxListTile(title: const LText('酒精饮品（不参与推荐）'), value: alcohol, onChanged: (v) => refresh(() => alcohol = v!)),
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
          catch (e) { if (ctx.mounted) refresh(() => error=e is FormatException && e.message == '照片过大，请选择小于300KB的图片' ? e.message : '照片读取失败，请换一张再试。'); }
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
        notify('已经有一家同名同位置的店铺');
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
      content: LText('删除“{dish}”？', params: {'dish': offer.name}), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const LText('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const LText('删除'))]));
    if (accepted != true || !mounted) return;
    final db = repo!.personal;
    await save(MenuDb(source: db.source, revision: db.revision + 1, places: db.places, foods: db.foods, ricePlans: db.ricePlans, offers: db.offers.where((o) => o.id != offer.id).toList()));
  }
  Widget libraries() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    OutlinedButton.icon(onPressed: manageOfficial, icon: const Icon(Icons.download), label: const LText('官方菜单')),
    title('你的菜单，你做主', '可以用官方菜单选餐，也可以加上自己常吃的菜。'),
    for (final db in [repo!.official, repo!.personal]) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LText(db.source == Source.official ? '官方菜单' : '我的菜单', style: Theme.of(context).textTheme.titleLarge),
      LText('{stores} 家店 · {items} 个菜品', params: {'stores': db.places.length, 'items': db.offers.length}),
      const SizedBox(height: 10), LText(db.source == Source.official ? '可以导入新版菜单文件。' : '保存在本机，可随时修改。'),
      Wrap(spacing: 8, children: [TextButton(onPressed: busy ? null : () => transfer(db.source, false), child: const LText('导出备份')),
        TextButton(onPressed: busy ? null : () => transfer(db.source, true), child: LText(db.source == Source.official ? '导入更新' : '导入我的菜单'))]),
    ]))),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: busy ? null : addStore, icon: const Icon(Icons.add_business), label: const LText('添加个人店铺')),
    const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : () => editOffer(), icon: const Icon(Icons.add), label: const LText('添加个人菜品')),
    const SizedBox(height: 12),
    for (final o in repo!.personal.offers) Card(child: ListTile(leading: DishPhoto(data: o.photo), title: Text(o.name), subtitle: Text('¥${money(o.priceCents)} · ${tr(context, o.available ? '在售' : '已下架')}'),
      onTap: busy ? null : () => editOffer(o), trailing: IconButton(tooltip: tr(context, '删除个人菜品'), onPressed: busy ? null : () => deleteOffer(o), icon: const Icon(Icons.delete_outline)))),
    const SizedBox(height: 12), const LText('官方菜单和我的菜单分开保存，互不覆盖。'),
  ]);
  @override
  Widget build(BuildContext context) {
    if (repo == null) return Scaffold(body: Center(child: loadError == null ? const CircularProgressIndicator() :
      Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [LText(loadError!), TextButton(onPressed: load, child: const LText('重试')), TextButton(onPressed: exportRecovery, child: const LText('导出备份（排障用）'))]))));
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
