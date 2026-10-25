import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/rice_panel.dart';

void main() {
  testWidgets('manual selection can be locked while random fills other cooked dishes', (tester) async {
    const plan = RicePlan(id:'fixture',name:'测试套餐',location:'测试窗口',priceCents:900,
      labels:['大荤','小荤','素菜'],options:[['测试菜A','测试菜B'],['测试菜C'],['测试菜D']]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      RicePanel(plans: const [('personal:fixture',plan)],budget:900,savePersonal: (_) async => true)))));
    expect(find.text('选择米饭套餐'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first); await tester.pumpAndSettle();
    await tester.tap(find.text('测试菜A').last); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rice-lock-0'))); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('随机未锁定菜位')); await tester.tap(find.text('随机未锁定菜位')); await tester.pumpAndSettle();
    final fields = tester.widgetList<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>)).toList();
    expect(fields[0].initialValue,'测试菜A'); expect(fields[1].initialValue,'测试菜C'); expect(fields[2].initialValue,'测试菜D');
    expect(tester.takeException(),isNull);
  });
}
