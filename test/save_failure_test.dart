import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/favorites.dart';

// A failed disk write must not change durable data. Exercise both plugin
// failure modes without relying on SharedPreferences' optimistic memory cache.
class FailingPreferences implements SharedPreferences {
  final Map<String, String> disk = {};
  bool failNext = false;
  bool throwOnFailure = false;
  @override
  String? getString(String key) => disk[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (failNext) {
      failNext = false;
      if (throwOnFailure) throw StateError('simulated disk failure');
      return false;
    }
    disk[key] = value;
    return true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final throws in [false, true]) {
    test('menu save failure ($throws) preserves state and queue recovers', () async {
      final prefs = FailingPreferences()..throwOnFailure = throws;
      final db = MenuDb.decode(File('assets/official.json').readAsStringSync(), Source.official);
      final repo = MenuRepository(prefs, db, MenuDb.empty(Source.personal));
      await repo.replace(db);
      final original = prefs.disk[MenuRepository.storageKey];
      final a = db.places[0].id, b = db.places[1].id;
      prefs.failNext = true;
      final failed = repo.setStoreInstalled(a, false);
      final recovery = repo.setStoreInstalled(b, false);
      await expectLater(failed, throwsStateError);
      await recovery;
      expect(repo.installedStoreIds, contains(a));
      expect(repo.installedStoreIds, isNot(contains(b)));
      final saved = jsonDecode(prefs.disk[MenuRepository.storageKey]!);
      expect(saved['installedStores'], contains(a));
      expect(saved['installedStores'], isNot(contains(b)));
      expect(original, isNotNull);
      final before = prefs.disk[MenuRepository.storageKey];
      prefs.failNext = true;
      await expectLater(repo.replace(MenuDb.empty(Source.personal)), throwsStateError);
      expect(prefs.disk[MenuRepository.storageKey], before);
      expect(repo.official, same(db));
    });
    test('favorite save failure ($throws) preserves meals, scores and settings', () async {
      final prefs = FailingPreferences()..throwOnFailure = throws;
      final store = await FavoriteStore.load(prefs);
      const meal = FavoriteMeal(storeKey: 'official:test', storeName: 'test',
        kind: 'meal', savedAt: '2026-10-25', items: [FavoriteItem('dish', 'dish', 100)]);
      await store.save(meal);
      final raw = prefs.disk[FavoriteStore.storageKey];
      final score = store.dishWeight('dish');
      prefs.failNext = true;
      await expectLater(store.remove(meal.id), throwsStateError);
      expect(store.meals.single.id, meal.id);
      expect(store.dishWeight('dish'), score);
      expect(prefs.disk[FavoriteStore.storageKey], raw);
      prefs.failNext = true;
      final failed = store.setEnabled(false);
      final recovery = store.save(meal);
      await expectLater(failed, throwsStateError);
      await recovery;
      expect(store.enabled, isTrue);
      expect((await FavoriteStore.load(prefs)).enabled, isTrue);
      await store.remove(meal.id);
      expect((await FavoriteStore.load(prefs)).meals, isEmpty);
    });
  }
}
