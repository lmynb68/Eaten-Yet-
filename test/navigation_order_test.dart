import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/navigation_order.dart';

void main() {
  test('restores order and repairs unknown or repeated identifiers', () async {
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',
      navigationOrderKey: ['favorites', 'unknown', 'favorites', 'stores'],
    });
    final prefs = await SharedPreferences.getInstance();
    expect(readNavigationOrder(prefs), [4, 2, 0, 1, 3]);
    await saveNavigationOrder(prefs, [3, 4, 2, 1, 0]);
    expect(readNavigationOrder(prefs), [3, 4, 2, 1, 0]);
    await prefs.remove(navigationOrderKey);
    expect(readNavigationOrder(prefs), [0, 1, 2, 3, 4]);
  });

  testWidgets('long press reorders without selecting a different page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var order = [0, 1, 2, 3, 4];
    var selected = 0;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      return Scaffold(bottomNavigationBar: SortableNavigationBar(
        order: order, selected: selected,
        onSelected: (id) => setState(() => selected = id),
        onReorder: (oldIndex, newIndex) => setState(() {
          order = List<int>.of(order);
          order.insert(newIndex, order.removeAt(oldIndex));
        }),
      ));
    })));
    final first = find.byKey(const ValueKey('navigation-meal'));
    final last = find.byKey(const ValueKey('navigation-favorites'));
    final target = tester.getCenter(first);
    final gesture = await tester.startGesture(tester.getCenter(last));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(order.first, 4);
    expect(selected, 0);
    expect(tester.getCenter(last).dx, lessThan(tester.getCenter(first).dx));
    await tester.tap(find.text('我的喜爱'));
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(tester.takeException(), isNull);
  });
}
