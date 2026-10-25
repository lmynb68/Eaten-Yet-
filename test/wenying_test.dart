import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/domain.dart';

void main() {
  test('Wenying retains portion prices, paid rice and restricted weight pricing', () {
    final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
    db.validate();
    final rows=db.offers.where((o)=>o.placeId=='wy').toList();
    expect(rows.length,483);
    expect(rows.where((o)=>o.name=='浓汤牛肉面').map((o)=>o.priceCents).toSet(),{1300,1500});
    expect(rows.singleWhere((o)=>o.name=='称重麻辣拌').available,isFalse);
    expect(rows.singleWhere((o)=>o.name=='香辣牛肚浇头面').priceCents,1980);
    expect(rows.where((o)=>o.name=='米饭').every((o)=>o.kind=='side'),isTrue);
    expect(rows.where((o)=>o.addonOnly).every((o)=>o.kind=='side'),isTrue);
    final old=MenuDb.decode(File('docs/catalog-before-wenying.json').readAsStringSync(),Source.official);
    expect(db.offers.where((o)=>o.placeId!='wy' && o.placeId!='btk' && o.placeId!='btz' && o.placeId!='fw' && o.placeId!='zxb').map((o)=>o.id).toList(),old.offers.map((o)=>o.id).toList());
  });
}
