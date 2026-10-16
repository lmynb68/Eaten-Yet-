import 'dart:math';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'rice.dart';
import 'snacks.dart';
import 'photos.dart';
import 'language.dart';

class RicePanel extends StatefulWidget {
  final List<(String, RicePlan)> plans;
  final int? budget;
  final List<Entry> snacks;
  final Map<String,String> stores;
  final Future<bool> Function(RicePlan) savePersonal;
  const RicePanel({super.key, this.stores = const {}, this.snacks = const [], required this.plans, required this.budget, required this.savePersonal});
  @override
  State<RicePanel> createState() => _RicePanelState();
}
class _RicePanelState extends State<RicePanel> {
  String? keyValue;
  Entry? snack;
  List<String?> dishes = [null,null,null];
  final locked = <int>{};
  String message = '先选套餐，再选择三个成品菜；米饭包含在套餐中。';
  RicePlan? get plan => widget.plans.where((p) => p.$1 == keyValue).firstOrNull?.$2;
  void reset() { snack=null; dishes = [null,null,null]; locked.clear(); }
  @override
  void didUpdateWidget(covariant RicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.plans.where((p) => p.$1 == keyValue).firstOrNull?.$2;
    if (old?.toJson().toString() != plan?.toJson().toString()) {
      reset(); message = '套餐数据或范围已更新，请重新选择。';
    }
    if (snack != null && !widget.snacks.any((e) => e.fingerprint == snack!.fingerprint)) snack=null;
    if (snack != null && (plan == null || snack!.placeKey != riceStoreKey(plan!, widget.stores))) snack=null;
    if (plan == null) keyValue = null;
  }
  Future<void> edit(RicePlan? old) async {
    final name = TextEditingController(text: old?.name ?? '我的米饭套餐');
    final location = TextEditingController(text: old?.location ?? '');
    final price = TextEditingController(text: old == null ? '' : money(old.priceCents));
    final labels = List.generate(3, (i) => TextEditingController(text: old?.labels[i] ?? '菜位${i+1}'));
    final options = List.generate(3, (i) => TextEditingController(text: old?.options[i].join('、') ?? ''));
    RicePlan? result;
    String? error;
    String? storeKey = old == null ? null : riceStoreKey(old, widget.stores);
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const LText('维护个人米饭套餐'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const LText('填写窗口真实可选的成品菜。整套固定价含米饭；加价菜请另建套餐。官方模板会复制到个人库。'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: storeKey, isExpanded: true,
          decoration: InputDecoration(labelText: tr(context,'所属店铺（用于匹配小食）')),
          items: widget.stores.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => refresh(() => storeKey=v)),
        for (final field in [(name,'套餐名称'),(location,'餐厅 / 窗口'),(price,'整套售价（元，含米饭）')])
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
            result = RicePlan(id: keyValue?.startsWith('personal:') == true && old != null
              ? old.id : 'rice${DateTime.now().microsecondsSinceEpoch}', name: name.text.trim(),
              storeKey: storeKey ?? '', location: location.text.trim(), priceCents: parseMoney(price.text) ?? 0,
              labels: labels.map((c) => c.text.trim()).toList(),
              options: options.map((c) => c.text.split(RegExp('[、，,\\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()).toList());
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
    final affordable = p != null && widget.budget != null && widget.budget! >= p.priceCents + (snack?.offer.priceCents ?? 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(key: ValueKey(keyValue), initialValue: p == null ? null : keyValue,
        isExpanded: true, decoration: InputDecoration(labelText: tr(context, '选择米饭套餐')),
        items: widget.plans.map((v) => DropdownMenuItem(value: v.$1,
          child: LText('${v.$1.startsWith('official:') ? '官方' : '个人'} · ${v.$2.name} · ¥${money(v.$2.priceCents)}', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) => setState(() { keyValue=v; reset(); message='可手选或随机，锁定后只换剩余菜位。'; })),
      if (p != null) ...[
        const SizedBox(height: 12), const DishPhoto(large: true),
        const SizedBox(height: 12), LText('${p.location} · 整套 ¥${money(p.priceCents)}（含米饭）'),
        if (!affordable) const LText('请输入足够的预算后选菜；已选结果保留。', style: TextStyle(color: Colors.red)),
        if (p.options.any((v) => v.isEmpty)) const LText('这个套餐的可选菜名待补充。可以复制到个人库，填入当天窗口菜单后使用。'),
        for (var i=0;i<3;i++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(key: ValueKey('$keyValue:$i:${dishes[i]}'),
            initialValue: dishes[i], isExpanded: true,
            decoration: InputDecoration(labelText: '${i+1}. ${p.labels[i]}'),
            items: p.options[i].map((n) => DropdownMenuItem(value: n,
              enabled: dishes[i] == n || !dishes.contains(n), child: LText(n, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: !affordable || locked.contains(i) ? null : (v) => setState(() { dishes[i]=v; message='已手选，可锁定满意的菜位后随机其余项。'; }))),
          IconButton(key: Key('rice-lock-$i'), tooltip: locked.contains(i) ? '解锁菜位' : '锁定菜位',
            onPressed: dishes[i] == null ? null : () => setState(() { locked.contains(i) ? locked.remove(i) : locked.add(i); }),
            icon: Icon(locked.contains(i) ? Icons.lock : Icons.lock_open)),
        ]))),
        FilledButton.icon(onPressed: !affordable ? null : () => setState(() {
          final result = randomRice(p, widget.budget! - (snack?.offer.priceCents ?? 0), dishes, locked, Random());
          message=result.message; if (result.dishes != null) dishes=result.dishes!;
        }), icon: const Icon(Icons.shuffle), label: const LText('随机未锁定菜位')),
        TextButton(onPressed: () => edit(p), child: LText(keyValue!.startsWith('official:') ? '复制到个人库并补充菜名' : '编辑这个个人套餐')),
      ],
      if (p != null && riceStoreKey(p, widget.stores) != null) SnackPanel(placeKey: riceStoreKey(p, widget.stores)!, pool: widget.snacks, budget: widget.budget, mainPrice: p.priceCents, selected: snack, onChanged: (v) => setState(() => snack=v)),
      if (p != null && riceStoreKey(p, widget.stores) == null) const LText('请先编辑套餐并关联店铺，才能选择同店小食。'),
      LText(message, key: const Key('rice-status')),
      TextButton.icon(onPressed: () => edit(null), icon: const Icon(Icons.add), label: const LText('新建个人米饭套餐')),
    ]);
  }
}
