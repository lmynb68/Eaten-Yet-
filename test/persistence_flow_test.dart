import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/favorites.dart';

// Cross-module tests with a simulated persistent store, not device E2E tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.clear();
  });

  test('personal import and store selection survive a fresh repository load', () async {
    const personal = MenuDb(source: Source.personal, revision: 2,
      places: [Place('my-store', '我的店', '校门口')], foods: [],
      offers: [Offer(id: 'my-meal', placeId: 'my-store', name: '午餐',
        portion: '一份', priceCents: 1250, roles: {}, foodIds: {},
        updatedAt: '2026-10-27', kind: 'main')]);
    final imported = MenuDb.decode(personal.encode(), Source.personal);
    final repo = await MenuRepository.load();
    final disabled = repo.official.places.first.id;
    await repo.replace(imported);
    await repo.setStoreInstalled(disabled, false);
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString(MenuRepository.storageKey)!;
    // Drop the old plugin singleton/cache; retain only serialized saved data.
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey: persisted});
    rootBundle.clear();
    final restored = await MenuRepository.load();
    expect(restored.personal.encode(), personal.encode());
    expect(restored.installedStoreIds, isNot(contains(disabled)));
    expect(restored.activeOfficial.places.any((p) => p.id == disabled), isFalse);
    expect(entries(restored.official, restored.personal, Scope.personal).single.offer.priceCents, 1250);
    final exported = MenuDb.decode(restored.personal.encode(), Source.personal);
    expect(exported.offers.single.name, '午餐');
  });

  test('favorites and preference survive a fresh preferences instance', () async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await FavoriteStore.load(prefs);
    const meal = FavoriteMeal(storeKey: 'personal:my-store', storeName: '我的店',
      kind: 'meal', savedAt: '2026-10-27',
      items: [FavoriteItem('personal:my-meal', '午餐', 1250)]);
    await favorites.save(meal);
    await favorites.setEnabled(false);
    final raw = prefs.getString(FavoriteStore.storageKey)!;
    SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
    final restored = await FavoriteStore.load(await SharedPreferences.getInstance());
    expect(restored.meals.single.id, meal.id);
    expect(restored.meals.single.total, 1250);
    expect(restored.enabled, isFalse);
    await restored.remove(meal.id);
    expect((await FavoriteStore.load(await SharedPreferences.getInstance())).meals, isEmpty);
  });
}
