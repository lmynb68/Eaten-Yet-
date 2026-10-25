import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/main.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/snacks.dart';
import 'package:eat_what/rice_panel.dart';

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',}); rootBundle.clear(); });
  Future<void> start(WidgetTester tester, {String? onlyStore}) async {
    if (onlyStore != null) {
      SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
        'official':File('assets/official.json').readAsStringSync(),
        'personal':MenuDb.empty(Source.personal).encode(), 'installedStores':[onlyStore],
      })});
    }
    await tester.pumpWidget(const EatWhatApp());
    for (var i=0;i<100;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.text('今天，吃什么？'),findsOneWidget);
    await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
  }
  for (final store in ['community','jml']) {
    testWidgets('$store never offers rice selection', (tester) async {
      await start(tester,onlyStore:store);
      expect(find.byKey(const ValueKey('meal-category-rice')), findsNothing);
    });
  }
  testWidgets('rice filters only show stores with eligible rice menus', (tester) async {
    await start(tester);
    await tap(tester, find.byKey(const ValueKey('meal-category-rice')));
    await tap(tester, find.byKey(const ValueKey('meal-filters')));
    final sheet = find.byType(BottomSheet);
    final labels = tester.widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text)))
      .map((text) => text.data ?? '').join(' ');
    expect(labels, contains('食味坊'));
    expect(labels, isNot(contains('社区食堂')));
    expect(labels, isNot(contains('牛肉面')));
    expect(labels, isNot(contains('主食分类')));
    expect(labels, isNot(contains('筛选店铺和主餐')));
    expect(tester.takeException(), isNull);
  });
  testWidgets('catalog store sheet filters offers and rice dishes together', (tester) async {
    await start(tester);
    await tap(tester, find.text('餐品菜单').last);
    await tap(tester, find.byKey(const ValueKey('catalog-filters')));
    await tap(tester, find.text('食味坊'));
    await tap(tester, find.text('应用筛选'));
    expect(find.text('228 个售卖项'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('catalog-filters')));
    await tap(tester, find.text('重置'));
    await tap(tester, find.text('应用筛选'));
    expect(find.text('1666 个售卖项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('main survives switching to sides; candidates stay in the main store', (tester) async {
    await start(tester,onlyStore:'sf');
    await tap(tester,find.text('随机一份'));
    final before = tester.widget<SnackPanel>(find.byType(SnackPanel));
    expect(before.placeKey,'official:sf');
    await tap(tester,find.byKey(const ValueKey('meal-category-side')));
    final after = tester.widget<SnackPanel>(find.byType(SnackPanel));
    expect(after.placeKey,before.placeKey); expect(after.mainPrice,before.mainPrice);
    await tap(tester,find.text('选择小食'));
    final dialog=find.byType(AlertDialog);
    final subtitles = tester.widgetList<Text>(find.descendant(of:dialog,matching:find.byType(Text)))
      .map((t)=>t.data ?? '').join(' ');
    expect(subtitles, isNot(contains('社区食堂')));
    expect(subtitles, isNot(contains('牛肉面中北大学店')));
    expect(tester.takeException(),isNull);
  });
  testWidgets('standalone sides have a store filter and can be liked', (tester) async {
    await start(tester);
    await tap(tester,find.byKey(const ValueKey('meal-category-side')));
    await tap(tester,find.byKey(const ValueKey('side-store-null')));
    await tap(tester,find.text('社区食堂').last);
    await tap(tester,find.text('随机小食'));
    await tap(tester,find.text('满意，收藏这一顿'));
    await tap(tester,find.text('我的喜爱').last);
    expect(find.text('社区食堂 · 小食'),findsOneWidget);
    final store=await FavoriteStore.load(await SharedPreferences.getInstance());
    expect(store.meals.single.storeKey,'official:community');
    await tap(tester,find.byKey(const Key('preference-learning')));
    expect((await FavoriteStore.load(await SharedPreferences.getInstance())).enabled,isFalse);
    expect(tester.takeException(),isNull);
  });
  testWidgets('rice auto opens and selected dishes persist into same-store sides', (tester) async {
    await start(tester,onlyStore:'sf');
    await tap(tester,find.byKey(const ValueKey('meal-category-rice')));
    expect(find.text('选择米饭套餐'),findsNothing);
    await tap(tester,find.text('随机未锁定菜位'));
    final names = tester.widgetList<DropdownButtonFormField<String>>(find.descendant(
      of:find.byType(RicePanel),matching:find.byType(DropdownButtonFormField<String>)))
      .map((w)=>w.initialValue).whereType<String>().toList();
    expect(names.length,3);
    await tap(tester,find.byKey(const ValueKey('meal-category-side')));
    expect(tester.widget<SnackPanel>(find.byType(SnackPanel)).placeKey,'official:sf');
    for (final name in names) { expect(find.textContaining(name),findsOneWidget); }
    await tap(tester,find.text('满意，收藏这一顿'));
    final saved=await FavoriteStore.load(await SharedPreferences.getInstance());
    expect(saved.meals.single.items.map((i)=>i.name).toSet(),names.toSet());
    expect(saved.meals.single.ricePrice,100);
    expect(tester.takeException(),isNull);
  });
}
