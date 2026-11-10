import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/favorites.dart';

class Preferences implements SharedPreferences {
  @override
  Future<void> reload() async {}
  final Map<String, String> disk = {};
  String? failKey;
  bool throws = false;
  @override
  String? getString(String key) => disk[key];
  @override
  Object? get(String key) => disk[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (key == failKey) {
      if (throws) throw StateError('write failed');
      return false;
    }
    disk[key] = value;
    return true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
FavoriteMeal meal(String key, {String photo = ''}) => FavoriteMeal(
  storeKey: 's', storeName: 's', kind: 'meal', savedAt: 'today',
  items: [FavoriteItem(key, '菜', 100, photo: photo)]);
String encode(List<FavoriteMeal> meals) => jsonEncode({
  'version': 1, 'enabled': true, 'meals': meals.map((m) => m.toJson()).toList(),
});
void main() {
  for (final throws in [false, true]) {
    for (final backupFailure in [false, true]) {
      test('reset failure: backup=$backupFailure throw=$throws preserves original and retries', () async {
        final prefs = Preferences()..disk[FavoriteStore.storageKey] = '{broken';
        final store = await FavoriteStore.loadAvailable(prefs);
        prefs.throws = throws;
        prefs.failKey = backupFailure ? '${FavoriteStore.storageKey}.recovery' : FavoriteStore.storageKey;
        await expectLater(store.resetAfterBackup(), throwsStateError);
        expect(prefs.getString(FavoriteStore.storageKey), '{broken');
        expect(store.recoveryRequired, isTrue);
        expect(store.enabled, isFalse);
        expect(prefs.getString('${FavoriteStore.storageKey}.recovery'), backupFailure ? isNull : '{broken');
        prefs.failKey = null;
        await store.resetAfterBackup();
        expect(store.recoveryRequired, isFalse);
        expect((await FavoriteStore.load(prefs)).meals, isEmpty);
      });
    }
  }
  test('oversized legacy count allows settings, replacement and deletion but rejects growth', () async {
    final original = List.generate(502, (i) => meal('$i'));
    final prefs = Preferences()..disk[FavoriteStore.storageKey] = encode(original);
    final store = await FavoriteStore.load(prefs);
    await store.setEnabled(false);
    expect((await FavoriteStore.load(prefs)).enabled, isFalse);
    await store.setEnabled(true);
    await store.save(original.first);
    await expectLater(store.save(meal('new')), throwsFormatException);
    await store.remove(original.first.id);
    expect((await FavoriteStore.load(prefs)).meals.length, 501);
    await store.setEnabled(false);
    expect(store.dishWeight('1'), 1);
  });
  test('UTF8 capacity accepts exactly 10 MiB and rejects one byte more', () async {
    final prefs = Preferences();
    final store = await FavoriteStore.load(prefs);
    final padding = FavoriteStore.maxStorageBytes - utf8.encode(encode([meal('a')])).length;
    await store.save(meal('a', photo: 'x' * padding));
    final before = prefs.getString(FavoriteStore.storageKey);
    expect(utf8.encode(before!).length, FavoriteStore.maxStorageBytes);
    await expectLater(store.save(meal('a', photo: 'x' * (padding + 1))), throwsFormatException);
    expect(prefs.getString(FavoriteStore.storageKey), before);
    expect(store.meals.single.items.single.photo.length, padding);
    await store.remove(store.meals.single.id);
    expect((await FavoriteStore.load(prefs)).meals, isEmpty);
  });
  test('oversized legacy bytes allow both settings directions and shrinking saves', () async {
    final huge = meal('a', photo: 'x' * FavoriteStore.maxStorageBytes);
    final prefs = Preferences()..disk[FavoriteStore.storageKey] = encode([huge, meal('b')]);
    final store = await FavoriteStore.load(prefs);
    await store.setEnabled(false);
    await store.setEnabled(true);
    expect((await FavoriteStore.load(prefs)).enabled, isTrue);
    await store.save(huge);
    await expectLater(store.save(meal('c')), throwsFormatException);
    await store.remove(meal('b').id);
    expect((await FavoriteStore.load(prefs)).meals.length, 1);
    await store.save(meal('a'));
    expect((await FavoriteStore.load(prefs)).meals.single.items.single.photo, isEmpty);
  });
}
