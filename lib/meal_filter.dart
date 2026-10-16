import 'package:flutter/material.dart';
import 'language.dart';

class MealTarget {
  final String key, storeKey, storeName, name;
  const MealTarget(this.key, this.storeKey, this.storeName, this.name);
}

bool matchesMealFilter(Set<String>? selected, String key) => selected == null || selected.contains(key);

Future<Set<String>?> showMealFilter(BuildContext context, List<MealTarget> targets,
    Set<String>? selected) => showDialog<Set<String>>(context: context, builder: (ctx) {
  final draft = selected == null ? targets.map((e) => e.key).toSet() : {...selected};
  final groups = <String,List<MealTarget>>{};
  for (final target in targets) { groups.putIfAbsent(target.storeKey, () => []).add(target); }
  return StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
    title: const LText('筛选店铺和主餐'),
    content: SizedBox(width: 560, height: MediaQuery.sizeOf(ctx).height * .6,
      child: Column(children: [
        const LText('可多选店铺，或展开店铺勾选主餐；只从勾选项中手选和随机。'),
        Wrap(spacing: 12, children: [
          TextButton(onPressed: () => refresh(() => draft.addAll(targets.map((e) => e.key))), child: const LText('全选')),
          TextButton(onPressed: () => refresh(draft.clear), child: const LText('清空选择')),
        ]),
        Expanded(child: ListView(children: [for (final group in groups.entries)
          ExpansionTile(key: ValueKey('filter-store-${group.key}'),
            title: Text(group.value.first.storeName),
            leading: Checkbox(tristate: true,
              value: group.value.every((e) => draft.contains(e.key)) ? true : group.value.any((e) => draft.contains(e.key)) ? null : false,
              onChanged: (_) => refresh(() {
                final all = group.value.every((e) => draft.contains(e.key));
                for (final e in group.value) { if (all) { draft.remove(e.key); } else { draft.add(e.key); } }
              })),
            children: [for (final e in group.value) CheckboxListTile(
              key: ValueKey('filter-meal-${e.key}'), title: Text(e.name), value: draft.contains(e.key),
              onChanged: (v) => refresh(() { if (v == true) { draft.add(e.key); } else { draft.remove(e.key); } })),
            ]),
        ])),
      ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const LText('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, draft), child: const LText('应用筛选'))],
  ));
});
