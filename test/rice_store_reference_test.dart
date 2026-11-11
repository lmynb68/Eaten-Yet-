import 'dart:convert';
import 'dart:io';

import 'package:eat_what/domain.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/main.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/rice_panel.dart';
import 'package:eat_what/snacks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final officialText = File('assets/official.json').readAsStringSync();
  final official = MenuDb.decode(officialText, Source.official);

  Future<void> start(
    WidgetTester tester, {
    MenuDb? personal,
    List<String> installedStores = const ['sf'],
  }) async {
    SharedPreferences.setMockInitialValues({
      'eat_what.meal_period': 'lunch',
      MenuRepository.storageKey: jsonEncode({
        'official': officialText,
        'personal': (personal ?? MenuDb.empty(Source.personal)).encode(),
        'installedStores': installedStores,
      }),
    });
    rootBundle.clear();
    await tester.pumpWidget(const EatWhatApp());
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('今天，吃什么？'), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    for (var i = 0; i < 100 && find.text('正在选菜…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> filter(WidgetTester tester, String scope) async {
    await tap(tester, find.byKey(const ValueKey('meal-filters')));
    await tap(tester, find.text(scope).last);
    await tap(tester, find.text('应用筛选'));
  }

  testWidgets(
      'copying an official rice plan keeps shop, snacks, favorites and history in my menu',
      (tester) async {
    await start(tester);
    await tap(tester, find.byKey(const ValueKey('meal-category-rice')));
    await tap(tester, find.text('复制到我的菜单并编辑'));
    await tap(tester, find.text('保存到我的菜单'));
    await tester.pump(const Duration(seconds: 1));

    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(preferences.getString(MenuRepository.storageKey)!)
        as Map<String, dynamic>;
    final personal =
        MenuDb.decode(saved['personal'] as String, Source.personal);
    expect(personal.ricePlans, hasLength(1));
    expect(personal.places, isEmpty);
    expect(personal.ricePlans.single.storeKey, 'official:sf');

    await filter(tester, '我的菜单');
    await tap(tester, find.byKey(const ValueKey('meal-filters')));
    await tap(tester, find.text('食味坊').last);
    await tap(tester, find.text('应用筛选'));
    final panel = tester.widget<RicePanel>(find.byType(RicePanel));
    expect(panel.plans, hasLength(1));
    expect(panel.plans.single.$1, startsWith('personal:'));
    expect(panel.stores['official:sf'], '食味坊');
    expect(
        panel.snacks
            .every((entry) => entry.offer.mealPeriods.contains('lunch')),
        isTrue);
    expect(find.text('这个套餐还没选店铺，先选一家。'), findsNothing);

    await tap(tester, find.text('自由选菜'));
    await tap(tester, find.text('随机其余菜品'));
    await tap(tester, find.text('随机小食'));
    final snackPanel = tester.widget<SnackPanel>(find.byType(SnackPanel));
    expect(snackPanel.placeKey, 'official:sf');
    expect(snackPanel.selected, isNotNull);
    expect(snackPanel.selected!.placeKey, 'official:sf');

    await tap(tester, find.byKey(const Key('meal-favorite')));
    final favorite = (await FavoriteStore.load(preferences)).meals.single;
    expect(favorite.storeKey, 'official:sf');
    expect(favorite.storeName, '食味坊');
    expect(favorite.items.any((item) => item.key == snackPanel.selected!.key),
        isTrue);

    await tap(tester, find.text('记录这一顿'));
    await tap(tester, find.text('保存').last);
    final record = (await HistoryStore.load(preferences)).records.single;
    expect(record.meal.toJson()..remove('savedAt'),
        favorite.toJson()..remove('savedAt'));

    await filter(tester, '官方菜单');
    expect(
        tester
            .widget<RicePanel>(find.byType(RicePanel))
            .plans
            .every((plan) => plan.$1.startsWith('official:')),
        isTrue);
    await filter(tester, '我的菜单');
    await tap(tester, find.byKey(const ValueKey('meal-category-main')));
    await tap(tester, find.text('随机一份'));
    expect(find.byType(SnackPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a personal plan does not restore an official shop removed from the active menu',
      (tester) async {
    final original =
        official.ricePlans.firstWhere((plan) => plan.storeKey == 'official:sf');
    final personal = MenuDb(
        source: Source.personal,
        revision: 1,
        places: [],
        foods: [],
        offers: [],
        ricePlans: [
          RicePlan.fromJson({...original.toJson(), 'id': 'copied_sf_plan'}),
        ]);
    await start(tester, personal: personal, installedStores: ['community']);
    await tap(tester, find.byKey(const ValueKey('meal-category-rice')));
    await filter(tester, '我的菜单');
    final panel = tester.widget<RicePanel>(find.byType(RicePanel));
    expect(panel.plans, hasLength(1));
    expect(panel.stores, isNot(contains('official:sf')));
    expect(
        panel.snacks.any((entry) => entry.placeKey == 'official:sf'), isFalse);
    expect(find.text('这个套餐还没选店铺，先选一家。'), findsOneWidget);
    expect(find.byType(SnackPanel), findsNothing);
    expect(find.byKey(const Key('meal-favorite')), findsNothing);
    expect(find.text('记录这一顿'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
