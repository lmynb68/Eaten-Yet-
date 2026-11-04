import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'rice.dart';

// SHA-256 of UTF-8 MenuDb.encode() for each shipped official catalog.
const shippedMenuDigests = <int, String>{
  1: 'f4502d8b89718f485aab9af6c8418ebe856d60309d5808674db3731fd624cb8e',
  4: '3d63c329da95c87f200771ed289d98202fa1f9bee07ad6b3f31969d985df55d3',
  5: 'a9224cc82af69e6f5220e5510a166db975176283336c06bfeec9500bd5977fd2',
  6: '7aca739bf820a8cfc750abf86a4066f55d54e477a8c1cca2c05bc6c4c98f0b20',
  7: 'c32916677daa54ca5278cd9e893a36b81419c470fb5356f1615efd01005227ae',
  8: '5c564a4e74fab5fb01d77f876f176e615efa2551a09c0b561052fe2eeaf988a2',
  9: 'fccc4a3dfdfc507681c07da9ed3eb07ce68328ee2114ef166d1f3f46ee5e578c',
};

class MenuRepository {
  static const storageKey = 'eat_what.campus.v1';
  final SharedPreferences preferences;
  MenuDb official, personal;
  Set<String> installedStoreIds;
  Future<void> _pending = Future<void>.value();
  MenuRepository(this.preferences, this.official, this.personal, {Set<String>? installed})
    : installedStoreIds = {...(installed ?? official.places.map((p) => p.id).toSet())};
  MenuDb get activeOfficial {
    final stores = {for (final p in official.places) 'official:${p.id}': p.name};
    return MenuDb(source: Source.official, revision: official.revision,
      places: official.places.where((p) => installedStoreIds.contains(p.id)).toList(),
      foods: official.foods,
      offers: official.offers.where((o) => installedStoreIds.contains(o.placeId)).toList(),
      ricePlans: official.ricePlans.where((p) {
        final key = riceStoreKey(p, stores);
        return key != null && installedStoreIds.contains(key.substring('official:'.length));
      }).toList());
  }
  // Recovery export deliberately avoids decoding or overwriting saved values.
  // This is a diagnostic snapshot, not a normal menu-library import package.
  static Future<String> exportRecoveryData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('eat_what.')).toList()..sort();
    return jsonEncode({'format': 'eat-what-recovery-v1',
      'values': {for (final key in keys) key: prefs.get(key)}});
  }
  static Future<MenuRepository> load({AssetBundle? assets}) async {
    final bundle = assets ?? rootBundle;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    final builtIn = MenuDb.decode(await bundle.loadString('assets/official.json'), Source.official);
    if (saved == null) return MenuRepository(prefs, builtIn, MenuDb.empty(Source.personal));
    final j = jsonDecode(saved) as Map<String, dynamic>;
    final old = _decodeStoredMenu(j['official'], Source.official);
    final upgrade = old.revision < builtIn.revision && await _matchesShippedMenu(old, bundle);
    final next = upgrade ? builtIn : old;
    return MenuRepository(prefs, next, _decodeStoredMenu(j['personal'], Source.personal),
      installed: j['installedStores'] == null ? null : Set<String>.from(j['installedStores']));
  }
  static Future<bool> _matchesShippedMenu(MenuDb old, AssetBundle bundle) async {
    if (old.revision != 3) {
      final expected = shippedMenuDigests[old.revision];
      return expected != null && sha256.convert(utf8.encode(old.encode())).toString() == expected;
    }
    // v3 was a subset of v4. A missing reference must not block startup.
    late final String text;
    try {
      text = await bundle.loadString('assets/official-v4.json');
    } catch (_) {
      return false;
    }
    final reference = MenuDb.decode(text, Source.official);
    return old.offers.length == 228 && old.places.length == 2 &&
      old.places.every((p) => reference.places.any((n) => jsonEncode(n.toJson()) == jsonEncode(p.toJson()))) &&
      jsonEncode(old.ricePlans.map((p) => p.toJson()).toList()) == jsonEncode(reference.ricePlans.map((p) => p.toJson()).toList()) &&
      jsonEncode(old.foods.map((f) => f.toJson()).toList()) == jsonEncode(reference.foods.map((f) => f.toJson()).toList()) &&
      old.offers.every((o) => reference.offers.any((n) => jsonEncode(n.toJson()) == jsonEncode(o.toJson())));
  }
  static MenuDb _decodeStoredMenu(String text, Source source) {
    // Older builds could persist indented JSON larger than the import limit.
    if (text.length > MenuDb.maxJsonLength) return MenuDb.fromStoredJson(text, source);
    return MenuDb.decode(text, source);
  }
  static String _encodeForStorage(MenuDb menu) {
    final text = menu.encode(compact: true);
    if (text.length > MenuDb.maxJsonLength) {
      throw const FormatException('菜单保存后超过容量上限，请减少内容后重试');
    }
    return text;
  }
  Future<void> _commit(MenuDb nextOfficial, MenuDb nextPersonal, Set<String> installed) async {
    final ok = await preferences.setString(storageKey, jsonEncode({
      'official': _encodeForStorage(nextOfficial), 'personal': _encodeForStorage(nextPersonal),
      'installedStores': installed.toList()..sort(),
    }));
    if (!ok) throw StateError('保存失败，原数据库保持不变');
    official = nextOfficial; personal = nextPersonal; installedStoreIds = {...installed};
  }
  Future<void> _enqueue(Future<void> Function() operation) {
    final task = _pending.then((_) => operation());
    _pending = task.catchError((Object _) {});
    return task;
  }
  Future<void> setStoreInstalled(String id, bool enabled) => _enqueue(() async {
    if (!official.places.any((p) => p.id == id)) throw StateError('店铺不存在');
    final next = {...installedStoreIds};
    if (enabled) { next.add(id); } else { next.remove(id); }
    await _commit(official, personal, next);
  });
  Future<void> replace(MenuDb db) => _enqueue(() async {
    db.validate();
    await _commit(db.source == Source.official ? db : official,
      db.source == Source.personal ? db : personal, installedStoreIds);
  });
}
