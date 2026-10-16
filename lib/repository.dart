import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';

class MenuRepository {
  static const storageKey = 'eat_what.campus.v1';
  final SharedPreferences preferences;
  MenuDb official, personal;
  MenuRepository(this.preferences, this.official, this.personal);
  static Future<MenuRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    final builtIn = MenuDb.decode(await rootBundle.loadString('assets/official.json'), Source.official);
    if (saved == null) return MenuRepository(prefs, builtIn, MenuDb.empty(Source.personal));
    final j = jsonDecode(saved) as Map<String, dynamic>;
    final savedOfficial = MenuDb.decode(j['official'], Source.official);
    // Only replace the original demo automatically. Keep any imported non-demo official catalog.
    final replaceDemo = savedOfficial.revision == 1 && savedOfficial.offers.isNotEmpty &&
      savedOfficial.offers.every((o) => o.example) && builtIn.revision > savedOfficial.revision;
    return MenuRepository(prefs, replaceDemo ? builtIn : savedOfficial, MenuDb.decode(j['personal'], Source.personal));
  }
  Future<void> replace(MenuDb db) async {
    db.validate();
    final nextOfficial = db.source == Source.official ? db : official;
    final nextPersonal = db.source == Source.personal ? db : personal;
    final ok = await preferences.setString(storageKey, jsonEncode({
      'official': nextOfficial.encode(), 'personal': nextPersonal.encode(),
    }));
    if (!ok) throw StateError('保存失败，原数据库保持不变');
    official = nextOfficial; personal = nextPersonal;
  }
}
