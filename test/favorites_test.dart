import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/rice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',}));
  FavoriteMeal meal(List<String> keys, {int price = 300}) => FavoriteMeal(
    storeKey: 'official:sf', storeName: '食味坊', kind: '米饭选菜', savedAt: '2026-10-19T12:00:00',
    ricePrice: 100, items: keys.map((k) => FavoriteItem(k, k, price)).toList());
  test('favorites preserve prices, deduplicate reordered meals and persist the off switch', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await FavoriteStore.load(prefs);
    expect(store.score(['a','b']), 1);
    await store.save(meal(['a','b']));
    final weight = store.score(['a','b']);
    expect(weight, greaterThan(1));
    await store.save(meal(['b','a']));
    expect(store.meals.length, 1); expect(store.score(['a','b']), weight);
    expect(store.meals.single.total, 700);
    expect(store.pairCoefficient('a','b'), store.pairCoefficient('b','a'));
    expect(store.pairCoefficient('a','unseen'), 1);
    await store.setEnabled(false);
    final restored = await FavoriteStore.load(prefs);
    expect(restored.enabled, isFalse); expect(restored.meals.length, 1);
    expect(restored.score(['a','b']), 1);
    await restored.setEnabled(true);
    await restored.remove(restored.meals.single.id);
    expect(restored.score(['a','b']), 1);
    expect((await FavoriteStore.load(prefs)).meals, isEmpty);
  });
  test('queued saves do not lose a meal and scores have an upper bound', () async {
    final store = await FavoriteStore.load(await SharedPreferences.getInstance());
    await Future.wait([for (var i=0;i<20;i++) store.save(meal(['a','b','c$i']))]);
    expect(store.meals.length, 20);
    expect(store.dishWeight('a'), 3); expect(store.pairCoefficient('a','b'), 2);
    expect(store.score(['a','b']), 6);
    expect(store.dishWeight('other-store:a'), 1);
  });
  test('weighted sampling favors liked food without excluding other choices', () {
    final random = Random(14); var liked=0;
    for (var i=0;i<4000;i++) {
      if (weightedPick(['a','b'],random,(s) => s == 'a' ? 3 : 1) == 'a') liked++;
    }
    expect(liked, inInclusiveRange(2800,3200));
    expect(() => weightedPick(['a'],Random(1), (_) => double.nan), throwsArgumentError);
  });
  test('rice preferences cannot override budget, uniqueness or locks', () async {
    const p = RicePlan(id:'rice', name:'自选', storeKey:'official:sf', location:'食味坊1号窗口',
      priceCents:100, labels:['1','2','3'], options:[['a','b','c','expensive'],['a','b','c','expensive'],['a','b','c','expensive']],
      dishPrices:{'a':200,'b':200,'c':200,'expensive':10000});
    final store = await FavoriteStore.load(await SharedPreferences.getInstance());
    await store.save(meal([riceDishKey(p,'expensive'),riceDishKey(p,'a')]));
    for (var i=0;i<20;i++) {
      final result = randomRice(p,700,['a',null,null],{0},Random(i),
        score:(names) => store.score(names.map((n) => riceDishKey(p,n))));
      expect(result.dishes, isNotNull); expect(result.dishes!.first,'a');
      expect(result.dishes!.toSet(), {'a','b','c'}); expect(p.totalPrice(result.dishes!),700);
    }
  });
}
