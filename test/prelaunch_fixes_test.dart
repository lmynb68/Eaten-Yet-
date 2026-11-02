import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('numeric Android build suffix breaks ties for release selection', () {
    expect(compareVersions('v1.0.0+27', '1.0.0+25'), greaterThan(0));
    expect(compareVersions('v1.0.0+25', '1.0.0+25'), 0);
    expect(compareVersions('v1.0.0+24', '1.0.0+25'), lessThan(0));
    expect(compareVersions('v1.0.1', '1.0.0+99'), greaterThan(0));
    expect(compareVersions('v1.0.0-beta+99', '1.0.0+25'), lessThan(0));
  });
  test('reset keeps corrupt original in a recovery copy and enables writes', () async {
    const original = '{broken';
    SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: original});
    final prefs = await SharedPreferences.getInstance();
    final store = await FavoriteStore.loadAvailable(prefs);
    await store.resetAfterBackup();
    expect(prefs.getString('${FavoriteStore.storageKey}.recovery'), original);
    expect(store.recoveryRequired, isFalse);
    expect((await FavoriteStore.load(prefs)).meals, isEmpty);
    await store.setEnabled(true);
    expect(store.enabled, isTrue);
  });
  test('favorite count limit rejects growth without losing existing records', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await FavoriteStore.load(prefs);
    FavoriteMeal meal(int i) => FavoriteMeal(storeKey: 'store', storeName: 'store',
      kind: 'meal', savedAt: '2026-10-29', items: [FavoriteItem('$i', 'dish', 100)]);
    // Seed existing records to exercise the boundary without 500 disk writes.
    store.meals = List.generate(FavoriteStore.maxMeals, meal);
    await expectLater(store.save(meal(501)), throwsFormatException);
    expect(store.meals.length, FavoriteStore.maxMeals);
    await store.remove(meal(0).id);
    await store.save(meal(501));
    expect(store.meals.length, FavoriteStore.maxMeals);
  });
}
