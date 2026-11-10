import 'dart:convert';

import 'package:eat_what/favorites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const favorite = FavoriteMeal(
  storeKey: 'official:test',
  storeName: '测试店',
  kind: 'meal',
  savedAt: '2026-11-10',
  items: [FavoriteItem('test', '测试菜', 500)],
);

class FailingDisk extends InMemorySharedPreferencesStore {
  FailingDisk(Object raw, this.failKey, this.throwOnFailure)
      : super.withData({'flutter.${FavoriteStore.storageKey}': raw});
  final String failKey;
  final bool throwOnFailure;
  bool failOnce = true;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == failKey && failOnce) {
      failOnce = false;
      if (throwOnFailure) throw StateError('disk write failed');
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final raw in <Object>[
    42,
    false,
    2.5,
    ['broken', 'favorites']
  ]) {
    test('non-string favorites can be backed up and reset: ${raw.runtimeType}',
        () async {
      SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
      final prefs = await SharedPreferences.getInstance();
      final store = await FavoriteStore.loadAvailable(prefs);
      expect(store.recoveryRequired, isTrue);
      expect(prefs.get(FavoriteStore.storageKey), raw);
      await store.resetAfterBackup();
      await prefs.reload();
      expect(
          jsonDecode(prefs.getString('${FavoriteStore.storageKey}.recovery')!),
          raw);
      expect((await FavoriteStore.load(prefs)).meals, isEmpty);
      expect(store.recoveryRequired, isFalse);
      await store.save(favorite);
      expect((await FavoriteStore.load(prefs)).meals.single.total, 500);
    });
  }
  for (final raw in [double.nan, double.infinity, double.negativeInfinity]) {
    test('non-finite preference retains its value before reset: $raw', () async {
      SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
      final prefs = await SharedPreferences.getInstance();
      final store = await FavoriteStore.loadAvailable(prefs);
      expect(store.recoveryRequired, isTrue);
      await store.resetAfterBackup();
      await prefs.reload();
      expect(jsonDecode(prefs.getString('${FavoriteStore.storageKey}.recovery')!),
          {'type': 'double', 'value': raw.toString()});
      expect((await FavoriteStore.load(prefs)).meals, isEmpty);
      expect(store.recoveryRequired, isFalse);
    });
  }
  for (final backupFailure in [true, false]) {
    for (final throwOnFailure in [true, false]) {
      test(
          'typed recovery retries real plugin cache: backup=$backupFailure throw=$throwOnFailure',
          () async {
        const raw = 42;
        SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
        final prefs = await SharedPreferences.getInstance();
        final disk = FailingDisk(
            raw,
            'flutter.${FavoriteStore.storageKey}${backupFailure ? '.recovery' : ''}',
            throwOnFailure);
        SharedPreferencesStorePlatform.instance = disk;
        final store = await FavoriteStore.loadAvailable(prefs);
        await expectLater(store.resetAfterBackup(), throwsStateError);
        expect(
            (await disk.getAll())['flutter.${FavoriteStore.storageKey}'], raw);
        expect(store.recoveryRequired, isTrue);
        await store.resetAfterBackup();
        final saved = await disk.getAll();
        expect(saved['flutter.${FavoriteStore.storageKey}.recovery'], '42');
        expect(
            jsonDecode(saved['flutter.${FavoriteStore.storageKey}'] as String)[
                'meals'],
            isEmpty);
        expect(store.recoveryRequired, isFalse);
      });
    }
  }
  test(
      'independent typed corruptions retain both originals and an existing typed backup',
      () async {
    SharedPreferences.setMockInitialValues({
      FavoriteStore.storageKey: 42,
      '${FavoriteStore.storageKey}.recovery': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await (await FavoriteStore.loadAvailable(prefs)).resetAfterBackup();
    await prefs.setStringList(FavoriteStore.storageKey, ['second']);
    await (await FavoriteStore.loadAvailable(prefs)).resetAfterBackup();
    await prefs.reload();
    final backups = prefs
        .getKeys()
        .where((key) => key.startsWith('${FavoriteStore.storageKey}.recovery'))
        .map(prefs.get)
        .toList();
    expect(backups, containsAll([true, '42', '["second"]']));
  });
  test(
      'invalid favorite fields enter recovery without replacing the original data',
      () async {
    final mutations = <void Function(Map<String, dynamic>)>[
      (j) => (j['items'] as List).first['price'] = -1,
      (j) => (j['items'] as List).first['price'] = 1.5,
      (j) => (j['items'] as List).first['price'] = 10000001,
      (j) => (j['items'] as List).first['quantity'] = 0,
      (j) => (j['items'] as List).first['name'] = '',
      (j) => j['ricePrice'] = -1,
      (j) => j['baseQuantity'] = 100,
      (j) => j['storeKey'] = '',
      (j) => j['storeName'] = 123,
      (j) => j['items'] = [],
    ];
    for (final mutate in mutations) {
      final meal = favorite.toJson();
      mutate(meal);
      final raw = jsonEncode({
        'version': 1,
        'enabled': true,
        'meals': [meal]
      });
      SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: raw});
      final prefs = await SharedPreferences.getInstance();
      final store = await FavoriteStore.loadAvailable(prefs);
      expect(store.recoveryRequired, isTrue);
      expect(store.enabled, isFalse);
      expect(store.meals, isEmpty);
      expect(prefs.getString(FavoriteStore.storageKey), raw);
    }
  });
  test('save rejects invalid prices before replacing valid favorites',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await FavoriteStore.load(prefs);
    await store.save(favorite);
    final before = prefs.getString(FavoriteStore.storageKey);
    for (final meal in [
      const FavoriteMeal(
          storeKey: 's',
          storeName: 's',
          kind: 'meal',
          savedAt: 'today',
          items: [FavoriteItem('bad', 'bad', -1)]),
      const FavoriteMeal(
          storeKey: 's',
          storeName: 's',
          kind: 'meal',
          savedAt: 'today',
          ricePrice: -1,
          items: [FavoriteItem('bad', 'bad', 0)]),
    ]) {
      expect(() => store.save(meal), throwsFormatException);
      expect(prefs.getString(FavoriteStore.storageKey), before);
    }
    final legacy = favorite.toJson();
    legacy.remove('baseQuantity');
    (legacy['items'] as List).first.remove('quantity');
    expect(FavoriteMeal.fromJson(legacy).total, 500);
    expect(
        FavoriteItem.fromJson({'key': 'free', 'name': '免费汤', 'price': 0}).price,
        0);
  });
}
