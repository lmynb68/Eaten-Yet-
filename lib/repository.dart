import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'rice.dart';

class MenuRepository {
  static const storageKey = 'eat_what.campus.v1';
  final SharedPreferences preferences;
  MenuDb official, personal;
  Set<String> installedStoreIds;
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
  static Future<MenuRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    final builtIn = MenuDb.decode(await rootBundle.loadString('assets/official.json'), Source.official);
    if (saved == null) return MenuRepository(prefs, builtIn, MenuDb.empty(Source.personal));
    final j = jsonDecode(saved) as Map<String, dynamic>;
    final previousBuiltIn = MenuDb.decode(await rootBundle.loadString('assets/official-v4.json'), Source.official);
    final old = MenuDb.decode(j['official'], Source.official);
    final demo = old.revision == 1 && old.offers.isNotEmpty && old.offers.every((o) => o.example);
    // Recognize only the shipped catalog. Arbitrary imported libraries remain intact.
    final bundledV3 = old.revision == 3 && old.offers.length == 228 && old.places.length == 2 &&
      old.places.every((p) => previousBuiltIn.places.any((n) => jsonEncode(n.toJson()) == jsonEncode(p.toJson()))) &&
      jsonEncode(old.ricePlans.map((p) => p.toJson()).toList()) == jsonEncode(previousBuiltIn.ricePlans.map((p) => p.toJson()).toList()) &&
      jsonEncode(old.foods.map((f) => f.toJson()).toList()) == jsonEncode(previousBuiltIn.foods.map((f) => f.toJson()).toList()) &&
      old.offers.every((o) => previousBuiltIn.offers.any((n) => jsonEncode(n.toJson()) == jsonEncode(o.toJson())));
    final previousV5 = MenuDb.decode(await rootBundle.loadString('assets/official-v5.json'), Source.official);
    final previousV6 = MenuDb.decode(await rootBundle.loadString('assets/official-v6.json'), Source.official);
    final previousV7 = MenuDb.decode(await rootBundle.loadString('assets/official-v7.json'), Source.official);
    final previousV8 = MenuDb.decode(await rootBundle.loadString('assets/official-v8.json'), Source.official);
    final bundled = (old.revision == 8 && old.encode() == previousV8.encode()) || (old.revision == 7 && old.encode() == previousV7.encode()) || (old.revision == 6 && old.encode() == previousV6.encode()) || bundledV3 || (old.revision == 4 && old.encode() == previousBuiltIn.encode()) ||
      (old.revision == 5 && old.encode() == previousV5.encode());
    final next = builtIn.revision > old.revision && (demo || bundled) ? builtIn : old;
    return MenuRepository(prefs, next, MenuDb.decode(j['personal'], Source.personal),
      installed: j['installedStores'] == null ? null : Set<String>.from(j['installedStores']));
  }
  Future<void> _commit(MenuDb nextOfficial, MenuDb nextPersonal, Set<String> installed) async {
    final ok = await preferences.setString(storageKey, jsonEncode({
      'official': nextOfficial.encode(), 'personal': nextPersonal.encode(),
      'installedStores': installed.toList()..sort(),
    }));
    if (!ok) throw StateError('保存失败，原数据库保持不变');
    official = nextOfficial; personal = nextPersonal; installedStoreIds = {...installed};
  }
  Future<void> setStoreInstalled(String id, bool enabled) async {
    if (!official.places.any((p) => p.id == id)) throw StateError('店铺不存在');
    final next = {...installedStoreIds};
    if (enabled) { next.add(id); } else { next.remove(id); }
    await _commit(official, personal, next);
  }
  Future<void> replace(MenuDb db) async {
    db.validate();
    await _commit(db.source == Source.official ? db : official,
      db.source == Source.personal ? db : personal, installedStoreIds);
  }
}
