import 'dart:convert';
import 'dart:math';
import 'rice.dart';

enum Source { official, personal }
enum Scope { official, personal, merged }
enum MealMode { mainWithSides, balancedThree }
const kindNames = {'main': '主餐 / 套餐', 'side': '配菜 / 小食', 'drink': '饮品', 'dish': '单点菜', 'fee': '费用'};
const roleNames = {'staple': '主食', 'protein': '蛋白质类', 'vegetable': '蔬菜'};
String money(int cents) => (cents / 100).toStringAsFixed(2);
int? parseMoney(String value) {
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().split('.');
  return int.parse(parts[0]) * 100 + (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

class Place {
  final String id, name, area;
  const Place(this.id, this.name, this.area);
  factory Place.fromJson(Map<String, dynamic> j) => Place(j['id'], j['name'], j['area']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'area': area};
}

class Food {
  final String id, name;
  const Food(this.id, this.name);
  factory Food.fromJson(Map<String, dynamic> j) => Food(j['id'], j['name']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class Offer {
  final String id, placeId, name, portion, updatedAt;
  final int priceCents;
  final Set<String> roles, foodIds;
  final bool available, ingredientsKnown, example;
  final String kind, window, channel, notes, evidence, observedAt, photo;
  final bool addonOnly, alcohol;
  const Offer({required this.id, required this.placeId, required this.name,
    required this.portion, required this.priceCents, required this.roles,
    required this.foodIds, required this.updatedAt, this.available = true,
    this.ingredientsKnown = false, this.example = false, this.kind = 'dish',
    this.window = '', this.channel = 'regular', this.notes = '', this.evidence = '',
    this.photo = '', this.observedAt = '', this.addonOnly = false, this.alcohol = false});
  factory Offer.fromJson(Map<String, dynamic> j) => Offer(id: j['id'], placeId: j['placeId'],
    name: j['name'], portion: j['portion'], priceCents: j['priceCents'],
    roles: Set<String>.from(j['roles']), foodIds: Set<String>.from(j['foodIds']),
    updatedAt: j['updatedAt'], available: j['available'],
    ingredientsKnown: j['ingredientsKnown'], example: j['example'],
    kind: j['kind'] ?? 'dish', window: j['window'] ?? '', channel: j['channel'] ?? 'regular',
    notes: j['notes'] ?? '', evidence: j['evidence'] ?? '', observedAt: j['observedAt'] ?? '',
    photo: j['photo'] ?? '', addonOnly: j['addonOnly'] ?? false, alcohol: j['alcohol'] ?? false);
  Map<String, dynamic> toJson() => {'id': id, 'placeId': placeId, 'name': name,
    'portion': portion, 'priceCents': priceCents, 'roles': roles.toList()..sort(),
    'foodIds': foodIds.toList()..sort(), 'updatedAt': updatedAt,
    'available': available, 'ingredientsKnown': ingredientsKnown, 'example': example,
    'kind': kind, 'window': window, 'channel': channel, 'notes': notes, 'evidence': evidence,
    'photo': photo, 'observedAt': observedAt, 'addonOnly': addonOnly, 'alcohol': alcohol};
}

class MenuDb {
  final Source source;
  final int revision;
  final List<Place> places;
  final List<Food> foods;
  final List<Offer> offers;
  final List<RicePlan> ricePlans;
  const MenuDb({required this.source, required this.revision, required this.places,
    required this.foods, required this.offers, this.ricePlans = const []});
  factory MenuDb.empty(Source source) => MenuDb(source: source, revision: 1, places: [], foods: [], offers: []);
  factory MenuDb.decode(String text, Source expected) {
    if (text.length > 12000000) throw const FormatException('数据包超过 12 MB');
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (![1, 2, 3].contains(j['schemaVersion']) || j['source'] != expected.name) {
      throw const FormatException('数据版本或库类型不匹配');
    }
    final db = MenuDb(source: expected, revision: j['revision'],
      ricePlans: ((j['ricePlans'] ?? []) as List).map((v) => RicePlan.fromJson(Map<String,dynamic>.from(v))).toList(),
      places: (j['places'] as List).map((v) => Place.fromJson(Map<String,dynamic>.from(v))).toList(),
      foods: (j['foods'] as List).map((v) => Food.fromJson(Map<String,dynamic>.from(v))).toList(),
      offers: (j['offers'] as List).map((v) => Offer.fromJson(Map<String,dynamic>.from(v))).toList());
    db.validate();
    return db;
  }
  void validate() {
    if (offers.fold<int>(0, (n, o) => n + o.photo.length) > 10000000) throw const FormatException('照片总量超过10MB，请移除部分照片');
    void ids(List<String> values) {
      if (values.any((s) => s.trim().isEmpty) || values.toSet().length != values.length) {
        throw const FormatException('编号为空或重复');
      }
    }
    ids(ricePlans.map((p) => p.id).toList());
    if (ricePlans.length > 100) throw const FormatException('套餐模板最多100个');
    for (final plan in ricePlans) { plan.validate(); }
    ids(places.map((e) => e.id).toList()); ids(foods.map((e) => e.id).toList()); ids(offers.map((e) => e.id).toList());
    if (revision < 1 || offers.length > 500 || places.length > 200 || foods.length > 2000) {
      throw const FormatException('版本无效或超过原型容量（500 道菜）');
    }
    if (places.any((p) => p.name.trim().isEmpty) || foods.any((f) => f.name.trim().isEmpty)) {
      throw const FormatException('店铺或食材名称为空');
    }
    final placeIds = places.map((e) => e.id).toSet(), foodIds = foods.map((e) => e.id).toSet();
    for (final o in offers) {
      if (o.photo.length > 400000 || (o.photo.isNotEmpty && base64Decode(o.photo).length > 300000)) throw const FormatException('照片过大或格式无效');
      if (!placeIds.contains(o.placeId) || !foodIds.containsAll(o.foodIds) ||
          o.priceCents <= 0 || o.priceCents > 10000000 || o.name.trim().isEmpty ||
          o.portion.trim().isEmpty || !kindNames.containsKey(o.kind) || !['regular', 'douyin'].contains(o.channel) ||
          !roleNames.keys.toSet().containsAll(o.roles) ||
          (o.alcohol && o.kind != 'drink') || (o.addonOnly && o.kind != 'side') ||
          DateTime.tryParse(o.updatedAt) == null || (o.ingredientsKnown && o.foodIds.isEmpty)) {
        throw FormatException('菜品 ${o.id} 的关联、价格、分类或日期无效');
      }
    }
  }
  String encode() => const JsonEncoder.withIndent('  ').convert({'schemaVersion': 3,
    'ricePlans': ricePlans.map((p) => p.toJson()).toList(),
    'source': source.name, 'revision': revision, 'places': places.map((e) => e.toJson()).toList(),
    'foods': foods.map((e) => e.toJson()).toList(), 'offers': offers.map((e) => e.toJson()).toList()});
}

class Entry {
  final Offer offer;
  final MenuDb db;
  const Entry(this.offer, this.db);
  String get key => '${db.source.name}:${offer.id}';
  String get placeKey => '${db.source.name}:${offer.placeId}';
  Place get place => db.places.firstWhere((p) => p.id == offer.placeId);
  Set<String> get foodNames => db.foods.where((f) => offer.foodIds.contains(f.id)).map((f) => f.name).toSet();
  String get fingerprint => jsonEncode({'offer': offer.toJson(), 'place': place.toJson(),
    'foods': foodNames.toList()..sort()});
}
List<Entry> entries(MenuDb official, MenuDb personal, Scope scope) => [
  if (scope != Scope.personal) ...official.offers.map((o) => Entry(o, official)),
  if (scope != Scope.official) ...personal.offers.map((o) => Entry(o, personal)),
];

class MealRequest {
  final int budget;
  final bool samePlace;
  final Set<String> excludedFoods;
  final List<Entry?> previous;
  final Set<int> locked;
  final MealMode mode;
  final int extras;
  final bool allowDeals;
  const MealRequest({required this.budget, this.samePlace = true,
    this.excludedFoods = const {}, this.previous = const [null, null, null], this.locked = const {},
    this.mode = MealMode.balancedThree, this.extras = 2, this.allowDeals = false});
}
class MealResult {
  final List<Entry?>? meal;
  final String message;
  final bool limited;
  const MealResult(this.meal, this.message, {this.limited = false});
}

MealResult runRecommendation((List<Entry>, MealRequest, int) input) =>
    recommend(input.$1, input.$2, Random(input.$3));

/// Three purchased portions, not three alternative complete meals.
/// Hard constraints precede random weighting; locks always retain their snapshot.
MealResult recommend(List<Entry> pool, MealRequest request, Random random, {int nodeLimit = 250000}) {
  if (request.mode == MealMode.mainWithSides) return recommendMain(pool, request, random, nodeLimit: nodeLimit);
  if (request.budget <= 0 || request.previous.length != 3 || request.locked.any((i) => i < 0 || i > 2)) {
    return const MealResult(null, '预算或锁定参数无效');
  }
  bool allowed(Entry e) => e.offer.kind == 'dish' && e.offer.available && !e.offer.alcohol &&
    (request.allowDeals || e.offer.channel == 'regular') && (request.excludedFoods.isEmpty ||
    e.offer.ingredientsKnown && e.foodNames.intersection(request.excludedFoods).isEmpty);
  final byKey = {for (final e in pool) e.key: e};
  final chosen = List<Entry?>.filled(3, null);
  for (final index in request.locked) {
    final old = request.previous[index];
    final now = old == null ? null : byKey[old.key];
    if (old == null || now == null || old.fingerprint != now.fingerprint || !allowed(now)) {
      return const MealResult(null, '锁定项不在当前库中、价格或配料已变化、已下架或不符合忌口；请先解除对应锁定');
    }
    chosen[index] = old;
  }
  final fixed = chosen.whereType<Entry>().toList();
  if (fixed.fold<int>(0, (s, e) => s + e.offer.priceCents) > request.budget) {
    return const MealResult(null, '锁定项已超出预算；请提高预算或解除部分锁定');
  }
  if (fixed.map((e) => e.key).toSet().length != fixed.length ||
      request.samePlace && fixed.map((e) => e.placeKey).toSet().length > 1) {
    return const MealResult(null, '锁定项重复或来自不同店铺，与当前条件冲突');
  }
  final candidates = pool.where(allowed).where((e) => e.offer.priceCents <= request.budget).toList()..shuffle(random);
  final slots = [for (var i = 0; i < 3; i++) if (!request.locked.contains(i)) i];
  if (slots.isEmpty) return const MealResult(null, '三个组成项都已锁定；请先解锁需要更换的一项');
  final oldKeys = request.previous.whereType<Entry>().map((e) => e.key).toSet();
  List<Entry>? best;
  var bestRank = -1.0, nodes = 0;
  bool limited = false;
  void search(int depth, int spent) {
    if (nodes++ >= nodeLimit) { limited = true; return; }
    if (depth == slots.length) {
      final meal = chosen.cast<Entry>();
      if (!meal.expand((e) => e.offer.roles).toSet().containsAll(roleNames.keys)) return;
      final keys = meal.map((e) => e.key).toSet();
      if (oldKeys.length == 3 && keys.containsAll(oldKeys)) return;
      // Prefer fewer stores and varied ingredients; weighted randomness still allows exploration.
      final variety = meal.expand((e) => e.foodNames).toSet().length;
      final stores = meal.map((e) => e.placeKey).toSet().length;
      final weight = 1.0 + variety * .15 + (3 - stores) * .8;
      final rank = pow(random.nextDouble(), 1 / weight).toDouble();
      if (rank > bestRank) { bestRank = rank; best = List<Entry>.of(meal); }
      return;
    }
    final slot = slots[depth];
    for (final e in candidates) {
      if (limited) break;
      if (spent + e.offer.priceCents > request.budget || chosen.any((c) => c?.key == e.key) ||
          request.samePlace && chosen.whereType<Entry>().any((c) => c.placeKey != e.placeKey)) continue;
      chosen[slot] = e;
      search(depth + 1, spent + e.offer.priceCents);
      chosen[slot] = null;
    }
  }
  search(0, fixed.fold<int>(0, (s, e) => s + e.offer.priceCents));
  if (best != null) return MealResult(best, limited ? '已找到预算内搭配；大菜单搜索达到上限' : '已搭配主食、蛋白质类和蔬菜；价格为库内标价', limited: limited);
  return MealResult(null, limited ? '搜索达到上限，尚未找到组合；请缩小菜单范围后重试' :
    '当前条件下没有新的完整组合。可提高预算、允许跨店、增加菜品或解锁部分选项；原结果已保留', limited: limited);
}

/// Slot 0 is one complete purchased main; slots 1/2 are optional extras.
/// Included rice/vegetables are notes, never synthetic zero-price offers.
MealResult recommendMain(List<Entry> pool, MealRequest r, Random random, {int nodeLimit = 250000}) {
  if (r.budget <= 0 || r.previous.length != 3 || r.extras < 0 || r.extras > 2 ||
      r.locked.any((i) => i < 0 || i > 2)) return const MealResult(null, '预算或锁定参数无效');
  bool allowed(Entry e) => e.offer.available && !e.offer.alcohol &&
      (r.allowDeals || e.offer.channel == 'regular') &&
      (r.excludedFoods.isEmpty || e.offer.ingredientsKnown && e.foodNames.intersection(r.excludedFoods).isEmpty);
  bool isExtra(Entry e) => ['side', 'drink'].contains(e.offer.kind);
  final current = {for (final e in pool) e.key: e};
  final chosen = List<Entry?>.filled(3, null);
  for (final i in r.locked) {
    final old = r.previous[i], now = current[r.previous[i]?.key];
    if (old == null || now == null || old.fingerprint != now.fingerprint || !allowed(now)) {
      return const MealResult(null, '锁定项不在当前库、已变更、已下架或不符合当前价格 / 忌口条件；请先解锁');
    }
    if (i == 0 ? old.offer.kind != 'main' : !isExtra(old)) {
      return const MealResult(null, '锁定项与主餐 / 配菜位置不符，请先解锁再更换搭配方式');
    }
    chosen[i] = old;
  }
  final fixed = chosen.whereType<Entry>().toList();
  if (fixed.fold<int>(0, (s, e) => s + e.offer.priceCents) > r.budget) return const MealResult(null, '锁定项已超预算，请提高预算或解除部分锁定');
  if (chosen.skip(1).whereType<Entry>().length > r.extras) return const MealResult(null, '锁定配菜数量超过新上限，请先解除部分锁定');
  if (r.samePlace && fixed.map((e) => e.placeKey).toSet().length > 1) return const MealResult(null, '锁定项来自不同饭店，请解锁或允许跨店');
  if (r.locked.length == 3) return const MealResult(null, '三个组成项都已锁定；请先解锁需要更换的一项');
  final eligible = pool.where(allowed).where((e) => e.offer.priceCents <= r.budget).toList()..shuffle(random);
  final mains = eligible.where((e) => e.offer.kind == 'main').toList();
  final sides = eligible.where(isExtra).toList();
  final oldKeys = r.previous.whereType<Entry>().map((e) => e.key).toSet();
  List<Entry?>? best;
  int bestCount = -1, visits = 0;
  double bestRank = -1;
  bool limited = false;
  void visit(int slot) {
    if (++visits > nodeLimit) { limited = true; return; }
    final items = chosen.whereType<Entry>().toList();
    if (items.fold<int>(0, (s, e) => s + e.offer.priceCents) > r.budget ||
        chosen.skip(1).whereType<Entry>().length > r.extras ||
        items.map((e) => e.key).toSet().length != items.length ||
        items.map((e) => '${e.placeKey}:${e.offer.window}:${e.offer.name}').toSet().length != items.length ||
        items.where((e) => e.offer.kind == 'drink').length > 1 ||
        r.samePlace && items.map((e) => e.placeKey).toSet().length > 1) return;
    final main = chosen[0];
    if (main != null && items.any((e) => e.offer.addonOnly &&
        (e.placeKey != main.placeKey || e.offer.window != main.offer.window))) return;
    if (slot == 3) {
      if (main == null) return;
      final keys = items.map((e) => e.key).toSet();
      // Neither a permutation nor simply removing an old extra is a new recommendation.
      if (oldKeys.isNotEmpty && oldKeys.containsAll(keys)) return;
      final rank = random.nextDouble();
      if (items.length > bestCount || items.length == bestCount && rank > bestRank) {
        bestCount = items.length; bestRank = rank; best = [...chosen];
      }
      return;
    }
    if (r.locked.contains(slot)) { visit(slot + 1); return; }
    for (final e in slot == 0 ? mains : sides) {
      if (limited) break;
      chosen[slot] = e;
      visit(slot + 1);
      chosen[slot] = null;
    }
    if (slot > 0 && !limited) visit(slot + 1);
  }
  visit(0);
  if (best == null) return MealResult(null, limited ? '搜索达到上限，尚未找到新搭配；原结果保留' :
    '没有符合当前预算、锁定和配菜条件的新搭配；原结果保留。可减少配菜、提高预算或解除锁定', limited: limited);
  final extraCount = best!.skip(1).whereType<Entry>().length;
  return MealResult(best, '1 份主餐 + $extraCount 项配菜 / 饮品。${extraCount < r.extras ? '可选配菜未配满，不强行凑单。' : ''}'
    '${best!.whereType<Entry>().any((e) => e.offer.channel == 'douyin') ? '含抖音价，须符合商家核销条件。' : ''}'
    '${limited ? '搜索达到上限，返回已找到的有效搭配。' : ''}价格依拍摄记录，不代表实时售价。', limited: limited);
}
