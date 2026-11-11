import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/history_page.dart';
import 'package:eat_what/rice_panel.dart';
import 'history_quantity_test.dart' show meal, plan;
import 'save_failure_test.dart' show FailingPreferences;

void main() {
  testWidgets('free rice starts with one dish and supports adding and removing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      RicePanel(plans: const [('personal:s', plan)], budget: 5000, savePersonal: (_) async => true)))));
    await tester.tap(find.text('自由选菜'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.ensureVisible(find.text('添加一道菜'));
    await tester.tap(find.text('添加一道菜'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    await tester.ensureVisible(find.text('移除这道菜').last);
    await tester.tap(find.text('移除这道菜').last);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, '移除这道菜'));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing stars and review persists after reopening history', (tester) async {
    final prefs = FailingPreferences();
    final store = await HistoryStore.load(prefs);
    await store.add(meal());
    await tester.pumpWidget(MaterialApp(home: HistoryPage(store: store)));
    await tester.tap(find.text('编辑评价'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('4 星'));
    await tester.enterText(find.byType(TextField), '下次还吃');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final reloaded = await HistoryStore.load(prefs);
    await tester.pumpWidget(MaterialApp(home: HistoryPage(key: UniqueKey(), store: reloaded)));
    await tester.pumpAndSettle();
    expect(find.text('★★★★'), findsOneWidget);
    expect(find.text('下次还吃'), findsOneWidget);
    expect(reloaded.records.single.meal.items.single.quantity, 2);
    expect(tester.takeException(), isNull);
  });
}
