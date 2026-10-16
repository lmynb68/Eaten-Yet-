import 'dart:math';

// Older rice plans recorded only a location. Resolve only a unique store;
// ambiguous or missing locations must not enable cross-store snacks.
String? riceStoreKey(RicePlan plan, Map<String,String> stores) {
  if (plan.storeKey.isNotEmpty) return stores.containsKey(plan.storeKey) ? plan.storeKey : null;
  final matches = stores.entries.where((e) => plan.location == e.value ||
    RegExp('^${RegExp.escape(e.value)}\\s*[0-9一二三四五六七八九十]+号窗口').hasMatch(plan.location)).toList();
  return matches.length == 1 ? matches.single.key : null;
}

/// A fixed-price rice meal: three cooked-dish slots, not recipe ingredients.
class RicePlan {
  final String id, name, location, storeKey;
  final int priceCents;
  final List<String> labels;
  final List<List<String>> options;
  const RicePlan({required this.id, required this.name, required this.location,
    this.storeKey = '', required this.priceCents, required this.labels, required this.options});
  factory RicePlan.fromJson(Map<String, dynamic> j) => RicePlan(id: j['id'],
    storeKey: j['storeKey'] ?? '', name: j['name'], location: j['location'], priceCents: j['priceCents'],
    labels: List<String>.from(j['labels']),
    options: (j['options'] as List).map((v) => List<String>.from(v)).toList());
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'location': location,
    'storeKey': storeKey, 'priceCents': priceCents, 'labels': labels, 'options': options};
  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty || location.trim().isEmpty ||
        priceCents <= 0 || priceCents > 10000000 || labels.length != 3 ||
        labels.any((v) => v.trim().isEmpty) || options.length != 3 ||
        options.any((v) => v.length > 100 || v.any((n) => n.trim().isEmpty) || v.toSet().length != v.length)) {
      throw const FormatException('米饭套餐需有名称、位置、有效总价和三个菜位，每位最多100个不重复菜名');
    }
  }
}

class RiceResult {
  final List<String?>? dishes;
  final String message;
  const RiceResult(this.dishes, this.message);
}

RiceResult randomRice(RicePlan plan, int budget, List<String?> previous,
    Set<int> locked, Random random, {int limit = 100000}) {
  plan.validate();
  if (budget < plan.priceCents) return const RiceResult(null, '套餐总价超出预算，原选择保留');
  if (previous.length != 3 || locked.any((i) => i < 0 || i > 2)) {
    return const RiceResult(null, '菜位参数无效');
  }
  if (plan.options.any((v) => v.isEmpty)) return const RiceResult(null, '可选成品菜尚未补齐，请先维护套餐菜名');
  for (final i in locked) {
    if (!plan.options[i].contains(previous[i])) return const RiceResult(null, '锁定菜已不在这个菜位的菜单中，请先解锁');
  }
  if (locked.length == 3) return const RiceResult(null, '三个菜位都已锁定，请先解锁');
  final chosen = List<String?>.filled(3, null);
  List<String?>? result;
  int visited = 0, count = 0;
  bool limited = false;
  final old = previous.whereType<String>().toSet();
  final choices = plan.options.map((v) => [...v]..shuffle(random)).toList();
  void visit(int slot) {
    if (++visited > limit) { limited = true; return; }
    if (slot == 3) {
      if (old.length == 3 && old.containsAll(chosen)) return;
      if (random.nextInt(++count) == 0) result = [...chosen];
      return;
    }
    for (final name in locked.contains(slot) ? [previous[slot]!] : choices[slot]) {
      if (limited) break;
      if (chosen.take(slot).contains(name)) continue;
      chosen[slot] = name;
      visit(slot + 1);
      chosen[slot] = null;
    }
  }
  visit(0);
  return RiceResult(result, result != null
    ? '按套餐总价计费，锁定菜位保持不变。${limited ? '搜索达到上限，返回已找到的组合。' : ''}'
    : limited ? '搜索达到上限，暂未找到新组合；原选择保留' : '没有符合锁定条件的新组合；原选择保留');
}
