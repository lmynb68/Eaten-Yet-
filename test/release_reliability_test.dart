import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('corrupt favorites remain untouched and usable fallback refuses writes', () async {
    const raw = '{broken';
    SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
    final prefs = await SharedPreferences.getInstance();
    final favorites = await FavoriteStore.loadAvailable(prefs);
    expect(favorites.recoveryRequired, isTrue);
    expect(favorites.score(['meal']), 1);
    await expectLater(favorites.setEnabled(true), throwsStateError);
    expect(prefs.getString(FavoriteStore.storageKey), raw);
  });
  test('overlapping store changes and catalog replacement preserve latest state', () async {
    final prefs = await SharedPreferences.getInstance();
    final db = MenuDb.decode(File('assets/official.json').readAsStringSync(), Source.official);
    final repo = MenuRepository(prefs, db, MenuDb.empty(Source.personal));
    final a = db.places[0].id, b = db.places[1].id;
    await Future.wait([repo.setStoreInstalled(a, false), repo.replace(db), repo.setStoreInstalled(b, false)]);
    expect(repo.installedStoreIds, isNot(contains(a)));
    expect(repo.installedStoreIds, isNot(contains(b)));
    final saved = jsonDecode(prefs.getString(MenuRepository.storageKey)!);
    expect(saved['installedStores'], isNot(contains(a)));
    expect(saved['installedStores'], isNot(contains(b)));
    await expectLater(repo.setStoreInstalled('missing', false), throwsStateError);
    await repo.setStoreInstalled(a, true);
    expect(repo.installedStoreIds, contains(a));
  });
  test('stable update ignores previews and releases without uploaded APKs', () {
    Map<String,dynamic> release(String tag, {bool preview=false, bool asset=true}) => {
      'tag_name':tag,'html_url':'$releasesUrl/tag/$tag','prerelease':preview,
      'assets':asset?[{'name':'app.apk','state':'uploaded','size':123,
        'browser_download_url':'$releasesUrl/download/$tag/app.apk'}]:[],
    };
    final data=jsonEncode([release('v1.0.0'),release('v2.0.0-beta',preview:true),release('v3.0.0',asset:false)]);
    expect(AppRelease.latest(data)!.version,'v1.0.0');
    expect(AppRelease.latest(data,includePrereleases:true)!.version,'v2.0.0-beta');
    expect(AppRelease.latest(jsonEncode([release('v3.0.0',asset:false)])),isNull);
  });
}
