import 'dart:math';

// Older rice plans recorded only a location. Resolve only a unique store;
// ambiguous or missing locations must not enable cross-store snacks.
String? riceStoreKey(RicePlan plan, Map<String,String> stores) {
  if (plan.storeKey.isNotEmpty) return stores.containsKey(plan.storeKey) ? plan.storeKey : null;
  final matches = stores.entries.where((e) => plan.location == e.value ||
    RegExp('^${RegExp.escape(e.value)}\\s*[0-9一二三四五六七八九十]+号窗口').hasMatch(plan.location)).toList();
  return matches.length == 1 ? matches.single.key : null;
}

// Recorded ingredients: eggs count as vegetarian; any meat counts as meat.
// This fallback is scoped to the shipped window, including older saved menus.
const _sfVegetarian = {'韭菜鸡蛋', '蘑菇油菜', '卤鸡蛋', '西红柿炒鸡蛋',
  '清炒菜芯', '干炸蘑菇', '素炒菠菜', '土豆丝'};
const _sfMeat = {'火腿鸡蛋', '糖醋里脊', '黄焖鸡', '爆炒鸡柳', '小酥肉',
  '粉丝娃娃菜', '蟹棒', '孜然炒肉', '港式烧肉', '干锅土豆', '豆角肉丝',
  '清炒双花', '烤肠', '干锅丸子', '椒麻鸡', '肉沫茄子', '鱼排（无刺）',
  '贵妃荔枝鸡', '溜肝尖', '锅包肉', '杏鲍菇炒肉', '鸡腿', '大烩菜', '家常豆腐'};
String? riceDishType(RicePlan plan, String name) {
  if (plan.dishTypes.containsKey(name)) return plan.dishTypes[name];
  if (plan.storeKey == 'official:sf' && plan.id == 'sf_w1_alacarte') {
    if (_sfVegetarian.contains(name)) return 'veg';
    if (_sfMeat.contains(name)) return 'meat';
  }
  return null;
}

/// Three cooked dishes: legacy fixed price or rice base plus dish prices.
class RicePlan {
  final String id, name, location, storeKey;
  final int priceCents;
  final Map<String, int> dishPrices;
  final Map<String, String> dishPhotos;
  final Map<String, String> dishTypes;
  final bool riceRefill;
  bool get pricedByDish => dishPrices.isNotEmpty;
  int totalPrice(Iterable<String?> dishes, {List<int>? quantities, int baseQuantity = 1}) {
    final rows = dishes.toList();
    final counts = quantities ?? List.filled(rows.length, 1);
    if (baseQuantity < 1 || baseQuantity > 99 || counts.length != rows.length || counts.any((n) => n < 1 || n > 99)) throw ArgumentError('Invalid quantity');
    return priceCents * baseQuantity + (pricedByDish ? List.generate(rows.length, (i) => rows[i] == null ? 0 : dishPrices[rows[i]]! * counts[i]).fold<int>(0, (a,b) => a+b) : 0);
  }
  final List<String> labels;
  final List<List<String>> options;
  const RicePlan({required this.id, required this.name, required this.location,
    this.dishTypes = const {}, this.storeKey = '', this.dishPrices = const {}, this.dishPhotos = const {}, this.riceRefill = false, required this.priceCents, required this.labels, required this.options});
  factory RicePlan.fromJson(Map<String, dynamic> j) => RicePlan(id: j['id'],
    dishTypes: Map<String,String>.from(j['dishTypes'] ?? {}),
    dishPrices: Map<String,int>.from(j['dishPrices'] ?? {}),
    dishPhotos: Map<String,String>.from(j['dishPhotos'] ?? {}), riceRefill: j['riceRefill'] == true,
    storeKey: j['storeKey'] ?? '', name: j['name'], location: j['location'], priceCents: j['priceCents'],
    labels: List<String>.from(j['labels']),
    options: (j['options'] as List).map((v) => List<String>.from(v)).toList());
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'location': location,
    'dishTypes': dishTypes, 'dishPrices': dishPrices, 'dishPhotos': dishPhotos, 'riceRefill': riceRefill,
    'storeKey': storeKey, 'priceCents': priceCents, 'labels': labels, 'options': options};
  void validate() {
    if (dishTypes.values.any((v) => v != 'veg' && v != 'meat')) {
      throw const FormatException('菜品分类必须为素或荤');
    }
    if (pricedByDish && (dishPrices.values.any((p) => p <= 0 || p > 10000000) ||
        options.expand((v) => v).any((n) => !dishPrices.containsKey(n)))) {
      throw const FormatException('每道可选菜都需要有效价格');
    }
    if (dishPhotos.values.any((p) => !RegExp(r'^assets/rice/dish_[0-9]{2}\.webp$').hasMatch(p))) {
      throw const FormatException('菜品图片路径无效');
    }
    if (id.trim().isEmpty || name.trim().isEmpty || location.trim().isEmpty ||
        priceCents <= 0 || priceCents > 10000000 || labels.length != 3 ||
        labels.any((v) => v.trim().isEmpty) || options.length != 3 ||
        options.any((v) => v.length > 100 || v.any((n) => n.trim().isEmpty) || v.toSet().length != v.length)) {
      throw const FormatException('米饭套餐需有名称、位置、有效总价和三组菜品，每组最多100个不重复菜名');
    }
  }
}

class RiceResult {
  final List<String?>? dishes;
  final String message;
  const RiceResult(this.dishes, this.message);
}

RiceResult randomRice(RicePlan plan, int budget, List<String?> previous,
    Set<int> locked, Random random, {bool freeSelection = false, int? meatCount, List<int>? quantities, int baseQuantity = 1, int limit = 12000, double Function(List<String>)? score}) {
  plan.validate();
  if (meatCount != null && (meatCount < 0 || meatCount > 2)) return const RiceResult(null, '请选择3素、2素1荤或1素2荤；3荤请手选');
  if (budget < plan.priceCents) return const RiceResult(null, '套餐总价超出预算，原选择保留');
  final length = previous.length;
  final free = plan.pricedByDish && freeSelection;
  final options = free ? List.generate(length, (_) => plan.options.expand((r) => r).toSet().toList()) : plan.options;
  if (length < 1 || length > 20 || (!free && length != 3) || locked.any((i) => i < 0 || i >= length)) {
    return const RiceResult(null, '请重新选择菜品');
  }
  if (plan.options.any((v) => v.isEmpty)) return const RiceResult(null, '可选成品菜尚未补齐，请先维护套餐菜名');
  for (final i in locked) {
    if (!options[i].contains(previous[i])) return const RiceResult(null, '锁定的菜已不在菜单里，请先解锁');
  }
  if (locked.length == length) return const RiceResult(null, '菜品都已锁定，请先解锁一道菜');
  final chosen = List<String?>.filled(length, null);
  List<String?>? result;
  int visited = 0, count = 0;
  double totalWeight = 0;
  bool limited = false;
  final old = previous.whereType<String>().toSet();
  final choices = options.map((v) => [...v]..shuffle(random)).toList();
  final counts = quantities ?? List.filled(length, 1);
  plan.totalPrice(chosen, quantities: counts, baseQuantity: baseQuantity);
  final used = <String>{};
  int evaluated = 0;
  void visit(int slot, int cost) {
    if (++visited > limit) { limited = true; return; }
    if (cost > budget) return;
    if (slot == length) {
      if (meatCount != null && (chosen.any((n) => riceDishType(plan, n!) == null) ||
          chosen.where((n) => riceDishType(plan, n!) == 'meat').length != meatCount)) return;
      if (old.length == length && old.containsAll(chosen)) return;
      if (++evaluated >= 256) limited = true;
      if (score == null) {
        if (random.nextInt(++count) == 0) result = [...chosen];
      } else {
        final weight = score(chosen.cast<String>());
        if (!weight.isFinite || weight <= 0) throw ArgumentError('Invalid rice weight');
        totalWeight += weight;
        if (random.nextDouble() * totalWeight < weight) result = [...chosen];
      }
      return;
    }
    for (final name in locked.contains(slot) ? [previous[slot]!] : choices[slot]) {
      if (limited) break;
      if (!used.add(name)) continue;
      chosen[slot] = name;
      visit(slot + 1, cost + (plan.pricedByDish ? plan.dishPrices[name]! * counts[slot] : 0));
      used.remove(name);
      chosen[slot] = null;
    }
  }
  visit(0, plan.priceCents * baseQuantity);
  return RiceResult(result, result != null
    ? '已选好，锁定的菜保持不变。'
    : '暂无其他合适搭配，已保留当前选择。');
}
