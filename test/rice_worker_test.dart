import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/rice_panel.dart';
import 'package:eat_what/rice_worker.dart';

void main() {
  test('real twenty-dish worker keeps budget and uniqueness with bounded scoring', () {
    final db = MenuDb.decode(File('assets/official.json').readAsStringSync(), Source.official);
    final plan = db.ricePlans.firstWhere((p) => p.id == 'sf_w1_alacarte');
    for (final count in [3,20]) {
      final watch = Stopwatch()..start();
      final result = calculateRice({'plan':plan.toJson(),'budget':1000000,'dishes':List<String?>.filled(count,null),
        'locked':<int>[],'free':true,'meatCount':null,'quantities':List.filled(count,1),'baseQuantity':1,
        'seed':1,'preferences':{'enabled':true,'dishes':<String,int>{},'pairs':<String,int>{}}});
      print('worker desktop JIT: $count dishes, ${watch.elapsedMilliseconds} ms');
      expect(result.dishes,hasLength(count));
      expect(result.dishes!.toSet(),hasLength(count));
      expect(plan.totalPrice(result.dishes!),lessThanOrEqualTo(1000000));
    }
  });
  testWidgets('pending calculation shows busy state and ignores changed budget', (tester) async {
    const plan = RicePlan(id:'p',name:'plan',location:'store',priceCents:100,
      labels:['one','two','three'],options:[['A'],['B'],['C']]);
    final pending = Completer<RiceResult>();
    Widget page(int budget) => MaterialApp(home:Scaffold(body:SingleChildScrollView(child: RicePanel(
      plans:const [('p',plan)],budget:budget,savePersonal:(_)async=>true,randomizer:(_) => pending.future))));
    await tester.pumpWidget(page(1000));
    await tester.ensureVisible(find.text('随机其余菜品'));
    await tester.tap(find.text('随机其余菜品'));
    await tester.pump();
    expect(find.text('正在选菜…'),findsOneWidget);
    await tester.pumpWidget(page(50));
    pending.complete(const RiceResult(['A','B','C'],'done'));
    await tester.pumpAndSettle();
    expect(find.text('done'),findsNothing);
    expect(find.text('正在选菜…'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
