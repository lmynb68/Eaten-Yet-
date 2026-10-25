import 'dart:math';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'photos.dart';
import 'language.dart';
import 'favorites.dart';

int mealCostWithSnack(Entry meal, Entry? snack) => meal.offer.priceCents +
  (snack?.placeKey == meal.placeKey ? snack!.offer.priceCents : 0);

List<Entry> snackChoices(List<Entry> pool, int budget, int mainPrice, {String? placeKey}) => pool.where((e) =>
  (placeKey == null || e.placeKey == placeKey) && e.offer.kind == 'side' && !e.offer.addonOnly && e.offer.available &&
  !e.offer.alcohol && e.offer.channel == 'regular' && e.offer.priceCents + mainPrice <= budget).toList();

class SnackPanel extends StatelessWidget {
  final List<Entry> pool;
  final int? budget;
  final int mainPrice;
  final String placeKey;
  final Entry? selected;
  final ValueChanged<Entry?> onChanged;
  final double Function(Entry)? weight;
  const SnackPanel({super.key, required this.pool, required this.budget, required this.mainPrice,
    required this.placeKey, required this.selected, required this.onChanged, this.weight});
  @override
  Widget build(BuildContext context) {
    final choices = snackChoices(pool, budget ?? 0, mainPrice, placeKey: placeKey);
    final current = selected?.placeKey == placeKey ? selected : null;
    final total = mainPrice + (current?.offer.priceCents ?? 0);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const LText('小食（可不选）', style: TextStyle(fontWeight: FontWeight.bold)),
      Text('仅限同店：${pool.where((e) => e.placeKey == placeKey).firstOrNull?.place.name ?? placeKey}'),
      const SizedBox(height: 12),
      if (current != null) ListTile(contentPadding: EdgeInsets.zero,
        leading: DishPhoto(asset: dishAssetForEntry(selected!), data: selected!.offer.photo), title: Text(selected!.offer.name),
        subtitle: Text('${selected!.place.name} · ¥${money(selected!.offer.priceCents)}'),
        trailing: IconButton(tooltip: tr(context,'不选小食'), onPressed: () => onChanged(null), icon: const Icon(Icons.close))),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: () async {
          final picked = await showDialog<Entry>(context: context, builder: (ctx) => AlertDialog(
            title: const LText('选择小食'), content: SizedBox(width: 460, height: 360,
              child: choices.isEmpty ? const LText('剩余预算内没有小食') : ListView(children: [
                for (final e in choices) ListTile(leading: DishPhoto(asset: dishAssetForEntry(e), data: e.offer.photo), title: Text(e.offer.name),
                  subtitle: Text('${e.place.name} · ¥${money(e.offer.priceCents)}'), onTap: () => Navigator.pop(ctx,e)),
              ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消'))]));
          if (context.mounted && picked != null) onChanged(picked);
        }, child: const LText('选择小食')),
        TextButton(onPressed: choices.isEmpty ? null : () {
          final different = choices.where((e) => e.key != selected?.key).toList();
          final candidates = different.isEmpty ? choices : different;
          onChanged(weightedPick<Entry>(candidates, Random(), weight ?? (_) => 1));
        }, child: const LText('随机小食')),
      ]),
      Text('${tr(context,'合计')} ¥${money(total)}'),
      if (total > (budget ?? 0)) const LText('当前选择超出新预算，请重新选择。', style: TextStyle(color: Colors.red)),
    ])));
  }
}
