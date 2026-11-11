import 'package:eat_what/meal_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final invalidValues = <String, Object>{
    'boolean': true,
    'integer': 123,
    'double': 6.5,
    'string list': <String>['lunch'],
    'malformed JSON': '{broken',
    'JSON list': '["lunch"]',
    'wrong field types':
        '{"mode":true,"breakfast":"300","lunch":600,"dinner":960}',
  };

  for (final entry in invalidValues.entries) {
    test('${entry.key} uses defaults and can be repaired durably', () async {
      SharedPreferences.setMockInitialValues({mealPeriodKey: entry.value});
      final prefs = await SharedPreferences.getInstance();
      expect(readMealChoice(prefs), 'auto');
      expect(hasMealChoice(prefs), isFalse);
      expect(readMealSchedule(prefs).starts, const MealSchedule().starts);
      // Merely opening settings must not erase the original value.
      expect(prefs.get(mealPeriodKey), entry.value);

      const schedule = MealSchedule(breakfast: 360, lunch: 660, dinner: 1020);
      await saveMealConfig(prefs, 'dinner', schedule);
      await prefs.reload();
      expect(hasMealChoice(prefs), isTrue);
      expect(readMealChoice(prefs), 'dinner');
      expect(readMealSchedule(prefs).starts, schedule.starts);
    });
  }

  for (final name in ['boolean', 'integer', 'string list']) {
    testWidgets('settings repair a $name value after cancel and reopen', (
      tester,
    ) async {
      final raw = invalidValues[name]!;
      SharedPreferences.setMockInitialValues({mealPeriodKey: raw});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMealChoice(context, prefs),
              child: const Text('打开餐次'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('打开餐次'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      final autoChoice = find.byKey(const ValueKey('meal-choice-auto'));
      expect(
        find.descendant(
          of: autoChoice,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await prefs.reload();
      expect(prefs.get(mealPeriodKey), raw);

      await tester.tap(find.text('打开餐次'));
      await tester.pumpAndSettle();
      final lunchChoice = find.byKey(const ValueKey('meal-choice-lunch'));
      await tester.ensureVisible(lunchChoice);
      await tester.tap(lunchChoice);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await prefs.reload();
      expect(readMealChoice(prefs), 'lunch');
      expect(readMealSchedule(prefs).starts, const MealSchedule().starts);
      expect(hasMealChoice(prefs), isTrue);

      await tester.tap(find.text('打开餐次'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: lunchChoice,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
