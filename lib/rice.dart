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
  int totalPrice(Iterable<String?> dishes) => priceCents + (pricedByDish
    ? dishes.whereType<String>().fold<int>(0, (sum, name) => sum + dishPrices[name]!) : 0);
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
    Set<int> locked, Random random, {int? meatCount, int limit = 100000, double Function(List<String>)? score}) {
  plan.validate();
  if (meatCount != null && (meatCount < 0 || meatCount > 2)) return const RiceResult(null, '请选择3素、2素1荤或1素2荤；3荤请手选');
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
  double totalWeight = 0;
  bool limited = false;
  final old = previous.whereType<String>().toSet();
  final choices = plan.options.map((v) => [...v]..shuffle(random)).toList();
  void visit(int slot) {
    if (++visited > limit) { limited = true; return; }
    if (plan.totalPrice(chosen) > budget) return;
    if (slot == 3) {
      if (meatCount != null && (chosen.any((n) => riceDishType(plan, n!) == null) ||
          chosen.where((n) => riceDishType(plan, n!) == 'meat').length != meatCount)) return;
      if (old.length == 3 && old.containsAll(chosen)) return;
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
      if (chosen.take(slot).contains(name)) continue;
      chosen[slot] = name;
      visit(slot + 1);
      chosen[slot] = null;
    }
  }
  visit(0);
  return RiceResult(result, result != null
    ? '${plan.pricedByDish ? '菜价合计加米饭，锁定菜位保持不变。' : '按套餐总价计费，锁定菜位保持不变。'}${limited ? '搜索达到上限，返回已找到的组合。' : ''}'
    : limited ? '搜索达到上限，暂未找到新组合；原选择保留' : '没有符合预算和锁定条件的新组合；原选择保留');
}
