import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/rice_panel.dart';
import 'package:eat_what/main.dart';

// Models Android commitToMemory before a failing disk commit. getAll reads
// the native memory map; a subsequent successful commit persists that map.
class NativeCacheStore extends InMemorySharedPreferencesStore {
  NativeCacheStore() : super.withData({'flutter.${FavoriteStore.storageKey}': '{broken'});
  bool fail = true;
  Map<String, Object> disk = {'flutter.${FavoriteStore.storageKey}': '{broken'};
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    await super.setValue(type, key, value);
    if (key == 'flutter.${FavoriteStore.storageKey}' && fail) {
      fail = false;
      return false;
    }
    disk = Map.from(await getAll());
    return true;
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reset retry preserves recovery with native cache after failed commit', () async {
    SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: '{broken'});
    final prefs = await SharedPreferences.getInstance();
    final backend = NativeCacheStore();
    SharedPreferencesStorePlatform.instance = backend;
    final store = await FavoriteStore.loadAvailable(prefs);
    await expectLater(store.resetAfterBackup(), throwsStateError);
    expect(backend.disk['flutter.${FavoriteStore.storageKey}.recovery'], '{broken');
    await store.resetAfterBackup();
    expect(backend.disk['flutter.${FavoriteStore.storageKey}.recovery'], '{broken');
  });
  testWidgets('unassociated personal rice plan can select a dish without crashing', (tester) async {
    const plan = RicePlan(id: 'orphan', name: '个人套餐', location: '未知窗口', priceCents: 900,
      labels: ['大荤','小荤','素菜'], options: [['测试菜A'],['测试菜B'],['测试菜C']]);
    final personal = MenuDb(source: Source.personal, revision: 1, places: [], foods: [], offers: [], ricePlans: [plan]);
    SharedPreferences.setMockInitialValues({'eat_what.meal_period': 'lunch', MenuRepository.storageKey: jsonEncode({
      'official': File('assets/official.json').readAsStringSync(), 'personal': personal.encode(), 'installedStores': <String>[],
    })});
    await tester.pumpWidget(const EatWhatApp());
    for (var i=0;i<100;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    final rice = find.byKey(const ValueKey('meal-category-rice'));
    await tester.ensureVisible(rice); await tester.tap(rice); await tester.pumpAndSettle();
    final choice = find.descendant(of: find.byType(RicePanel), matching: find.byType(DropdownButtonFormField<String>)).first;
    await tester.ensureVisible(choice); await tester.tap(choice); await tester.pumpAndSettle();
    await tester.tap(find.text('测试菜A').last); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
