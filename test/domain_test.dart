import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/domain.dart';

void main() {
  final official = MenuDb.decode(File('test/fixtures/demo-v1.json').readAsStringSync(), Source.official);
  final personal = MenuDb.empty(Source.personal);
  final pool = entries(official, personal, Scope.official);
  test('money parser preserves cents and rejects malformed numbers', () {
    expect(parseMoney('12.01'), 1201); expect(parseMoney('0.1'), 10);
    for (final s in ['NaN', '-1', '2.001', '1e4', '']) { expect(parseMoney(s), isNull); }
  });
  test('seeded recommendations obey budget, unique items, role coverage and same store', () {
    for (var seed = 0; seed < 100; seed++) {
      final result = recommend(pool, const MealRequest(budget: 1600), Random(seed));
      final meal = result.meal!.cast<Entry>();
      expect(meal.length, 3);
      expect(meal.map((e) => e.key).toSet().length, 3);
      expect(meal.fold<int>(0, (s, e) => s + e.offer.priceCents), lessThanOrEqualTo(1600));
      expect(meal.map((e) => e.placeKey).toSet().length, 1);
      expect(meal.expand((e) => e.offer.roles).toSet(), containsAll(roleNames.keys));
    }
  });
  test('two locks keep identity, position, portion and price; third actually changes', () {
    final old = recommend(pool, const MealRequest(budget: 2200), Random(1)).meal!.cast<Entry>();
    final next = recommend(pool, MealRequest(budget: 2200, previous: old, locked: {0, 1}), Random(2)).meal!.cast<Entry>();
    expect(identical(next[0], old[0]), isTrue); expect(identical(next[1], old[1]), isTrue);
    expect(next[2].key, isNot(old[2].key));
  });
  test('impossible budgets and all locks do not mutate previous selection', () {
    final old = recommend(pool, const MealRequest(budget: 2000), Random(1)).meal!.cast<Entry>();
    expect(recommend(pool, MealRequest(budget: 1, previous: old, locked: {0}), Random(1)).meal, isNull);
    expect(recommend(pool, MealRequest(budget: 2000, previous: old, locked: {0,1,2}), Random(1)).message, contains('都已锁定'));
    expect(old.length, 3);
  });
  test('changed price, removed source and unavailable locked items are rejected', () {
    final old = recommend(pool, const MealRequest(budget: 2000), Random(1)).meal!.cast<Entry>();
    final changed = old[0].offer.toJson()..['priceCents'] = 1;
    final updated = pool.map((e) => e.key == old[0].key ? Entry(Offer.fromJson(changed), official) : e).toList();
    expect(recommend(updated, MealRequest(budget: 2000, previous: old, locked: {0}), Random()).meal, isNull);
    expect(recommend([], MealRequest(budget: 2000, previous: old, locked: {0}), Random()).meal, isNull);
    changed['available'] = false;
    final unavailable = pool.map((e) => e.key == old[0].key ? Entry(Offer.fromJson(changed), official) : e).toList();
    expect(recommend(unavailable, MealRequest(budget: 2000, previous: old, locked: {0}), Random()).meal, isNull);
  });
  test('excluded foods and unknown ingredients fail closed when exclusion is active', () {
    final result = recommend(pool, const MealRequest(budget: 2200, excludedFoods: {'鸡蛋', '鸡肉'}), Random(4));
    expect(result.meal, isNotNull);
    expect(result.meal!.whereType<Entry>().expand((e) => e.foodNames), isNot(contains('鸡蛋')));
    final unknown = pool.map((e) => Entry(Offer.fromJson(e.offer.toJson()..['ingredientsKnown'] = false), official)).toList();
    expect(recommend(unknown, const MealRequest(budget: 2200, excludedFoods: {'鸡蛋'}), Random()).meal, isNull);
  });
  test('source namespace isolates IDs and personal-only stays empty', () {
    final p = MenuDb(source: Source.personal, revision: 1, places: official.places, foods: official.foods, offers: official.offers);
    final both = entries(official, p, Scope.merged);
    expect(both.map((e) => e.key).toSet().length, pool.length * 2);
    expect(entries(official, personal, Scope.personal), isEmpty);
  });
  test('JSON round trip and validation enforce reference integrity', () {
    expect(MenuDb.decode(official.encode(), Source.official).offers.length, 16);
    expect(() => MenuDb.decode(official.encode(), Source.personal), throwsFormatException);
    final broken = MenuDb(source: Source.official, revision: 1, places: [], foods: official.foods, offers: official.offers);
    expect(broken.validate, throwsFormatException);
    final duplicate = MenuDb(source: Source.official, revision: 1, places: official.places, foods: official.foods, offers: [official.offers.first, official.offers.first]);
    expect(duplicate.validate, throwsFormatException);
  });
  test('search limit reports uncertainty, not proven infeasibility', () {
    final result = recommend(pool, const MealRequest(budget: 2200), Random(0), nodeLimit: 1);
    expect(result.limited, isTrue); expect(result.message, contains('搜索达到上限'));
  });
  test('no reroll alternative returns no replacement', () {
    final one = [pool[0], pool[2], pool[5]];
    expect(recommend(one, MealRequest(budget: 2000, previous: one, locked: {0,1}), Random()).meal, isNull);
  });
}
