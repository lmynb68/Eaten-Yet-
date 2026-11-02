import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:eat_what/favorites.dart';

class FailOnceStore extends InMemorySharedPreferencesStore {
  FailOnceStore() : super.withData({'flutter.${FavoriteStore.storageKey}': '{broken'});
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${FavoriteStore.storageKey}' && fail) {
      fail = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('probe reset retry with real preferences cache', () async {
    SharedPreferences.setMockInitialValues({FavoriteStore.storageKey: '{broken'});
    final prefs = await SharedPreferences.getInstance();
    final disk = FailOnceStore();
    SharedPreferencesStorePlatform.instance = disk;
    final store = await FavoriteStore.loadAvailable(prefs);
    await expectLater(store.resetAfterBackup(), throwsStateError);
    expect((await disk.getAll())['flutter.${FavoriteStore.storageKey}'], '{broken');
    expect(prefs.getString(FavoriteStore.storageKey), isNot('{broken'));
    await store.resetAfterBackup();
    final saved = await disk.getAll();
    expect(saved['flutter.${FavoriteStore.storageKey}.recovery'], '{broken');
    expect(saved['flutter.${FavoriteStore.storageKey}'], isNot('{broken'));
  });
}
