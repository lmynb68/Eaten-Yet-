import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => rootBundle.clear());
  test('corrupt saved JSON remains intact after failed load and recovery export', () async {
    const raw = '{broken personal menu';
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey: raw,
      'eat_what.favorites': 'unparsed favorites', 'unrelated': 'excluded'});
    await expectLater(MenuRepository.load(), throwsA(isA<FormatException>()));
    final snapshot = jsonDecode(await MenuRepository.exportRecoveryData()) as Map;
    expect(snapshot['values'][MenuRepository.storageKey], raw);
    expect(snapshot['values']['eat_what.favorites'], 'unparsed favorites');
    expect(snapshot['values'].containsKey('unrelated'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(MenuRepository.storageKey), raw);
  });
  test('recovery export preserves supported preference value types', () async {
    SharedPreferences.setMockInitialValues({'eat_what.enabled': true,
      'eat_what.count': 3, 'eat_what.order': <String>['a','b']});
    final snapshot = jsonDecode(await MenuRepository.exportRecoveryData()) as Map;
    expect(snapshot['values']['eat_what.enabled'], true);
    expect(snapshot['values']['eat_what.count'], 3);
    expect(snapshot['values']['eat_what.order'], ['a','b']);
  });
}
