import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/photos.dart';
import 'package:eat_what/domain.dart';

void main() {
  testWidgets('missing photo stays blank and changing a dish clears its old image', (tester) async {
    Widget host(String asset) => MaterialApp(home: Scaffold(body: DishPhoto(asset: asset)));
    await tester.pumpWidget(host('assets/rice/dish_01.webp'));
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(host(''));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('photo match requires exact dish, store and window', () {
    final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
    Entry dish(String name, {String place='sf', String window='1号窗口'}) => Entry(
      Offer(id:'photo-test',placeId:place,name:name,portion:'一份',priceCents:500,
        roles:{},foodIds:{},updatedAt:'2026-10-18',window:window),db);
    expect(dishAssetForEntry(dish('糖醋里脊')), 'assets/rice/dish_02.webp');
    expect(dishAssetForEntry(dish('糖醋里脊饭')), '');
    expect(dishAssetForEntry(dish('糖醋里脊',window:'2号窗口')), '');
    expect(dishAssetForEntry(dish('糖醋里脊',place:'community')), '');
    expect(dishAssetForEntry(dish('卤鸡蛋')), '');
  });
}
