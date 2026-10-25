import 'package:flutter/material.dart';
import 'domain.dart';
import 'language.dart';

class BrowseFilters {
  final Scope scope;
  final String staple;
  final String? store;
  final bool advanced;
  final bool clearMeals;
  const BrowseFilters(this.scope, this.staple, this.store, {this.advanced = false, this.clearMeals = false});
}

Future<BrowseFilters?> showBrowseFilters(BuildContext context, {
  required Scope scope, required String staple, required String? store,
  required Map<String, String> stores, bool advanced = false, bool riceOnly = false,
}) {
  var clearMeals = false;
  var draftScope = scope;
  var draftStaple = staple;
  var draftStore = store;
  return showModalBottomSheet<BrowseFilters>(context: context, isScrollControlled: true,
    showDragHandle: true, useSafeArea: true, backgroundColor: Colors.white,
    builder: (sheetContext) => StatefulBuilder(builder: (context, refresh) {
      Widget options(Map<String, String> values, String selected, ValueChanged<String> change) =>
        LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 8, runSpacing: 8,
          children: [for (final entry in values.entries) SizedBox(
            width: (constraints.maxWidth - 8) / 2,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                backgroundColor: selected == entry.key ? const Color(0xfff7eee8) : const Color(0xfff5f6f3),
                foregroundColor: selected == entry.key ? const Color(0xff914f35) : const Color(0xff45483f),
                side: BorderSide(color: selected == entry.key ? const Color(0xffd8b59f) : Colors.transparent)),
              onPressed: () => refresh(() => change(entry.key)), child: Text(tr(context, entry.value), textAlign: TextAlign.center)),
          )]));
      final visibleStores = Map<String, String>.fromEntries(stores.entries.where((e) =>
        draftScope == Scope.merged || e.key.startsWith(draftScope == Scope.official ? 'official:' : 'personal:')));
      return SafeArea(top: false, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
        child: Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 18), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const Expanded(child: LText('筛选餐品', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            IconButton(tooltip: tr(context, '关闭'), onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close))]),
          Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 14),
            const LText('店铺', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 10),
            options({'': '全部店铺', ...visibleStores}, draftStore ?? '', (v) => draftStore = v.isEmpty ? null : v),
            if (!riceOnly) ...[
            const SizedBox(height: 22), const LText('主食分类', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 10),
            options({'all': '全部主食', ...stapleNames}, draftStaple, (v) => draftStaple = v),
            ],
            const SizedBox(height: 22), const LText('菜单来源', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 10),
            options({'merged': '官方库 + 个人库', 'official': '仅官方库', 'personal': '仅个人库'}, draftScope.name, (v) {
              draftScope = Scope.values.byName(v);
              if (draftStore != null && draftScope != Scope.merged && !draftStore!.startsWith('${draftScope.name}:')) draftStore = null;
            }),
            if (advanced) Padding(padding: const EdgeInsets.only(top: 14), child: TextButton.icon(
              onPressed: () => Navigator.pop(sheetContext, BrowseFilters(draftScope, draftStaple, draftStore, advanced: true, clearMeals: clearMeals)),
              icon: const Icon(Icons.checklist), label: const LText('筛选店铺和主餐'))),
            const SizedBox(height: 16),
          ]))),
          const Divider(height: 20), Row(children: [
            TextButton(onPressed: () => refresh(() { clearMeals = true; draftScope = Scope.merged; draftStaple = 'all'; draftStore = null; }), child: const LText('重置')),
            const SizedBox(width: 12), Expanded(child: FilledButton(
              onPressed: () => Navigator.pop(sheetContext, BrowseFilters(draftScope, draftStaple, draftStore, clearMeals: clearMeals)), child: const LText('应用筛选'))),
          ]),
        ]))));
    }));
}
