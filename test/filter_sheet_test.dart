import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/filter_sheet.dart';

void main() {
  testWidgets('filter sheet cancels drafts and applies a valid source/store pair on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    BrowseFilters? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async { result = await showBrowseFilters(context, scope: Scope.merged, staple: 'all', store: null,
        stores: {'official:sf': '食味坊', 'personal:test': '我的店铺'}); }, child: const Text('打开'))))));
    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text)); await tester.pumpAndSettle();
    }
    await tap('打开');
    expect(tester.getRect(find.widgetWithText(FilledButton, '应用筛选')).bottom, lessThanOrEqualTo(776));
    await tap('食味坊');
    await tester.tap(find.byTooltip('关闭')); await tester.pumpAndSettle();
    expect(result, isNull);
    await tap('打开'); await tap('食味坊'); await tap('仅个人库');
    expect(find.text('食味坊'), findsNothing);
    await tap('应用筛选');
    expect(result!.scope, Scope.personal); expect(result!.store, isNull);
    expect(tester.takeException(), isNull);
  });
}
