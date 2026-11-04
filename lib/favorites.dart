import 'dart:convert';
import 'package:crypto/crypto.dart';
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
  static const maxMeals = 500;
  static const maxStorageBytes = 10 * 1024 * 1024;
  final SharedPreferences preferences;
  List<FavoriteMeal> meals;
  bool enabled;
  bool recoveryRequired = false;
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
  static Future<FavoriteStore> loadAvailable(SharedPreferences preferences) async {
    try { return await load(preferences); }
    on FormatException { return FavoriteStore._(preferences, [], false)..recoveryRequired = true; }
    on TypeError { return FavoriteStore._(preferences, [], false)..recoveryRequired = true; }
  }
  Future<void> _update(List<FavoriteMeal> Function() nextMeals, bool Function() nextEnabled, {bool enforceLimits = false}) {
    final task = _pending.then((_) async {
      if (recoveryRequired) throw StateError('收藏数据需要恢复，请先导出原始数据；未覆盖原记录');
      final next = nextMeals(), flag = nextEnabled();
      if (enforceLimits && next.length > maxMeals && next.length > meals.length) {
        throw const FormatException('最多保存500条收藏，请先删除部分记录');
      }
      final encoded = jsonEncode({'version': 1, 'enabled': flag,
        'meals': next.map((m) => m.toJson()).toList()});
      final previous = preferences.getString(storageKey) ?? '';
      if (enforceLimits && utf8.encode(encoded).length > maxStorageBytes &&
          utf8.encode(encoded).length > utf8.encode(previous).length) {
        throw const FormatException('收藏超过10MB，请先删除部分含照片的记录');
      }
      final ok = await preferences.setString(storageKey, encoded);
      if (!ok) throw StateError('喜爱记录保存失败，原记录保留');
      meals = next; enabled = flag; _reindex();
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
  Future<void> save(FavoriteMeal meal) {
    if (meal.items.isEmpty || meal.storeKey.isEmpty) throw const FormatException('请先选好这一顿');
    return _update(() => [meal, ...meals.where((m) => m.id != meal.id)], () => enabled, enforceLimits: true);
  }
  Future<void> remove(String id) => _update(() => meals.where((m) => m.id != id).toList(), () => enabled);
  Future<void> setEnabled(bool value) => _update(() => [...meals], () => value);
  /// Only called after the user has exported the original data and confirmed.
  String? _resetOriginal;
  Future<void> resetAfterBackup() {
    final task = _pending.then((_) async {
      // Discard optimistic plugin cache updates from any failed disk write.
      await preferences.reload();
      // Pin this reset's source across retries, even if a failed native commit changed its cache.
      final original = _resetOriginal ??= preferences.getString(storageKey);
      if (original != null) {
        const firstKey = '$storageKey.recovery';
        final first = preferences.getString(firstKey);
        final key = first == null || first == original ? firstKey :
            '$firstKey.${sha256.convert(utf8.encode(original))}';
        final backedUp = await preferences.setString(key, original);
        if (!backedUp) throw StateError('备份失败，原记录保留');
      }
      final ok = await preferences.setString(storageKey,
        jsonEncode({'version': 1, 'enabled': false, 'meals': []}));
      if (!ok) throw StateError('重置失败，原记录保留');
      _resetOriginal = null;
      meals = []; enabled = false; recoveryRequired = false; _reindex();
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
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
