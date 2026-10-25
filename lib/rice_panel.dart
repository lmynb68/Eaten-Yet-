import 'dart:math';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'rice.dart';
import 'snacks.dart';
import 'photos.dart';
import 'language.dart';
import 'favorites.dart';

class RicePanel extends StatefulWidget {
  final List<(String, RicePlan)> plans;
  final int? budget;
  final bool snacksOnly;
  final FavoriteStore? preferences;
  final Future<void> Function(RicePlan, List<String>, Entry?)? onFavorite;
  final List<Entry> snacks;
  final Map<String,String> stores;
  final Future<bool> Function(RicePlan) savePersonal;
  const RicePanel({super.key, this.snacksOnly = false, this.preferences, this.onFavorite, this.stores = const {}, this.snacks = const [], required this.plans, required this.budget, required this.savePersonal});
  @override
  State<RicePanel> createState() => _RicePanelState();
}
class _RicePanelState extends State<RicePanel> {
  String? keyValue;
  int? meatCount = 1;
  Entry? snack;
  List<String?> dishes = [null,null,null];
  final locked = <int>{};
  String message = '直接手选或随机搭配成品菜。';
  RicePlan? get plan => widget.plans.where((p) => p.$1 == keyValue).firstOrNull?.$2;
  void reset() { snack=null; dishes = [null,null,null]; locked.clear(); }
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
    if (plan == null) keyValue = widget.plans.firstOrNull?.$1;
  }
  Future<void> edit(RicePlan? old) async {
    final name = TextEditingController(text: old?.name ?? '我的米饭套餐');
    final location = TextEditingController(text: old?.location ?? '');
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final labels = List.generate(3, (i) => TextEditingController(text: old?.labels[i] ?? '菜位${i+1}'));
    final options = List.generate(3, (i) => TextEditingController(text: old == null ? '' : old.options[i].map((n) => old.pricedByDish ? '$n|${money(old.dishPrices[n]!)}' : n).join('、')));
    RicePlan? result;
    String? error;
    String? storeKey = old == null ? null : riceStoreKey(old, widget.stores);
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const LText('维护个人米饭套餐'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        LText(old?.pricedByDish == true ? '按菜计价：每项填写 菜名|价格，用顿号或换行分隔；基础价是米饭费用。' : '填写窗口真实可选的成品菜。整套固定价含米饭；加价菜请另建套餐。官方模板会复制到个人库。'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: storeKey, isExpanded: true,
          decoration: InputDecoration(labelText: tr(context,'所属店铺（用于匹配小食）')),
          items: widget.stores.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => refresh(() => storeKey=v)),
        for (final field in [(name,'套餐名称'),(location,'餐厅 / 窗口'),(price,old?.pricedByDish == true ? '米饭价格（元）' : '整套售价（元，含米饭）')])
          Padding(padding: const EdgeInsets.only(top: 16), child: TextField(controller: field.$1, decoration: InputDecoration(labelText: tr(context, field.$2)))),
        for (var i=0;i<3;i++) ...[
          const SizedBox(height: 16),
          TextField(controller: labels[i], decoration: InputDecoration(labelText: tr(context,'菜位类别') + ' ${i+1}')),
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
          } catch (e) { result = null; refresh(() => error = '$e'); }
        }, child: const LText('保存到个人库')),
      ])));
    if (result != null && mounted) {
      final saved = await widget.savePersonal(result!);
      if (saved && mounted) setState(() { keyValue = null; reset(); message = '已保存到个人库；选择“个人库”或“合并库”后选用。'; });
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in [name,location,price,...labels,...options]) { c.dispose(); }
    });
  }
  @override
  Widget build(BuildContext context) {
    final p = plan;
    final hasTypes = p != null && p.options.expand((r) => r).any((n) => riceDishType(p, n) != null);
    final total = p?.totalPrice(dishes) ?? 0;
    final affordable = p != null && widget.budget != null && widget.budget! >= p.priceCents + (snack?.offer.priceCents ?? 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.plans.length > 1 && !widget.snacksOnly)
        DropdownButtonFormField<String>(key: ValueKey(keyValue), initialValue: keyValue,
          isExpanded: true, decoration: const InputDecoration(labelText: '选菜菜单来源'),
          items: widget.plans.map((v) => DropdownMenuItem(value: v.$1, child: Text(v.$2.location))).toList(),
          onChanged: (v) => setState(() { keyValue=v; reset(); })),
      if (p == null) const LText('所选店铺没有米饭选菜。'),
      if (widget.snacksOnly && p != null) ...[
        LText('${p.location} · 已选：${dishes.whereType<String>().join('、')}'),
        if (dishes.every((d) => d == null)) const LText('请先回到米饭选菜，选好主菜。'),
      ],
      if (p != null && !widget.snacksOnly) ...[
        if (hasTypes) ...[
          const SizedBox(height: 16),
          const LText('搭配方案'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final item in <(int?, String)>[(0,'3素'),(1,'2素1荤'),(2,'1素2荤'),(null,'自由选菜')])
              ChoiceChip(label: LText(item.$2), selected: meatCount == item.$1,
                onSelected: (_) => setState(() { meatCount = item.$1;
                  message = '已切换方案，已选和锁定菜保留；随机时按新方案搭配。'; })),
          ]),
          const SizedBox(height: 8),
          const LText('鸡蛋算素，含肉算荤。3荤请自由手选；价格仍按菜品加米饭计算。'),
          const SizedBox(height: 12),
        ],
        if (!p.pricedByDish) ...[const SizedBox(height: 12), const DishPhoto(large: true)],
        const SizedBox(height: 12), LText(p.pricedByDish ? '${p.location} · 米饭 ¥${money(p.priceCents)}${p.riceRefill ? '（免费续饭）' : ''}' : '${p.location} · 整套 ¥${money(p.priceCents)}（含米饭）'),
        if (p.pricedByDish) LText('已选菜品＋米饭：¥${money(total)}', key: const Key('rice-total')),
        if (total + (snack?.offer.priceCents ?? 0) > (widget.budget ?? 0))
          const LText('当前总价超出预算，请更换菜品或取消小食。', style: TextStyle(color: Colors.red)),
        if (!affordable) const LText('请输入足够的预算后选菜；已选结果保留。', style: TextStyle(color: Colors.red)),
        if (p.options.any((v) => v.isEmpty)) const LText('这个套餐的可选菜名待补充。可以复制到个人库，填入当天窗口菜单后使用。'),
        for (var i=0;i<3;i++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (p.pricedByDish && dishes[i] != null) ...[DishPhoto(asset: p.dishPhotos[dishes[i]] ?? '', large: true), const SizedBox(height: 8)],
          Row(children: [
          Expanded(child: DropdownButtonFormField<String>(key: ValueKey('$keyValue:$i:${dishes[i]}'),
            initialValue: dishes[i], isExpanded: true,
            decoration: InputDecoration(labelText: '${i+1}. ${p.labels[i]}'),
            items: p.options[i].map((n) => DropdownMenuItem(value: n,
              enabled: dishes[i] == n || !dishes.contains(n), child: Row(children: [
                Padding(padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 36, height: 36, child: DishPhoto(asset: p.dishPhotos[n] ?? ''))),
                Expanded(child: LText(p.pricedByDish ? '$n · ¥${money(p.dishPrices[n]!)}' : n, overflow: TextOverflow.ellipsis)),
              ]))).toList(),
            onChanged: locked.contains(i) ? null : (v) => setState(() {
              final next = [...dishes]..[i] = v;
              if (p.totalPrice(next) + (snack?.offer.priceCents ?? 0) > (widget.budget ?? 0)) {
                message='所选菜品和小食超出预算，原选择保留'; return;
              }
              dishes=next; message='已手选，可锁定满意的菜位后随机其余项。'; }))),
          if (p.pricedByDish && dishes[i] != null && !locked.contains(i)) IconButton(tooltip: tr(context,'清除菜位'),
            onPressed: () => setState(() => dishes[i]=null), icon: const Icon(Icons.close)),
          IconButton(key: Key('rice-lock-$i'), tooltip: locked.contains(i) ? '解锁菜位' : '锁定菜位',
            onPressed: dishes[i] == null ? null : () => setState(() { locked.contains(i) ? locked.remove(i) : locked.add(i); }),
            icon: Icon(locked.contains(i) ? Icons.lock : Icons.lock_open)),
        ]),]))),
        FilledButton.icon(onPressed: !affordable || (hasTypes && meatCount == null) ? null : () => setState(() {
          final result = randomRice(p, widget.budget! - (snack?.offer.priceCents ?? 0), dishes, locked, Random(), meatCount: hasTypes ? meatCount : null, score: widget.preferences == null ? null : (names) => widget.preferences!.score([for (final name in names) riceDishKey(p, name), if (snack != null) snack!.key]));
          message=result.message; if (result.dishes != null) dishes=result.dishes!;
        }), icon: const Icon(Icons.shuffle), label: const LText('随机未锁定菜位')),
        TextButton(onPressed: () => edit(p), child: LText(keyValue!.startsWith('official:') ? (p.pricedByDish ? '复制到个人库并编辑' : '复制到个人库并补充菜名') : '编辑这个个人套餐')),
      ],
      if (p != null && dishes.any((d) => d != null) && riceStoreKey(p, widget.stores) != null) SnackPanel(placeKey: riceStoreKey(p, widget.stores)!, pool: widget.snacks, budget: widget.budget, mainPrice: total, selected: snack, weight: (e) => widget.preferences?.score([for (final name in dishes.whereType<String>()) riceDishKey(p, name), e.key]) ?? 1, onChanged: (v) => setState(() => snack=v)),
      if (p != null && riceStoreKey(p, widget.stores) == null) const LText('请先编辑套餐并关联店铺，才能选择同店小食。'),
      if (p != null && dishes.any((d) => d != null) && widget.onFavorite != null)
        OutlinedButton.icon(onPressed: () => widget.onFavorite!(p, dishes.whereType<String>().toList(), snack),
          icon: const Icon(Icons.favorite_border), label: const LText('满意，收藏这一顿')),
      if (!widget.snacksOnly) LText(message, key: const Key('rice-status')),
      if (!widget.snacksOnly) TextButton.icon(onPressed: () => edit(null), icon: const Icon(Icons.add), label: const LText('新建个人米饭套餐')),
    ]);
  }
}
