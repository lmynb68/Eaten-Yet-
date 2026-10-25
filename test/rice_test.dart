import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/rice.dart';

void main() {
  test('schemes enforce meat count, budget, locks and exclude unknown dishes', () {
    final p = RicePlan(id: 'typed', name: '测试', location: '测试', priceCents: 100,
      labels: ['菜','菜','菜'], options: List.generate(3, (_) => ['蛋','菜A','菜B','肉A','肉B','未知']),
      dishTypes: {'蛋':'veg','菜A':'veg','菜B':'veg','肉A':'meat','肉B':'meat'},
      dishPrices: {'蛋':100,'菜A':100,'菜B':100,'肉A':200,'肉B':200,'未知':100});
    expect(RicePlan.fromJson(p.toJson()).dishTypes, p.dishTypes);
    for (var count=0; count<=2; count++) {
      for (var seed=0; seed<10; seed++) {
        final result = randomRice(p, 600, ['蛋',null,null], {0}, Random(seed), meatCount: count);
        expect(result.dishes, isNotNull);
        expect(result.dishes![0], '蛋');
        expect(result.dishes!.where((n) => riceDishType(p,n!) == 'meat').length, count);
        expect(result.dishes, isNot(contains('未知')));
        expect(p.totalPrice(result.dishes!), lessThanOrEqualTo(600));
      }
    }
    expect(randomRice(p, 300, [null,null,null], {}, Random(1), meatCount: 2).dishes, isNull);
    expect(randomRice(p, 600, ['肉A',null,null], {0}, Random(1), meatCount: 0).dishes, isNull);
    expect(randomRice(p, 900, [null,null,null], {}, Random(1), meatCount: 3).dishes, isNull);
  });

  const plan = RicePlan(id: 'test', name: '测试套餐（非真实菜单）', location: '测试窗口',
    priceCents: 1100, labels: ['大荤','小荤','素菜'],
    options: [['测试荤菜A','测试荤菜B'],['测试小荤A','测试小荤B'],['测试素菜A','测试素菜B']]);
  test('fixed total is inclusive and low budget preserves previous', () {
    expect(randomRice(plan, 1099, [null,null,null], {}, Random()).dishes, isNull);
    expect(randomRice(plan, 1100, [null,null,null], {}, Random()).dishes!.length, 3);
  });
  test('random keeps manual locks and changes the remaining dish', () {
    for (var seed=0;seed<30;seed++) {
      final old = ['测试荤菜A','测试小荤A','测试素菜A'];
      final result = randomRice(plan,1100,old,{0,1},Random(seed)).dishes!;
      expect(result[0],old[0]); expect(result[1],old[1]); expect(result[2],'测试素菜B');
      expect(old,['测试荤菜A','测试小荤A','测试素菜A']);
    }
  });
  test('unknown choices and invalid locked names are not fabricated', () {
    final empty = RicePlan(id: plan.id,name: plan.name,location: plan.location,
      priceCents: plan.priceCents,labels: plan.labels,options: [[],[],[]]);
    expect(randomRice(empty,1100,[null,null,null],{},Random()).message,contains('尚未补齐'));
    expect(randomRice(plan,1100,['已下架菜',null,null],{0},Random()).dishes,isNull);
  });
  test('duplicate dishes, all locks and mere permutations produce no new meal', () {
    const same = RicePlan(id:'same',name:'测试',location:'测试',priceCents:900,
      labels:['一','二','三'],options:[['A','B','C'],['A','B','C'],['A','B','C']]);
    final first=randomRice(same,900,[null,null,null],{},Random()).dishes!;
    expect(first.toSet().length,3);
    expect(randomRice(same,900,first,{},Random()).dishes,isNull);
    expect(randomRice(plan,1100,['测试荤菜A','测试小荤A','测试素菜A'],{0,1,2},Random()).message,contains('都已锁定'));
  });
  test('plan roundtrip validates and bounded search does not claim impossibility', () {
    final copy=RicePlan.fromJson(plan.toJson()); copy.validate();
    expect(copy.options,plan.options);
    expect(randomRice(plan,1100,[null,null,null],{},Random(),limit:1).message,contains('搜索达到上限'));
  });
}
