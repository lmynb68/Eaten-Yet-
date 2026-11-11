import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/history_page.dart';
import 'history_quantity_test.dart' show meal;
import 'save_failure_test.dart' show FailingPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final character in ['😀', '👨‍👩‍👧‍👦', 'e\u0301']) {
    test('review storage and import use visible character limit: $character',
        () async {
      final prefs = FailingPreferences();
      final store = await HistoryStore.load(prefs);
      final review = character * MealHistory.maxReviewCharacters;
      await store.add(meal(), stars: 5, review: review);
      final loaded = await HistoryStore.load(prefs);
      expect(loaded.recoveryRequired, isFalse);
      expect(loaded.records.single.review, review);
      final imported = await HistoryStore.load(FailingPreferences());
      await imported.import(loaded.export());
      expect(imported.records.single.review, review);
      final original = prefs.disk[HistoryStore.storageKey];
      await expectLater(
          store.edit(store.records.single.id, 1, '$review$character'),
          throwsFormatException);
      expect(prefs.disk[HistoryStore.storageKey], original);
      expect(store.records.single.review, review);
    });
  }

  testWidgets('1001 emoji review saves and survives reopening history',
      (tester) async {
    final prefs = FailingPreferences();
    final store = await HistoryStore.load(prefs);
    await store.add(meal());
    await tester.pumpWidget(MaterialApp(home: HistoryPage(store: store)));
    await tester.tap(find.text('编辑评价'));
    await tester.pumpAndSettle();
    final review = '😀' * 1001;
    await tester.enterText(find.byType(TextField), review);
    await tester.tap(find.byTooltip('4 星'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final loaded = await HistoryStore.load(prefs);
    expect(loaded.records.single.review, review);
    expect(loaded.records.single.stars, 4);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets('failed review save ($throws) retains editor and permits retry',
        (tester) async {
      final prefs = FailingPreferences()..throwOnFailure = throws;
      final store = await HistoryStore.load(prefs);
      await store.add(meal(), stars: 2, review: '原评价');
      final original = prefs.disk[HistoryStore.storageKey];
      await tester.pumpWidget(MaterialApp(home: HistoryPage(store: store)));
      await tester.tap(find.text('编辑评价'));
      await tester.pumpAndSettle();
      final review = '😀' * 1001;
      await tester.enterText(find.byType(TextField), review);
      await tester.tap(find.byTooltip('5 星'));
      prefs.failNext = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          review);
      expect(find.byIcon(Icons.star), findsNWidgets(5));
      expect(find.text('评价保存失败，内容已保留，请重试。'), findsOneWidget);
      expect(prefs.disk[HistoryStore.storageKey], original);
      expect(store.records.single.review, '原评价');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final loaded = await HistoryStore.load(prefs);
      expect(loaded.records.single.review, review);
      expect(loaded.records.single.stars, 5);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending review save blocks repeated submission and dismiss',
      (tester) async {
    final pending = Completer<void>();
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showMealReview(context, onSave: (_, __) {
                            saves++;
                            return pending.future;
                          }),
                      child: const Text('评价')),
                ))));
    await tester.tap(find.text('评价'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '请保留');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  for (final value in [double.infinity, double.negativeInfinity, double.nan]) {
    test('non-finite history value $value can be exported and safely reset',
        () async {
      SharedPreferences.setMockInitialValues({HistoryStore.storageKey: value});
      final prefs = await SharedPreferences.getInstance();
      final store = await HistoryStore.load(prefs);
      expect(store.recoveryRequired, isTrue);
      final raw = store.export();
      expect(jsonDecode(raw), {'type': 'double', 'value': value.toString()});
      await store.resetAfterBackup();
      final backupKey =
          '${HistoryStore.storageKey}.recovery.${sha256.convert(utf8.encode(raw))}';
      expect(prefs.getString(backupKey), raw);
      expect(store.recoveryRequired, isFalse);
      expect(store.records, isEmpty);
      final loaded = await HistoryStore.load(prefs);
      expect(loaded.recoveryRequired, isFalse);
      expect(loaded.records, isEmpty);
    });
  }
}
