import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/main.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',});
    // Do not retain asset futures created in another widget test's fake-async zone.
    rootBundle.clear();
  });
  Future<void> startApp(WidgetTester tester) async {
    await tester.pumpWidget(const EatWhatApp());
    // Asset file I/O needs real event-loop time. pumpAndSettle advances the
    // fake clock while the loading spinner keeps scheduling frames.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing,
      reason: 'Menu loading did not finish within five seconds of real I/O time');
    expect(find.text('今天，吃什么？'), findsOneWidget,
      reason: 'The application must show the meal page, not a loading error');
    await tester.pumpAndSettle();
  }
  testWidgets('personal editor has photo space and separated fields on a small phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await startApp(tester);
    await tester.tap(find.text('菜单库')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加个人菜品'));
    await tester.tap(find.text('添加个人菜品')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('添加照片'), findsOneWidget);
    await tester.ensureVisible(find.text('价格渠道'));
    final type = tester.getRect(find.byType(DropdownButtonFormField<String>).first);
    final channel = tester.getRect(find.byType(DropdownButtonFormField<String>).last);
    expect(channel.top - type.bottom, greaterThanOrEqualTo(16));
    expect(find.text('保存'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('phone: select whole meal and navigate catalogs', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await startApp(tester);
    expect(find.text('包含抖音团购价'), findsNothing);
    await tester.ensureVisible(find.text('随机一份')); await tester.tap(find.text('随机一份')); await tester.pumpAndSettle();
    expect(find.textContaining('普通标价'), findsNothing);
    expect(find.text('自己选一份'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('meal-category-side')));
    await tester.tap(find.byKey(const ValueKey('meal-category-side'))); await tester.pumpAndSettle();
    expect(find.textContaining('当前主菜：'), findsOneWidget);
    expect(find.text('自己选小食'), findsNothing);
    await tester.ensureVisible(find.text('只买小食（结束当前搭配）'));
    await tester.tap(find.text('只买小食（结束当前搭配）')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('自己选小食'));
    await tester.tap(find.text('自己选小食')); await tester.pumpAndSettle();
    expect(find.text('招牌红烧肉饭'), findsNothing);
    expect(find.text('加肉'), findsNothing);
    await tester.tap(find.text('卤豆干').first); await tester.pumpAndSettle();
    expect(find.text('已手选小食。'), findsOneWidget);
    await tester.tap(find.text('餐品菜单')); await tester.pumpAndSettle(); expect(find.text('1666 个售卖项'), findsOneWidget);
    await tester.tap(find.text('店铺')); await tester.pumpAndSettle();
    expect(find.text('9 家店铺'), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-thumbnail')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('store-official:sf'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-cover')), findsOneWidget);
    expect(find.text('228 个售卖项'), findsOneWidget);
    expect(find.text('小份牛肉面'), findsNothing);
    await tester.tap(find.text('返回全部店铺')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('store-official:jml')));
    await tester.tap(find.byKey(const ValueKey('store-official:jml'))); await tester.pumpAndSettle();
    expect(find.text('29 个售卖项'), findsOneWidget);
    await tester.ensureVisible(find.text('小份牛肉面').first);
    await tester.tap(find.text('小份牛肉面').first); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭')); await tester.pumpAndSettle();
    await tester.tap(find.text('菜单库')); await tester.pumpAndSettle(); expect(find.text('添加个人菜品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('updates are opt-in from settings without a launch prompt', (tester) async {
    await startApp(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('设置')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('官方最新版本'));
    await tester.tap(find.text('官方最新版本')); await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('不会在启动时弹窗'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('catalog builds only visible cards and can scroll to the last dish', (tester) async {
    await startApp(tester);
    await tester.tap(find.text('餐品菜单')); await tester.pumpAndSettle();
    expect(find.byType(Card).evaluate().length, lessThan(50));
    expect(find.byKey(const ValueKey('official:community_10')), findsNothing);
    final scrollable = find.descendant(of: find.byKey(const PageStorageKey('catalog-scroll')),
      matching: find.byType(Scrollable)).first;
    // This item is now before the rice dishes, rather than at the scroll end.
    // Keep each drag shorter than the viewport so an intermediate card cannot
    // be skipped and disposed between observations of the lazy list.
    Future<void> reach(Finder target) async {
      final step = tester.getSize(scrollable).height / 3;
      for (var attempt = 0; attempt < 1400 && target.evaluate().isEmpty; attempt++) {
        await tester.drag(scrollable, Offset(0, -step));
        await tester.pumpAndSettle();
      }
      expect(target, findsOneWidget, reason: 'Expected catalog card was not reached');
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }
    await reach(find.byKey(const ValueKey('official:community_10')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('official:community_10')), findsOneWidget);
    expect(find.byType(Card).evaluate().length, lessThan(50));
    await reach(find.byKey(const ValueKey('rice-dish:official:sf:sf_w1_alacarte:土豆丝')));
    expect(find.byType(Card).evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
  });
  testWidgets('desktop layout uses navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await startApp(tester);
    expect(find.byType(NavigationRail), findsOneWidget); expect(tester.takeException(), isNull);
  });
  test('repository saves one source without overwriting the other', () async {
    final r = await MenuRepository.load();
    final original = r.official.encode();
    await r.replace(MenuDb(source: Source.personal, revision: 2, places: r.official.places, foods: r.official.foods, offers: r.official.offers));
    final reloaded = await MenuRepository.load();
    expect(reloaded.personal.offers.length, 1634); expect(reloaded.official.encode(), original);
  });
  test('old demo migrates without replacing personal data', () async {
    final demo = MenuDb.decode(File('test/fixtures/demo-v1.json').readAsStringSync(), Source.official);
    final personal = MenuDb(source: Source.personal, revision: 3, places: demo.places,
      foods: demo.foods, offers: demo.offers);
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey: jsonEncode({
      'official': demo.encode(), 'personal': personal.encode(),
    })});
    final r = await MenuRepository.load();
    expect(r.official.revision, 9);
    expect(r.personal.encode(), personal.encode());
  });
  test('an imported non-demo official library is preserved', () async {
    final real = MenuDb.decode(File('assets/official.json').readAsStringSync(), Source.official);
    final imported = MenuDb(source: Source.official, revision: 3, places: real.places,
      foods: real.foods, offers: [real.offers.first]);
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey: jsonEncode({
      'official': imported.encode(), 'personal': MenuDb.empty(Source.personal).encode(),
    })});
    final r = await MenuRepository.load();
    expect(r.official.encode(), imported.encode());
  });
}
