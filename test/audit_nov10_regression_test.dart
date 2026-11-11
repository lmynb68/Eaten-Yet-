import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/rice_panel.dart';
import 'package:eat_what/rice_worker.dart';

// Review-only probes outside the application checkout. Assertions describe
// expected safe behavior, so failures are evidence of remaining defects.
class FailHistoryBackupOnce extends InMemorySharedPreferencesStore {
  bool fail = true;
  FailHistoryBackupOnce() : super.withData({
    'flutter.${HistoryStore.storageKey}': '{broken-history',
  });
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail && key.contains('.recovery.')) {
      fail = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

class FailHistoryClearOnce extends InMemorySharedPreferencesStore {
  bool fail = true;
  FailHistoryClearOnce() : super.withData({'flutter.${HistoryStore.storageKey}': '{A'});
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail && key == 'flutter.${HistoryStore.storageKey}') { fail = false; return false; }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('history backup retry must persist the original despite optimistic cache', () async {
    SharedPreferences.setMockInitialValues({HistoryStore.storageKey: '{broken-history'});
    final prefs = await SharedPreferences.getInstance();
    final backend = FailHistoryBackupOnce();
    SharedPreferencesStorePlatform.instance = backend;
    final store = await HistoryStore.load(prefs);
    await expectLater(store.resetAfterBackup(), throwsStateError);
    expect((await backend.getAll())['flutter.${HistoryStore.storageKey}'], '{broken-history');
    await store.resetAfterBackup();
    final disk = await backend.getAll();
    print('history durable keys after retry: ${disk.keys.toList()}');
    expect(disk.values, contains('{broken-history'));
  });

  test('history clear failure retry preserves original; independent corruption has own backup', () async {
    SharedPreferences.setMockInitialValues({HistoryStore.storageKey: '{A'});
    final prefs = await SharedPreferences.getInstance();
    final backend = FailHistoryClearOnce();
    SharedPreferencesStorePlatform.instance = backend;
    final store = await HistoryStore.load(prefs);
    await expectLater(store.resetAfterBackup(), throwsStateError);
    expect(store.export(), '{A');
    await store.resetAfterBackup();
    await prefs.setString(HistoryStore.storageKey, '{B');
    await (await HistoryStore.load(prefs)).resetAfterBackup();
    final values = (await backend.getAll()).values;
    expect(values, contains('{A'));
    expect(values, contains('{B'));
  });
  test('wrong-typed history must remain isolated from menu startup', () async {
    SharedPreferences.setMockInitialValues({HistoryStore.storageKey: 42});
    final prefs = await SharedPreferences.getInstance();
    final store = await HistoryStore.load(prefs);
    expect(store.recoveryRequired, isTrue);
    expect(store.export(), '42');
    await store.resetAfterBackup();
    expect((await HistoryStore.load(prefs)).recoveryRequired, isFalse);
  });
  test('saved personal menu export must be importable', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await MenuRepository.load();
    final j = jsonDecode(File('assets/official.json').readAsStringSync()) as Map;
    j['source'] = 'personal';
    j['offers'][0]['notes'] = '';
    final normalized = jsonDecode(MenuDb.decode(jsonEncode(j), Source.personal).encode(compact: true));
    normalized['offers'][0]['notes'] = 'x' * (11999900 - jsonEncode(normalized).length);
    final menu = MenuDb.decode(jsonEncode(normalized), Source.personal);
    await repo.replace(menu);
    final restored = await MenuRepository.load();
    final exported = MenuRepository.exportMenu(restored.personal);
    print('stored compact length=${restored.personal.encode(compact: true).length}; exported length=${exported.length}');
    expect(MenuDb.decode(exported, Source.personal).offers.length, menu.offers.length);
  });
  testWidgets('untyped personal rice random must respect the displayed option groups', (tester) async {
    // Valid imported plan with overlapping groups and no meat/veg tags.
    // There is no distinct three-dish match for these groups, so preserve blanks.
    const plan = RicePlan(id: 'p', name: 'personal', location: 'store',
      storeKey: 'personal:s', priceCents: 100, labels: ['1', '2', '3'],
      options: [['A'], ['A'], ['B', 'C']], dishPrices: {'A': 100, 'B': 100, 'C': 100});
    plan.validate();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: RicePanel(randomizer: (job) async => calculateRice(job), plans: const [('personal:p', plan)], budget: 2000,
        stores: const {'personal:s': 'store'}, savePersonal: (_) async => true)))));
    final button = find.text('随机其余菜品');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
