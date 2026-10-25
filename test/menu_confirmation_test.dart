import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final old=MenuDb.decode(File('assets/official-v8.json').readAsStringSync(),Source.official);
 test('unchanged v8 upgrades without changing personal data or installed stores', () async {
  final personal=MenuDb.empty(Source.personal);
  SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':old.encode(),'personal':personal.encode(),'installedStores':['sf']})});
  final repo=await MenuRepository.load();
  expect(repo.official.revision,9);
  expect(repo.personal.encode(),personal.encode());
  expect(repo.installedStoreIds,{'sf'});
 });
 test('customized v8 catalog is preserved', () async {
  final edited=jsonDecode(old.encode()) as Map<String,dynamic>;
  edited['offers'][0]['priceCents']=12345;
  final custom=MenuDb.decode(jsonEncode(edited),Source.official);
  SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':custom.encode(),'personal':MenuDb.empty(Source.personal).encode()})});
  final repo=await MenuRepository.load();
  expect(repo.official.encode(),custom.encode());
 });
}
