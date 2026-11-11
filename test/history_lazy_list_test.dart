import 'dart:collection';
import 'dart:convert';

import 'package:eat_what/favorites.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'save_failure_test.dart' show FailingPreferences;

MealHistory record(int index) => MealHistory(
      id: 'record-$index',
      meal: FavoriteMeal(
        storeKey: 'personal:shop',
        storeName: '餐厅 $index',
        kind: '整份餐品',
        savedAt: '2026-11-10T12:00:00',
        ricePrice: 0,
        items: [FavoriteItem('dish', '午餐', 1500, quantity: 2)],
      ),
    );

String backup(Iterable<MealHistory> rows) => jsonEncode({
      'version': 1,
      'type': 'meal-history',
      'records': rows.map((row) => row.toJson()).toList(),
    });

// Count accesses rather than mounted cards: ListView(children: ...) mounts
// lazily too, but it eagerly reads every record and constructs all its widgets.
class ObservedRecords extends ListBase<MealHistory> {
  final List<MealHistory> source;
  final Set<String> accessed;
  ObservedRecords(this.source, this.accessed);

  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('Read only');
  @override
  MealHistory operator [](int index) {
    final row = source[index];
    accessed.add(row.id);
    return row;
  }

  @override
  void operator []=(int index, MealHistory value) =>
      throw UnsupportedError('Read only');
}

class ObservedHistoryStore implements HistoryStore {
  final HistoryStore inner;
  final Set<String> accessed = {};
  ObservedHistoryStore(this.inner);

  @override
  List<MealHistory> get records => ObservedRecords(inner.records, accessed);
  @override
  SharedPreferences get preferences => inner.preferences;
  @override
  bool get recoveryRequired => inner.recoveryRequired;
  @override
  set recoveryRequired(bool value) => inner.recoveryRequired = value;
  @override
  String export() => inner.export();
  @override
  Future<void> import(String text) => inner.import(text);
  @override
  Future<void> add(FavoriteMeal meal, {int stars = 0, String review = ''}) =>
      inner.add(meal, stars: stars, review: review);
  @override
  Future<void> edit(String id, int stars, String review) =>
      inner.edit(id, stars, review);
  @override
  Future<void> remove(String id) => inner.remove(id);
  @override
  Future<void> resetAfterBackup() => inner.resetAfterBackup();
}

void main() {
  testWidgets(
      '2000 history records build on demand and remain editable at the end', (
    tester,
  ) async {
    final prefs = FailingPreferences()
      ..disk[HistoryStore.storageKey] = backup(
        List.generate(HistoryStore.maxRecords, record),
      );
    final inner = await HistoryStore.load(prefs);
    final store = ObservedHistoryStore(inner);
    await tester.pumpWidget(MaterialApp(home: HistoryPage(store: store)));
    await tester.pumpAndSettle();

    expect(inner.records, hasLength(2000));
    expect(find.text('餐厅 0'), findsOneWidget);
    expect(store.accessed.length, lessThan(20));
    expect(find.text('餐厅 1999'), findsNothing);

    final lastCard = find.byKey(const ValueKey('record-1999'));
    for (var attempt = 0;
        attempt < 10 && lastCard.evaluate().isEmpty;
        attempt++) {
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(lastCard, findsOneWidget);
    expect(find.byType(Card).evaluate().length, lessThan(20));
    final edit = find.descendant(of: lastCard, matching: find.text('编辑评价'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('5 星'));
    await tester.enterText(find.byType(TextField), '最后一条也能编辑');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    final reloaded = await HistoryStore.load(prefs);
    expect(reloaded.records.last.stars, 5);
    expect(reloaded.records.last.review, '最后一条也能编辑');
    final remove = find.descendant(of: lastCard, matching: find.text('删除'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pumpAndSettle();

    expect(inner.records, hasLength(1999));
    expect(inner.records.any((row) => row.id == 'record-1999'), isFalse);
    expect((await HistoryStore.load(prefs)).records, hasLength(1999));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history keeps import and export controls available',
      (tester) async {
    final prefs = FailingPreferences();
    final store = await HistoryStore.load(prefs);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(MaterialApp(home: HistoryPage(store: store)));
    expect(find.text('还没有用餐历史。选好后点击“记录这一顿”。'), findsOneWidget);
    await tester.tap(find.text('导入用餐历史'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), backup([record(0)]));
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('餐厅 0'), findsOneWidget);
    expect(find.text('还没有用餐历史。选好后点击“记录这一顿”。'), findsNothing);
    await tester.tap(find.text('导出用餐历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(HistoryStore.decode(copied!).single.id, 'record-0');
    expect(tester.takeException(), isNull);
  });
}
