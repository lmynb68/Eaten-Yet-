import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language.dart';

const navigationIds = ['meal', 'catalog', 'stores', 'libraries', 'favorites'];
const navigationLabels = ['搭一顿', '餐品菜单', '店铺', '菜单库', '我的喜爱'];
const navigationIcons = [
  Icons.shuffle, Icons.restaurant_menu, Icons.storefront, Icons.storage, Icons.favorite,
];
const navigationOrderKey = 'eat_what.navigation_order.v1';

List<int> readNavigationOrder(SharedPreferences preferences) {
  final saved = preferences.get(navigationOrderKey);
  final order = <int>[];
  if (saved is List<String>) {
    for (final id in saved) {
      final index = navigationIds.indexOf(id);
      if (index >= 0 && !order.contains(index)) order.add(index);
    }
  }
  for (var i = 0; i < navigationIds.length; i++) {
    if (!order.contains(i)) order.add(i);
  }
  return order;
}

Future<void> saveNavigationOrder(SharedPreferences preferences, List<int> order) async {
  if (!await preferences.setStringList(navigationOrderKey, [
    for (final index in order) navigationIds[index],
  ])) {
    throw StateError('导航顺序保存失败');
  }
}

class SortableNavigationBar extends StatelessWidget {
  final List<int> order;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelected;
  final void Function(int oldIndex, int newIndex) onReorder;
  const SortableNavigationBar({
    super.key, required this.order, required this.selected, required this.onSelected,
    required this.onReorder, this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final height = 72.0 + (scale > 1 ? (scale - 1) * 30 : 0);
    return Material(color: Colors.white, child: SafeArea(top: false,
      child: SizedBox(height: height, child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth / order.length;
        return ReorderableListView(
          key: const Key('sortable-navigation'),
          scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false, padding: EdgeInsets.zero,
          onReorderItem: (oldIndex, newIndex) { if (enabled) onReorder(oldIndex, newIndex); },
          proxyDecorator: (child, index, animation) => Material(
            color: const Color(0xfff7eee8), elevation: 5,
            borderRadius: BorderRadius.circular(14), child: child),
          children: [
            for (var position = 0; position < order.length; position++)
              SizedBox(key: ValueKey('navigation-${navigationIds[order[position]]}'), width: width,
                child: ReorderableDelayedDragStartListener(index: position, enabled: enabled,
                  child: Semantics(
                    selected: selected == order[position], button: true,
                    hint: tr(context, '长按拖动调整顺序'),
                    child: InkWell(onTap: enabled ? () => onSelected(order[position]) : null,
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedContainer(duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                            decoration: BoxDecoration(
                              color: selected == order[position] ? const Color(0xfff7eee8) : Colors.transparent,
                              borderRadius: BorderRadius.circular(18)),
                            child: Icon(navigationIcons[order[position]], size: 23,
                              color: selected == order[position] ? const Color(0xff914f35) : const Color(0xff777972))),
                          const SizedBox(height: 4),
                          Text(tr(context, navigationLabels[order[position]]), maxLines: 2,
                            textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, height: 1.15,
                              fontWeight: selected == order[position] ? FontWeight.w600 : FontWeight.w400,
                              color: selected == order[position] ? const Color(0xff914f35) : const Color(0xff777972))),
                        ]))),
                  )),
              ),
          ],
        );
      })),
    ));
  }
}
