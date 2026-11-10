import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'rice_worker.dart';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'rice.dart';
import 'snacks.dart';
import 'photos.dart';
import 'language.dart';
import 'favorites.dart';
import 'quantity.dart';

class RicePanel extends StatefulWidget {
  final List<(String, RicePlan)> plans;
  final int? budget;
  final bool snacksOnly;
  final FavoriteStore? preferences;
  final Future<void> Function(RicePlan, List<String>, Entry?)? onFavorite;
  final Future<void> Function(FavoriteMeal)? onMealFavorite, onRecord;
  final bool Function(FavoriteMeal)? isMealFavorite;
  final bool favoriteBusy;
  final Future<RiceResult> Function(Map<String,dynamic>)? randomizer;
  final bool Function(RicePlan, List<String>, Entry?)? isFavorite;
  final List<Entry> snacks;
  final Map<String,String> stores;
  final Future<bool> Function(RicePlan) savePersonal;
  const RicePanel({super.key, this.randomizer, this.snacksOnly = false, this.onMealFavorite, this.onRecord, this.isMealFavorite, this.preferences, this.onFavorite, this.isFavorite, this.favoriteBusy = false, this.stores = const {}, this.snacks = const [], required this.plans, required this.budget, required this.savePersonal});
  @override
  State<RicePanel> createState() => _RicePanelState();
}
class _RicePanelState extends State<RicePanel> {
  bool randomBusy = false;
  String fingerprint() => jsonEncode([keyValue, plan?.toJson(), widget.budget, dishes,
    quantities, baseQuantity, snack?.key, snackQuantity, locked.toList()..sort(), meatCount,
    widget.preferences?.scoringSnapshot]);
  Future<void> shuffle(RicePlan p, bool hasTypes, bool free) async {
    if (randomBusy) return;
    final before = fingerprint();
    final job = <String,dynamic>{'plan':p.toJson(), 'budget':widget.budget! - (snack?.offer.priceCents ?? 0)*snackQuantity,
      'dishes':[...dishes], 'locked':locked.toList(), 'quantities':[...quantities], 'baseQuantity':baseQuantity,
      'free':free, 'meatCount':hasTypes ? meatCount : null, 'snack':snack?.key,
      'preferences':widget.preferences?.scoringSnapshot, 'seed':Random().nextInt(1 << 32)};
    setState(() => randomBusy=true);
    try {
      final result = await (widget.randomizer?.call(job) ?? compute(calculateRice,job));
      if (!mounted || fingerprint() != before) return;
      setState(() {message=result.message; if(result.dishes != null) dishes=result.dishes!;});
    } catch (_) {
      if (mounted && fingerprint() == before) setState(() => message='选菜暂时失败，请重试。');
    } finally {if(mounted)setState(() => randomBusy=false);}
  }
  String? keyValue;
  int? meatCount = 1;
  Entry? snack;
  int baseQuantity = 1, snackQuantity = 1;
  List<int> quantities = [1,1,1];
  List<String?> dishes = [null,null,null];
  final locked = <int>{};
  String message = '自己挑，或者交给它随机。';
  RicePlan? get plan => widget.plans.where((p) => p.$1 == keyValue).firstOrNull?.$2;
  void reset() { snack=null; baseQuantity=1; snackQuantity=1; final count = plan?.pricedByDish == true && meatCount == null ? 1 : 3; dishes = List.filled(count,null,growable:true); quantities=List.filled(count,1,growable:true); locked.clear(); }
  @override
  void initState() { super.initState(); keyValue = widget.plans.firstOrNull?.$1; }
  @override
  void didUpdateWidget(covariant RicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.plans.where((p) => p.$1 == keyValue).firstOrNull?.$2;
    if (old?.toJson().toString() != plan?.toJson().toString()) {
      reset(); message = '套餐数据或范围已更新，请重新选择。';
    }
    if (snack != null && !widget.snacks.any((e) => e.fingerprint == snack!.fingerprint)) snack=null;
    if (snack != null && (plan == null || snack!.placeKey != riceStoreKey(plan!, widget.stores))) snack=null;
    if (plan == null) { keyValue = widget.plans.firstOrNull?.$1; reset(); }
  }
  Future<void> edit(RicePlan? old) async {
    final name = TextEditingController(text: old?.name ?? tr(context, '我的米饭套餐'));
    final location = TextEditingController(text: old?.location ?? '');
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final labels = List.generate(3, (i) => TextEditingController(text: old?.labels[i] ?? tr(context, '第${i+1}道菜')));
    final options = List.generate(3, (i) => TextEditingController(text: old == null ? '' : old.options[i].map((n) => old.pricedByDish ? '$n|${money(old.dishPrices[n]!)}' : n).join('、')));
    RicePlan? result;
    String? error;
    String? storeKey = old == null ? null : riceStoreKey(old, widget.stores);
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const LText('编辑我的米饭套餐'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        LText(old?.pricedByDish == true ? '每道菜填写“菜名|价格”，用顿号或换行分隔。米饭价格单独填写。' : '填写可选菜品。套餐价格已含米饭，加价菜请另建套餐。官方套餐会复制到我的菜单。'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: storeKey, isExpanded: true,
          decoration: InputDecoration(labelText: tr(context,'所属店铺')),
          items: widget.stores.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => refresh(() => storeKey=v)),
        for (final field in [(name,'套餐名称'),(location,'餐厅 / 窗口'),(price,old?.pricedByDish == true ? '米饭价格（元）' : '整套售价（元，含米饭）')])
          Padding(padding: const EdgeInsets.only(top: 16), child: TextField(controller: field.$1, decoration: InputDecoration(labelText: tr(context, field.$2)))),
        for (var i=0;i<3;i++) ...[
          const SizedBox(height: 16),
          TextField(controller: labels[i], decoration: InputDecoration(labelText: tr(context,'菜品类别') + ' ${i+1}')),
          const SizedBox(height: 16),
          TextField(controller: options[i], minLines: 1, maxLines: 4,
            decoration: InputDecoration(labelText: tr(context, '可选成品菜，用顿号或换行分隔；可留空待补充'))),
        ],
        if (error != null) LText(error!, style: const TextStyle(color: Colors.red)),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消')),
        FilledButton(onPressed: () {
          try {
            final rows = options.map((c) => c.text.split(RegExp('[、，,\\n]'))
              .map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()).toList();
            final prices = <String,int>{};
            if (old?.pricedByDish == true) {
              for (final row in rows.expand((v) => v)) {
                final parts = row.split('|');
                final value = parts.length == 2 ? parseMoney(parts[1].trim()) : null;
                if (value == null || value <= 0 || parts.first.trim().isEmpty) {
                  throw const FormatException('请按 菜名|价格 填写每道菜');
                }
                final dish = parts.first.trim();
                if (prices.containsKey(dish) && prices[dish] != value) {
                  throw const FormatException('同一道菜的价格必须一致');
                }
                prices[dish] = value;
              }
            }
            result = RicePlan(id: keyValue?.startsWith('personal:') == true && old != null
              ? old.id : 'rice${DateTime.now().microsecondsSinceEpoch}', name: name.text.trim(),
              storeKey: storeKey ?? '', location: location.text.trim(), priceCents: parseMoney(price.text) ?? 0,
              dishTypes: {for (final n in rows.expand((r) => r).map((n) => n.split('|').first.trim()))
                if (old != null && riceDishType(old, n) != null) n: riceDishType(old, n)!},
              dishPrices: prices, dishPhotos: old?.dishPhotos ?? {}, riceRefill: old?.riceRefill ?? false,
              labels: labels.map((c) => c.text.trim()).toList(),
              options: rows.map((r) => r.map((n) => old?.pricedByDish == true ? n.split('|').first.trim() : n).toSet().toList()).toList());
            result!.validate(); Navigator.pop(ctx);
          } catch (e) { result = null; refresh(() => error = e is FormatException && ['请按 菜名|价格 填写每道菜', '同一道菜的价格必须一致'].contains(e.message) ? e.message : '请检查套餐名称、价格和菜品。'); }
        }, child: const LText('保存到我的菜单')),
      ])));
    if (result != null && mounted) {
      final saved = await widget.savePersonal(result!);
      if (saved && mounted) setState(() { keyValue = null; reset(); message = '已保存。切换到“我的菜单”就能用。'; });
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in [name,location,price,...labels,...options]) { c.dispose(); }
    });
  }
  @override
  Widget build(BuildContext context) {
    final p = plan;
    final hasTypes = p != null && p.options.expand((r) => r).any((n) => riceDishType(p, n) != null);
    final free = p?.pricedByDish == true && meatCount == null;
    final total = p?.totalPrice(dishes, quantities: quantities, baseQuantity: baseQuantity) ?? 0;
    FavoriteMeal? meal;
    if (p != null && dishes.any((d) => d != null) && riceStoreKey(p, widget.stores) != null) {
      final store = riceStoreKey(p, widget.stores)!;
      meal = FavoriteMeal(storeKey: store, storeName: widget.stores[store]!, kind: "米饭选菜", savedAt: DateTime.now().toIso8601String(), ricePrice: p.priceCents, baseQuantity: baseQuantity, baseLabel: p.pricedByDish ? "米饭" : "套餐（含米饭）", items: [
        for (var i=0;i<dishes.length;i++) if (dishes[i] != null) FavoriteItem(riceDishKey(p,dishes[i]!), dishes[i]!, p.dishPrices[dishes[i]] ?? 0, quantity: p.pricedByDish ? quantities[i] : baseQuantity, asset: p.dishPhotos[dishes[i]] ?? ""),
        if (snack != null) FavoriteItem.entry(snack!,quantity: snackQuantity)]);
    }
    final affordable = p != null && widget.budget != null && widget.budget! >= p.priceCents * baseQuantity + (snack?.offer.priceCents ?? 0) * snackQuantity;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.plans.length > 1 && !widget.snacksOnly)
        DropdownButtonFormField<String>(key: ValueKey(keyValue), initialValue: keyValue,
          isExpanded: true, decoration: InputDecoration(labelText: tr(context, '套餐来源')),
          items: widget.plans.map((v) => DropdownMenuItem(value: v.$1, child: Text(v.$2.location))).toList(),
          onChanged: (v) => setState(() { keyValue=v; reset(); })),
      if (p == null) const LText('所选店铺没有米饭选菜。'),
      if (widget.snacksOnly && p != null) ...[
        LText('{store} · 已选：{dishes}', params: {'store': p.location, 'dishes': dishes.whereType<String>().join('、')}),

      ],
      if (p != null && !widget.snacksOnly) ...[
        if (hasTypes || p.pricedByDish) ...[
          const SizedBox(height: 16),
          const LText('搭配方案'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final item in <(int?, String)>[(0,'3素'),(1,'2素1荤'),(2,'1素2荤'),(null,'自由选菜')])
              ChoiceChip(label: LText(item.$2), selected: meatCount == item.$1,
                onSelected: (_) => setState(() { final wasFree = p.pricedByDish && meatCount == null; meatCount = item.$1; if (wasFree != (p.pricedByDish && meatCount == null)) reset();
                  message = wasFree != (p.pricedByDish && meatCount == null) ? '搭配已切换，请重新选菜。' : '搭配已切换，已选菜品和锁定保持不变。'; })),
          ]),
          const SizedBox(height: 8),
          LText(p.pricedByDish ? '鸡蛋算素菜。价格＝米饭＋所选菜品。' : '鸡蛋算素菜。套餐价格已含米饭。'),
          const SizedBox(height: 12),
        ],
        if (!p.pricedByDish) ...[const SizedBox(height: 12), const DishPhoto(large: true)],
        const SizedBox(height: 12), Text(p.pricedByDish ? '${p.location} · ${tr(context, '米饭')} ¥${money(p.priceCents)}${p.riceRefill ? tr(context, '（免费续饭）') : ''}' : '${p.location} · ${tr(context, '套餐（含米饭）')} ¥${money(p.priceCents)}'),
        if (p.pricedByDish) LText('已选菜品＋米饭：¥{price}', params: {'price': money(total)}, key: const Key('rice-total')),
        if (total + (snack?.offer.priceCents ?? 0) * snackQuantity > (widget.budget ?? 0))
          const LText('当前总价超出预算，请更换菜品或取消小食。', style: TextStyle(color: Colors.red)),
        if (!affordable) const LText('请输入足够的预算后选菜；已选结果保留。', style: TextStyle(color: Colors.red)),
        if (p.options.any((v) => v.isEmpty)) const LText('这个套餐还没填可选菜。复制一份，补上今天的菜就能用。'),
        QuantityPicker(value: baseQuantity, label: p.pricedByDish ? "米饭份数" : "套餐份数", onChanged: (n) => setState(() => baseQuantity=n)),
        for (var i=0;i<dishes.length;i++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (p.pricedByDish && dishes[i] != null) ...[DishPhoto(asset: p.dishPhotos[dishes[i]] ?? '', large: true), const SizedBox(height: 8)],
          Row(children: [
          Expanded(child: DropdownButtonFormField<String>(key: ValueKey('$keyValue:$i:${dishes[i]}'),
            initialValue: dishes[i], isExpanded: true,
            decoration: InputDecoration(labelText: '${tr(context, '第${i+1}道菜')} · ${free ? '' : p.labels[i]}'),
            items: (free ? p.options.expand((r) => r).toSet().toList() : p.options[i]).map((n) => DropdownMenuItem(value: n,
              enabled: dishes[i] == n || !dishes.contains(n), child: Row(children: [
                Padding(padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 36, height: 36, child: DishPhoto(asset: p.dishPhotos[n] ?? ''))),
                Expanded(child: Text(p.pricedByDish ? '$n · ¥${money(p.dishPrices[n]!)}' : n, overflow: TextOverflow.ellipsis)),
              ]))).toList(),
            onChanged: locked.contains(i) ? null : (v) => setState(() {
              final next = [...dishes]..[i] = v;
              if (p.totalPrice(next, quantities: quantities, baseQuantity: baseQuantity) + (snack?.offer.priceCents ?? 0) * snackQuantity > (widget.budget ?? 0)) {
                message='所选菜品和小食超出预算，原选择保留'; return;
              }
              dishes=next; message='喜欢这道菜就锁定，再随机选其他菜。'; }))),
          if (p.pricedByDish && dishes[i] != null && !locked.contains(i)) IconButton(tooltip: tr(context,'清除这道菜'),
            onPressed: () => setState(() => dishes[i]=null), icon: const Icon(Icons.close)),
          IconButton(key: Key('rice-lock-$i'), tooltip: tr(context, locked.contains(i) ? '解锁' : '锁定'),
            onPressed: dishes[i] == null ? null : () => setState(() { locked.contains(i) ? locked.remove(i) : locked.add(i); }),
            icon: Icon(locked.contains(i) ? Icons.lock : Icons.lock_open)),
        ]),
          if (p.pricedByDish && dishes[i] != null) QuantityPicker(value: quantities[i], onChanged: (n) => setState(() => quantities[i]=n)),
          if (free) TextButton(onPressed: dishes.length <= 1 ? null : () => setState(() { dishes.removeAt(i); quantities.removeAt(i); final remaining = locked.where((n) => n != i).map((n) => n > i ? n-1 : n).toList(); locked..clear()..addAll(remaining); }), child: const LText('移除这道菜')),
        ]))),
        if (free) TextButton.icon(onPressed: dishes.length >= 20 ? null : () => setState(() { dishes.add(null); quantities.add(1); }), icon: const Icon(Icons.add), label: const LText('添加一道菜')),
        FilledButton.icon(onPressed: !affordable || randomBusy ? null : () => shuffle(p,hasTypes,free),
          icon: randomBusy ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.shuffle),
          label: LText(randomBusy ? '正在选菜…' : '随机其余菜品')),
        TextButton(onPressed: () => edit(p), child: LText(keyValue!.startsWith('official:') ? (p.pricedByDish ? '复制到我的菜单并编辑' : '复制到我的菜单并补充菜名') : '编辑这个个人套餐')),
      ],
      if (p != null && dishes.any((d) => d != null) && riceStoreKey(p, widget.stores) != null) SnackPanel(placeKey: riceStoreKey(p, widget.stores)!, pool: widget.snacks, budget: widget.budget, mainPrice: total, selected: snack, quantity: snackQuantity, onQuantityChanged: (n) => setState(() => snackQuantity=n), weight: (e) => widget.preferences?.score([for (final name in dishes.whereType<String>()) riceDishKey(p, name), e.key]) ?? 1, onChanged: (v) => setState(() { snack=v; snackQuantity=1; })),
      if (p != null && riceStoreKey(p, widget.stores) == null) const LText('这个套餐还没选店铺，先选一家。'),
      if (p != null && dishes.any((d) => d != null) && (widget.onFavorite != null || widget.onMealFavorite != null) && riceStoreKey(p, widget.stores) != null)
        OutlinedButton.icon(key: const Key('meal-favorite'),
          onPressed: widget.favoriteBusy ? null : () => widget.onMealFavorite != null ? widget.onMealFavorite!(meal!) : widget.onFavorite!(p, dishes.whereType<String>().toList(), snack),
          icon: Icon((widget.isMealFavorite?.call(meal!) ?? widget.isFavorite?.call(p, dishes.whereType<String>().toList(), snack)) == true ? Icons.favorite : Icons.favorite_border),
          label: LText((widget.isMealFavorite?.call(meal!) ?? widget.isFavorite?.call(p, dishes.whereType<String>().toList(), snack)) == true ? '已收藏，再点取消' : '满意，收藏这一顿')),
      if (meal != null && widget.onRecord != null) TextButton.icon(onPressed: widget.favoriteBusy ? null : () => widget.onRecord!(meal!), icon: const Icon(Icons.history), label: const LText('记录这一顿')),
      if (!widget.snacksOnly) LText(message, key: const Key('rice-status')),
      if (!widget.snacksOnly) TextButton.icon(onPressed: () => edit(null), icon: const Icon(Icons.add), label: const LText('新建个人米饭套餐')),
    ]);
  }
}
