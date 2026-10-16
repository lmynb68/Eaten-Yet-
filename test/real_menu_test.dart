import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/domain.dart';

void main() {
  final db = MenuDb.decode(File('assets/official.json').readAsStringSync(), Source.official);
  final pool = entries(db, MenuDb.empty(Source.personal), Scope.official);
  MealResult draw(List<Entry> candidates, {int budget = 2000, int extras = 2,
      List<Entry?> previous = const [null,null,null], Set<int> locks = const {}, int seed = 1}) =>
    recommend(candidates, MealRequest(budget: budget, mode: MealMode.mainWithSides,
      extras: extras, previous: previous, locked: locks), Random(seed));

  test('real source has two restaurants, eight foodcourt windows and distinct price channels', () {
    expect(db.places.length, 2);
    expect(db.offers.length, 228);
    expect(db.offers.where((o) => o.placeId == 'sf').map((o) => o.window).toSet().length, 8);
    expect(db.offers.every((o) => !o.example && !o.ingredientsKnown && o.evidence.isNotEmpty), isTrue);
    final premium = db.offers.where((o) => o.name == '优质牛肉面');
    expect(premium.map((o) => o.priceCents).toSet(), {1500,1490});
    expect(MenuDb.decode(db.encode(), Source.official).encode(), db.encode());
  });
  test('seeded meals preserve budget, one main, optional extras and purchase restrictions', () {
    for (var seed = 0; seed < 30; seed++) {
      final slots = draw(pool, seed: seed).meal!;
      final meal = slots.whereType<Entry>().toList();
      expect(slots[0]!.offer.kind, 'main');
      expect(meal.where((e) => e.offer.kind == 'main').length, 1);
      expect(meal.fold<int>(0,(sum,e) => sum+e.offer.priceCents), lessThanOrEqualTo(2000));
      expect(meal.map((e) => e.placeKey).toSet().length, 1);
      expect(meal.every((e) => !e.offer.alcohol && e.offer.channel == 'regular'), isTrue);
      expect(meal.where((e) => e.offer.kind == 'drink').length, lessThanOrEqualTo(1));
      for (final e in meal.where((e) => e.offer.addonOnly)) {
        expect(e.offer.window, slots[0]!.offer.window);
      }
    }
  });
  test('main only and low budgets do not force three purchases', () {
    final meal = draw(pool, extras: 0).meal!;
    expect(meal.whereType<Entry>().length, 1);
    expect(draw(pool, budget: 1).meal, isNull);
    final cheapest = pool.where((e) => e.offer.name == '西红柿鸡蛋面').first;
    expect(draw([cheapest], budget: 800).meal!.whereType<Entry>().length, 1);
  });
  test('locks retain position including slot two with an empty slot one', () {
    final main = pool.firstWhere((e) => e.offer.name == '小份牛肉面' && e.offer.channel == 'regular');
    final side = pool.firstWhere((e) => e.offer.name == '卤蛋（1个）' && e.offer.placeId == 'jml');
    final old = <Entry?>[main,null,side];
    final next = draw(pool, extras: 1, previous: old, locks: {2}).meal!;
    expect(identical(next[2],side), isTrue);
    expect(next[1], isNull);
    expect(next[0]!.key, isNot(main.key));
  });
  test('cross-window sides allowed but another window addon rejected', () {
    final main = pool.firstWhere((e) => e.offer.window == '7号窗口' && e.offer.kind == 'main');
    final addon = pool.firstWhere((e) => e.offer.name == '加肉');
    final side = pool.firstWhere((e) => e.offer.name == '煎蛋（1个）');
    expect(draw([main, addon], budget: 3000).meal!.whereType<Entry>().length, 1);
    expect(draw([main, side], budget: 3000).meal!.whereType<Entry>().length, 2);
  });
  test('reroll cannot silently drop old extras to manufacture a changed meal', () {
    final main = pool.firstWhere((e) => e.offer.name == '小份牛肉面' && e.offer.channel == 'regular');
    final side = pool.firstWhere((e) => e.offer.name == '麻花（1根）');
    expect(draw([main,side], previous: [main,side,null], locks: {0}).meal, isNull);
  });
  test('unverified ingredients fail closed and fees never enter a meal', () {
    expect(recommend(pool, const MealRequest(budget: 5000, mode: MealMode.mainWithSides,
      excludedFoods: {'鸡蛋'}), Random()).meal, isNull);
    final main = pool.firstWhere((e) => e.offer.name == '小份牛肉面' && e.offer.channel == 'regular');
    final fee = pool.firstWhere((e) => e.offer.kind == 'fee');
    expect(draw([main,fee]).meal!.whereType<Entry>().length, 1);
  });
}
