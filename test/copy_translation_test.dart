import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/language.dart';

void main() {
  test('templates preserve dish names and do not expand inserted parameters', () {
    expect(translateText('当前主菜：{dish} · {store}', 'en', params: {
      'dish': '官方菜单{store}', 'store': '麦港餐厅',
    }), 'Main: 官方菜单{store} · 麦港餐厅');
    expect(translateText('麦港餐厅官方菜单', 'en'), '麦港餐厅官方菜单');
    expect(translateText('{store}', 'zh', params: {'store': '麦港餐厅'}), '麦港餐厅');
  });

  test('dynamic counts and recovery messages have English copy', () {
    expect(translateText('第2道菜', 'en'), 'Dish 2');
    expect(translateText('12 个菜品', 'en'), '12 items');
    for (final message in [
      '收藏已清空，原数据已另存一份。',
      '导入', '中北大学周边', '1 份', '个人录入', '菜单管理',
      '原数据暂时读不出来，请稍后重试。',
      '重置用餐历史？',
      '请先保存导出的内容。重置后可以导入之前正常的历史备份。',
      '已经有一家同名同位置的店铺',
      '暂无符合条件的菜品。可以在“菜单管理”添加自己的菜单。',
      '单独买小食',
      '米饭价格（元）',
      '暂无其他合适搭配，已保留当前选择。',
      '新版本还没准备好适合这台手机的安装包，请稍后再试。',
    ]) {
      expect(translateText(message, 'en'), isNot(message), reason: message);
    }
  });

  test('save errors hide implementation details but retain actionable limits', () {
    expect(friendlySaveError(StateError('private storage path')), '保存失败，请重试');
    expect(friendlySaveError(const FormatException('编号为空或重复')), '保存失败，请重试');
    expect(friendlySaveError(const FormatException('最多保存500条收藏，请先删除部分记录')),
        '最多保存500条收藏，请先删除部分记录');
  });
}
