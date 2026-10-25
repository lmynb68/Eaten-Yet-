import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/meal_period.dart';
import 'package:eat_what/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('custom minute boundaries, overnight dinner and invalid schedule', () async {
    const schedule=MealSchedule(breakfast:390,lunch:675,dinner:1050);
    expect(schedule.valid,isTrue);
    for(final row in [(6,29,'dinner'),(6,30,'breakfast'),(11,14,'breakfast'),(11,15,'lunch'),(17,29,'lunch'),(17,30,'dinner'),(0,0,'dinner')]) {
      expect(clockPeriod(DateTime(2026,10,22,row.$1,row.$2),schedule),row.$3);
    }
    expect(const MealSchedule(breakfast:600,lunch:600).valid,isFalse);
    expect(const MealSchedule(breakfast:700,lunch:600).valid,isFalse);
    SharedPreferences.setMockInitialValues({mealPeriodKey:'lunch'});
    final prefs=await SharedPreferences.getInstance();
    expect(readMealSchedule(prefs).breakfast,300);
    await saveMealConfig(prefs,'auto',schedule);await prefs.reload();
    expect(readMealChoice(prefs),'auto');expect(readMealSchedule(prefs).starts,[390,675,1050]);
    await saveMealConfig(prefs,'dinner',schedule);
    expect(readMealChoice(prefs),'dinner');expect(readMealSchedule(prefs).starts,[390,675,1050]);
  });
  test('local clock boundaries including midnight', () {
    for(final row in [(4,59,'dinner'),(5,0,'breakfast'),(9,59,'breakfast'),(10,0,'lunch'),(15,59,'lunch'),(16,0,'dinner'),(0,0,'dinner')]) {
      expect(clockPeriod(DateTime(2026,10,22,row.$1,row.$2)),row.$3);
    }
  });
  test('manual selection survives preferences reload; invalid setting prompts again', () async {
    SharedPreferences.setMockInitialValues({mealPeriodKey:'breakfast'});
    var prefs=await SharedPreferences.getInstance();
    expect(hasMealChoice(prefs),isTrue);
    expect(readMealChoice(prefs),'breakfast');
    await prefs.reload();expect(readMealChoice(prefs),'breakfast');
    await prefs.setString(mealPeriodKey,'invalid');expect(hasMealChoice(prefs),isFalse);
  });
  test('official meal classifications retain user rules and roundtrip', () {
    final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
    db.validate();
    expect(MenuDb.decode(db.encode(),Source.official).encode(),db.encode());
    expect(db.offers.where((o)=>!{'wy','btk','btz'}.contains(o.placeId)).every((o)=>!o.mealPeriods.contains('breakfast')),isTrue);
    expect(db.offers.singleWhere((o)=>o.placeId=='wy' && o.name=='紫薯包').mealPeriods,{'breakfast'});
    expect(db.offers.singleWhere((o)=>o.placeId=='btk' && o.name=='早餐汉堡＋牛奶').available,isFalse);
    expect(db.offers.singleWhere((o)=>o.placeId=='btz' && o.name=='狗不理小笼包').mealPeriods,{'breakfast','lunch','dinner'});
  });
  Future<void> loadApp(WidgetTester tester) async {
    await tester.pumpWidget(const EatWhatApp());
    for(var i=0;i<100;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
      await tester.pump();
      if(find.byType(CircularProgressIndicator).evaluate().isEmpty && find.text('今天，吃什么？').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
  }
  testWidgets('custom times persist and cancelling settings keeps saved times', (tester) async {
    SharedPreferences.setMockInitialValues({mealPeriodKey:'auto'});
    final prefs=await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(
      body:TextButton(onPressed:()=>showMealChoice(context,prefs),child:const Text('打开餐次'))))));
    await tester.tap(find.text('打开餐次'));await tester.pumpAndSettle();
    final breakfast=find.byKey(const ValueKey('meal-time-0'));
    await tester.ensureVisible(breakfast);await tester.tap(breakfast);await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));await tester.pumpAndSettle();
    final fields=find.byType(TextFormField);
    await tester.enterText(fields.at(0),'06');
    await tester.enterText(fields.at(1),'30');
    await tester.tap(find.text('OK'));await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));await tester.pumpAndSettle();
    await prefs.reload();expect(readMealSchedule(prefs).starts,[390,600,960]);
    await tester.tap(find.text('打开餐次'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('恢复默认时段'));
    await tester.tap(find.text('恢复默认时段'));await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));await tester.pumpAndSettle();
    expect(readMealSchedule(prefs).starts,[390,600,960]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('first prompt saves manual breakfast, restart skips prompt, settings can change it', (tester) async {
    SharedPreferences.setMockInitialValues({});rootBundle.clear();
    await loadApp(tester);
    expect(find.text('选择餐次方式'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('meal-choice-breakfast')));
    await tester.tap(find.text('保存'));await tester.pumpAndSettle();
    expect(readMealChoice(await SharedPreferences.getInstance()),'breakfast');
    expect(find.textContaining('当前：早餐'),findsOneWidget);
    expect(find.byKey(const ValueKey('meal-category-rice')),findsNothing);
    await tester.pumpWidget(const SizedBox());await tester.pump();rootBundle.clear();
    await loadApp(tester);expect(find.text('选择餐次方式'),findsNothing);
    await tester.tap(find.byTooltip('设置'));await tester.pumpAndSettle();
    await tester.tap(find.text('餐次设置'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('meal-choice-dinner')));
    await tester.tap(find.byKey(const ValueKey('meal-choice-dinner')));
    await tester.tap(find.text('保存'));await tester.pumpAndSettle();
    expect(readMealChoice(await SharedPreferences.getInstance()),'dinner');
    await tester.tap(find.byType(BackButton));await tester.pumpAndSettle();
    expect(find.textContaining('当前：晚餐'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await tester.pump();
  });
}
