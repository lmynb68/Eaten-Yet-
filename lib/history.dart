import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'favorites.dart';

class MealHistory {
  final String id;
  final FavoriteMeal meal;
  final int stars;
  final String review;
  const MealHistory({required this.id, required this.meal, this.stars = 0, this.review = ''});
  Map<String, dynamic> toJson() => {'id': id, 'meal': meal.toJson(), 'stars': stars, 'review': review};
  factory MealHistory.fromJson(Map<String, dynamic> json) {
    final item = MealHistory(id: json['id'], meal: FavoriteMeal.fromJson(Map<String, dynamic>.from(json['meal'])),
      stars: json['stars'], review: json['review']);
    item.validate();
    return item;
  }
  void validate() {
    if (id.isEmpty || id.length > 200 || stars < 0 || stars > 5 || review.length > 2000 ||
        DateTime.tryParse(meal.savedAt) == null || meal.storeName.isEmpty || meal.items.isEmpty ||
        meal.items.length > 200 || meal.baseQuantity < 1 || meal.baseQuantity > 99 || meal.ricePrice < 0 || meal.ricePrice > 990000000 ||
        meal.items.any((i) => i.key.isEmpty || i.name.isEmpty || i.price < 0 || i.price > 10000000 || i.quantity < 1 || i.quantity > 99)) {
      throw const FormatException('历史记录格式不正确');
    }
  }
}

/// Personal meal snapshots, independent of favorites and menu revisions.
class HistoryStore {
  static const storageKey = 'eat_what.history.v1';
  static const maxBytes = 10 * 1024 * 1024;
  static const maxRecords = 2000;
  final SharedPreferences preferences;
  List<MealHistory> _records;
  List<MealHistory> get records => List.unmodifiable(_records);
  bool recoveryRequired;
  String? _recoveryRaw;
  Future<void> _pending = Future<void>.value();
  HistoryStore._(this.preferences, this._records, this.recoveryRequired);
  static List<MealHistory> decode(String text) {
    if (utf8.encode(text).length > maxBytes) throw const FormatException('历史备份超过10MB');
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['version'] != 1 || json['type'] != 'meal-history') throw const FormatException('历史记录格式不正确');
    final rows = (json['records'] as List).map((r) => MealHistory.fromJson(Map<String, dynamic>.from(r))).toList();
    if (rows.length > maxRecords || rows.map((r) => r.id).toSet().length != rows.length) throw const FormatException('历史记录格式不正确');
    return rows;
  }
  static Future<HistoryStore> load(SharedPreferences preferences) async {
    final raw = preferences.get(storageKey);
    try {
      if (raw != null && raw is! String) throw const FormatException('Invalid history type');
      return HistoryStore._(preferences, raw == null ? [] : decode(raw as String), false);
    } catch (_) {
      return HistoryStore._(preferences, [], true)
        .._recoveryRaw = raw is String ? raw : jsonEncode(raw);
    }
  }
  String export() => recoveryRequired ? (_recoveryRaw ?? '') : _encode(_records);
  static String _encode(List<MealHistory> rows) => jsonEncode({'version': 1, 'type': 'meal-history', 'records': rows.map((r) => r.toJson()).toList()});
  Future<void> _update(List<MealHistory> Function() change) {
    final task = _pending.then((_) async {
      if (recoveryRequired) throw StateError('历史读取失败，请先导出原始备份。');
      final rows = change();
      for (final row in rows) { row.validate(); }
      if (rows.length > maxRecords && rows.length > _records.length) throw const FormatException('历史记录已满，请先导出并删除部分记录。');
      final text = _encode(rows);
      if (utf8.encode(text).length > maxBytes) throw const FormatException('历史记录超过10MB，请先导出并删除部分记录。');
      if (!await preferences.setString(storageKey, text)) throw StateError('History save failed');
      _records = rows;
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
  Future<void> add(FavoriteMeal meal, {int stars = 0, String review = ''}) {
    final snapshot = FavoriteMeal.fromJson(jsonDecode(jsonEncode(meal.toJson())));
    final id = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    return _update(() => [MealHistory(id: id, meal: snapshot, stars: stars, review: review), ..._records]);
  }
  Future<void> edit(String id, int stars, String review) => _update(() => [for (final r in _records)
    if (r.id == id) MealHistory(id: r.id, meal: r.meal, stars: stars, review: review) else r]);
  Future<void> remove(String id) => _update(() => _records.where((r) => r.id != id).toList());
  Future<void> resetAfterBackup() {
    final task = _pending.then((_) async {
      if (!recoveryRequired) return;
      final raw = _recoveryRaw!;
      final backupKey = '$storageKey.recovery.${sha256.convert(utf8.encode(raw))}';
      if (!await preferences.setString(backupKey, raw)) {
        throw StateError('History backup failed');
      }
      if (!await preferences.setString(storageKey, _encode([]))) throw StateError('History reset failed');
      _records = [];
      recoveryRequired = false;
      _recoveryRaw = null;
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
  Future<void> import(String text) async {
    final incoming = decode(text);
    await _update(() {
      // A repeated import is harmless; preserve existing reviews on collisions.
      final ids = _records.map((r) => r.id).toSet();
      return [..._records, ...incoming.where((r) => !ids.contains(r.id))]
        ..sort((a, b) => b.meal.savedAt.compareTo(a.meal.savedAt));
    });
  }
}
