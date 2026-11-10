import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'history.dart';
import 'language.dart';
import 'domain.dart';

Future<(int, String)?> showMealReview(BuildContext context,
    {int initialStars = 0, String initialReview = ''}) async {
  var stars = initialStars;
  final text = TextEditingController(text: initialReview);
  final result = await showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) => AlertDialog(
                  title: const LText('评价这一顿'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const LText('星级和评价可以稍后再填'),
                    Wrap(children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                            tooltip: tr(ctx, '{count} 星', params: {'count': i}),
                            onPressed: () =>
                                refresh(() => stars = stars == i ? 0 : i),
                            icon: Icon(
                                i <= stars ? Icons.star : Icons.star_border))
                    ]),
                    TextField(
                        controller: text,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 5,
                        decoration:
                            InputDecoration(labelText: tr(ctx, '写下你的评价'))),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const LText('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, (stars, text.text.trim())),
                        child: const LText('保存'))
                  ])));
  // Wait for the dialog exit animation before disposing its controller.
  Future<void>.delayed(const Duration(seconds: 1), text.dispose);
  return result;
}

class HistoryPage extends StatefulWidget {
  final HistoryStore store;
  const HistoryPage({super.key, required this.store});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool busy = false;
  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LText('历史记录保存失败，原记录已保留。请重试。')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importHistory() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const LText('导入用餐历史'),
                content: TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(labelText: tr(ctx, '粘贴历史备份'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const LText('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const LText('导入'))
                ]));
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (text != null) await act(() => widget.store.import(text));
  }

  @override
  Widget build(BuildContext context) {
    // Read one snapshot per build; create cards only as they enter the viewport.
    final records = widget.store.records;
    return Scaffold(
        appBar: AppBar(title: const LText('用餐历史')),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: records.length + 1,
          itemBuilder: (context, index) => index == 0
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LText('只保存在本机。记录这一顿后，可以评分、写评价。'),
                  Wrap(children: [
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => act(() async {
                                  await Clipboard.setData(ClipboardData(
                                      text: widget.store.export()));
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: LText('历史备份已复制，请私下保存。')));
                                }),
                        child: const LText('导出用餐历史')),
                    TextButton(
                        onPressed: busy ? null : importHistory,
                        child: const LText('导入用餐历史'))
                  ]),
                  if (widget.store.recoveryRequired)
                    const LText('历史记录暂时读不出来，原数据已保留，请先导出备份。'),
                  if (widget.store.recoveryRequired)
                    TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                            title: const LText('重置用餐历史？'),
                                            content: const LText(
                                                '请先保存导出的内容。重置后可以导入之前正常的历史备份。'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const LText('取消')),
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child:
                                                      const LText('已保存备份，确认重置'))
                                            ]));
                                if (yes == true)
                                  await act(widget.store.resetAfterBackup);
                              },
                        child: const LText('备份后重置历史')),
                  if (!widget.store.recoveryRequired && records.isEmpty)
                    const LText('还没有用餐历史。选好后点击“记录这一顿”。'),
                ])
              : historyCard(context, records[index - 1]),
        ));
  }

  Widget historyCard(BuildContext context, MealHistory row) => Card(
      key: ValueKey(row.id),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.meal.storeName,
                style: Theme.of(context).textTheme.titleMedium),
            Text(row.meal.savedAt.replaceFirst('T', ' ').split('.').first),
            for (final item in row.meal.items)
              Text(
                  '${item.name} × ${item.quantity}  ¥${money(item.price * item.quantity)}'),
            if (row.meal.ricePrice > 0)
              Text(
                  '${tr(context, row.meal.baseLabel)} × ${row.meal.baseQuantity}  ¥${money(row.meal.ricePrice * row.meal.baseQuantity)}'),
            Text('${tr(context, "合计")} ¥${money(row.meal.total)}'),
            if (row.stars > 0)
              Text('★' * row.stars,
                  semanticsLabel:
                      tr(context, '{count} 星', params: {'count': row.stars})),
            if (row.review.isNotEmpty) Text(row.review),
            Wrap(children: [
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final value = await showMealReview(context,
                              initialStars: row.stars,
                              initialReview: row.review);
                          if (value != null)
                            await act(() =>
                                widget.store.edit(row.id, value.$1, value.$2));
                        },
                  child: const LText('编辑评价')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: const LText('删除这条用餐记录？'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const LText('取消')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const LText('删除'))
                                      ]));
                          if (yes == true)
                            await act(() => widget.store.remove(row.id));
                        },
                  child: const LText('删除'))
            ]),
          ])));
}
