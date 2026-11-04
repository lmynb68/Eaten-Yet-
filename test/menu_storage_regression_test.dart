import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/favorites.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('accepted personal menu remains readable after save', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await MenuRepository.load();
    final j = jsonDecode(File('assets/official.json').readAsStringSync()) as Map;
    j['source']='personal';
    j['offers'][0]['notes']='';
    j['offers'][0]['notes']='x'*(11999999-jsonEncode(j).length);
    final raw=jsonEncode(j);
    final menu=MenuDb.decode(raw,Source.personal);
    final prefs = await SharedPreferences.getInstance();
    await repo.replace(repo.personal);
    final before = prefs.getString(MenuRepository.storageKey)!;
    await expectLater(repo.replace(menu), throwsFormatException);
    expect(prefs.getString(MenuRepository.storageKey), before);
    expect(repo.personal.offers, isEmpty);

    // Reproduce the on-disk value produced by the older writer.
    final stored = jsonDecode(before)..['personal'] = menu.encode();
    await prefs.setString(MenuRepository.storageKey, jsonEncode(stored));
    final recovered = await MenuRepository.load();
    expect(recovered.personal.offers.first.notes.length, menu.offers.first.notes.length);
    j['offers'][0]['notes'] = 'x' * 100000;
    final smaller = MenuDb.decode(jsonEncode(j), Source.personal);
    await recovered.replace(smaller);
    expect((await MenuRepository.load()).personal.encode(), smaller.encode());
  });
  test('subsequent independent corruption is retained in recovery', () async {
    final k=FavoriteStore.storageKey;
    SharedPreferences.setMockInitialValues({k:'{broken-A'});
    final prefs=await SharedPreferences.getInstance();
    await (await FavoriteStore.loadAvailable(prefs)).resetAfterBackup();
    await prefs.setString(k,'{broken-B');
    await (await FavoriteStore.loadAvailable(prefs)).resetAfterBackup();
    final exported = await MenuRepository.exportRecoveryData();
    expect(exported, contains('{broken-A'));
    expect(exported, contains('{broken-B'));
  });
  test('modified historical demo survives upgrade and subsequent save', () async {
    final j=jsonDecode(File('test/fixtures/demo-v1.json').readAsStringSync());
    j['offers'][0]['priceCents']=12345;
    final changed=MenuDb.decode(jsonEncode(j),Source.official);
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':changed.encode(),'personal':MenuDb.empty(Source.personal).encode()})});
    final repo=await MenuRepository.load();
    await repo.replace(repo.personal);
    expect((await MenuRepository.load()).official.offers.first.priceCents,12345);
  });
}
