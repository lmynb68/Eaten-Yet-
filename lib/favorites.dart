import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'photos.dart';
import 'rice.dart';

String riceDishKey(RicePlan plan, String name) => jsonEncode(['rice', plan.storeKey, plan.location, name]);

class FavoriteItem {
  final String key, name, asset, photo;
  final int price;
  const FavoriteItem(this.key, this.name, this.price, {this.asset = '', this.photo = ''});
  factory FavoriteItem.entry(Entry e) => FavoriteItem(e.key, e.offer.name, e.offer.priceCents, asset: dishAssetForEntry(e), photo: e.offer.photo);
  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'price': price, 'asset': asset, 'photo': photo};
  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(j['key'], j['name'], j['price'], asset: j['asset'] ?? '', photo: j['photo'] ?? '');
}

class FavoriteMeal {
  final String storeKey, storeName, kind, savedAt, baseLabel;
  final List<FavoriteItem> items;
  final int ricePrice;
  const FavoriteMeal({required this.storeKey, required this.storeName, required this.kind,
    required this.savedAt, required this.items, this.ricePrice = 0, this.baseLabel = '米饭'});
  String get id => jsonEncode([storeKey, kind, items.map((i) => i.key).toList()..sort()]);
  int get total => ricePrice + items.fold<int>(0, (sum, item) => sum + item.price);
  Map<String, dynamic> toJson() => {'storeKey': storeKey, 'storeName': storeName, 'kind': kind,
    'savedAt': savedAt, 'items': items.map((i) => i.toJson()).toList(), 'ricePrice': ricePrice, 'baseLabel': baseLabel};
  factory FavoriteMeal.fromJson(Map<String, dynamic> j) => FavoriteMeal(storeKey: j['storeKey'],
    storeName: j['storeName'], kind: j['kind'], savedAt: j['savedAt'], ricePrice: j['ricePrice'] ?? 0, baseLabel: j['baseLabel'] ?? '米饭',
    items: (j['items'] as List).map((i) => FavoriteItem.fromJson(Map<String, dynamic>.from(i))).toList());
}

/// Local-only, reversible learning. Duplicate saves do not increase evidence.
class FavoriteStore {
  static const storageKey = 'eat_what.favorites.v1';
  final SharedPreferences preferences;
  List<FavoriteMeal> meals;
  bool enabled;
  Future<void> _pending = Future<void>.value();
  final Map<String, int> _dishCounts = {}, _pairCounts = {};
  FavoriteStore._(this.preferences, this.meals, this.enabled) { _reindex(); }
  String _pairKey(String a, String b) => jsonEncode([a, b]..sort());
  void _reindex() {
    _dishCounts.clear(); _pairCounts.clear();
    for (final meal in meals) {
      final keys = meal.items.map((i) => i.key).toSet().toList();
      for (final key in keys) { _dishCounts[key] = (_dishCounts[key] ?? 0) + 1; }
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final key = _pairKey(keys[i], keys[j]);
          _pairCounts[key] = (_pairCounts[key] ?? 0) + 1;
        }
      }
    }
  }
  static Future<FavoriteStore> load(SharedPreferences preferences) async {
    final text = preferences.getString(storageKey);
    if (text == null) return FavoriteStore._(preferences, [], true);
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['version'] != 1) throw const FormatException('喜爱记录版本不支持，未修改原数据');
    return FavoriteStore._(preferences, (j['meals'] as List)
      .map((m) => FavoriteMeal.fromJson(Map<String, dynamic>.from(m))).toList(), j['enabled'] == true);
  }
  Future<void> _update(List<FavoriteMeal> Function() nextMeals, bool Function() nextEnabled) {
    final task = _pending.then((_) async {
      final next = nextMeals(), flag = nextEnabled();
      final ok = await preferences.setString(storageKey, jsonEncode({'version': 1, 'enabled': flag,
        'meals': next.map((m) => m.toJson()).toList()}));
      if (!ok) throw StateError('喜爱记录保存失败，原记录保留');
      meals = next; enabled = flag; _reindex();
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
  Future<void> save(FavoriteMeal meal) {
    if (meal.items.isEmpty || meal.storeKey.isEmpty) throw const FormatException('请先选好这一顿');
    return _update(() => [meal, ...meals.where((m) => m.id != meal.id)], () => enabled);
  }
  Future<void> remove(String id) => _update(() => meals.where((m) => m.id != id).toList(), () => enabled);
  Future<void> setEnabled(bool value) => _update(() => [...meals], () => value);
  double dishWeight(String key) => !enabled ? 1 : 1 + min(2.0, (_dishCounts[key] ?? 0) * .25);
  double pairCoefficient(String a, String b) => !enabled ? 1 : 1 + min(1.0, (_pairCounts[_pairKey(a, b)] ?? 0) * .15);
  double score(Iterable<String> input) {
    final keys = input.toSet().toList();
    if (!enabled || keys.isEmpty) return 1;
    final dishes = keys.map(dishWeight).reduce((a, b) => a * b);
    double pairs = 1; int count = 0;
    for (var i = 0; i < keys.length; i++) {
      for (var j = i + 1; j < keys.length; j++) { pairs *= pairCoefficient(keys[i], keys[j]); count++; }
    }
    // Geometric means bound the score at 6 regardless of meal size.
    return pow(dishes, 1 / keys.length).toDouble() * (count == 0 ? 1 : pow(pairs, 1 / count).toDouble());
  }
}

T weightedPick<T>(List<T> choices, Random random, double Function(T) score) {
  if (choices.isEmpty) throw ArgumentError('No eligible choices');
  var total = 0.0;
  T selected = choices.first;
  for (final item in choices) {
    final weight = score(item);
    if (!weight.isFinite || weight <= 0) throw ArgumentError('Weight must be finite and positive');
    total += weight;
    if (random.nextDouble() * total < weight) selected = item;
  }
  return selected;
}
