import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/language.dart';
import 'package:eat_what/snacks.dart';
import 'package:eat_what/meal_filter.dart';
import 'package:eat_what/rice.dart';

void main() {
  Offer offer(String id, int price, {bool addon = false, String photo = ''}) => Offer(
    id: id, placeId: 'p', name: id, portion: '1', priceCents: price,
    roles: {}, foodIds: {}, updatedAt: '2026-10-15', kind: 'side', addonOnly: addon, photo: photo);
  MenuDb db(List<Offer> offers) => MenuDb(source: Source.personal, revision: 1,
    places: [const Place('p','Store','Campus')], foods: [], offers: offers);
  test('optional snacks fit remaining budget and exclude add-on-only items', () {
    final menu = db([offer('egg',200),offer('dumpling',500),offer('addon',100,addon:true)]);
    final pool = menu.offers.map((o) => Entry(o,menu)).toList();
    expect(snackChoices(pool,1500,1300).map((e) => e.offer.id),['egg']);
    expect(snackChoices(pool,1300,1300),isEmpty);
    expect(snackChoices(pool,1800,1300).length,2);
  });
  test('snacks from a different store or library are excluded', () {
    final menu = db([offer('egg',200)]);
    final other=MenuDb(source: Source.official, revision: 1, places: menu.places, foods: [], offers: menu.offers);
    final pool=[Entry(menu.offers.single,menu),Entry(other.offers.single,other)];
    expect(snackChoices(pool,2000,1000,placeKey:'personal:p').map((e) => e.key),['personal:egg']);
    expect(snackChoices(pool,2000,1000,placeKey:'personal:unknown'),isEmpty);
    expect(mealCostWithSnack(pool.first,pool.first),400);
    expect(mealCostWithSnack(pool.first,pool.last),200);
  });
  test('meal filter distinguishes unrestricted, empty and multi-select', () {
    expect(matchesMealFilter(null,'a'),isTrue);
    expect(matchesMealFilter({},'a'),isFalse);
    expect(matchesMealFilter({'a','b'},'a'),isTrue);
    expect(matchesMealFilter({'a','b'},'c'),isFalse);
  });
  test('rice store resolution is conservative and explicit link survives JSON', () {
    const rice=RicePlan(id:'r',name:'Rice',location:'食味坊1号窗口',priceCents:1000,
      labels:['a','b','c'],options:[[],[],[]]);
    expect(riceStoreKey(rice,{'official:sf':'食味坊'}),'official:sf');
    expect(riceStoreKey(rice,{'official:sf':'食味坊','personal:sf':'食味坊'}),isNull);
    final linked=RicePlan.fromJson({...rice.toJson(),'storeKey':'official:sf'});
    expect(riceStoreKey(linked,{'official:sf':'食味坊','personal:sf':'食味坊'}),'official:sf');
  });
  testWidgets('store checkbox selects its meals and cancel preserves the caller filter', (tester) async {
    Set<String>? result;
    const targets=[MealTarget('a','s1','Store A','Meal A'),MealTarget('b','s1','Store A','Meal B'),MealTarget('c','s2','Store B','Meal C')];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result=await showMealFilter(context,targets,{'c'}); }, child: const Text('Filter'))))));
    await tester.tap(find.text('Filter')); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('filter-store-s1')),matching:find.byType(Checkbox)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选')); await tester.pumpAndSettle();
    expect(result,{'a','b','c'});
    await tester.tap(find.text('Filter')); await tester.pumpAndSettle();
    await tester.tap(find.text('清空选择')); await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选')); await tester.pumpAndSettle();
    expect(result,isEmpty);
    await tester.tap(find.text('Filter')); await tester.pumpAndSettle();
    await tester.tap(find.text('取消')); await tester.pumpAndSettle();
    expect(result,isNull);
  });
  test('photo survives export and import; legacy entries need no photo', () {
    final encoded = base64Encode([1,2,3]);
    final restored = MenuDb.decode(db([offer('egg',200,photo:encoded)]).encode(),Source.personal);
    expect(restored.offers.single.photo,encoded);
    final legacy=offer('legacy',100).toJson()..remove('photo');
    expect(Offer.fromJson(legacy).photo,isEmpty);
  });
  testWidgets('language switches on screen and survives a new controller', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller=LanguageController();
    await controller.load();
    await tester.pumpWidget(LanguageScope(controller: controller, child: const MaterialApp(home: SettingsPage())));
    expect(find.text('设置'),findsOneWidget);
    await tester.tap(find.text('English')); await tester.pumpAndSettle();
    expect(find.text('Settings'),findsOneWidget);
    final restored=LanguageController(); await restored.load();
    expect(restored.code,'en'); restored.dispose();
    await tester.tap(find.text('简体中文')); await tester.pumpAndSettle();
    expect(find.text('设置'),findsOneWidget);
    await tester.pumpWidget(const SizedBox()); controller.dispose();
  });
}
