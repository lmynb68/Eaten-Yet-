import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'backup_files.dart';
import 'language.dart';

Future<void> showBackupExportDialog(BuildContext context,
    {required String text,
    required String name,
    bool diagnostic = false}) async {
  var busy = false;
  String? message;
  final canCopy = utf8.encode(text).length <= BackupFiles.clipboardBytes;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) {
            Future<void> perform(bool copy) async {
              refresh(() {
                busy = true;
                message = null;
              });
              try {
                if (copy) {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) refresh(() => message = '内容已复制，请私下保存。');
                } else {
                  final saved = await BackupFiles.save(text, name);
                  if (ctx.mounted)
                    refresh(
                        () => message = saved ? '备份文件已保存。' : '已取消保存，原数据未改变。');
                }
              } catch (_) {
                if (ctx.mounted) refresh(() => message = '备份没有保存成功，请重试。原数据仍在。');
              } finally {
                if (ctx.mounted) refresh(() => busy = false);
              }
            }

            return PopScope(
                canPop: !busy,
                child: AlertDialog(
                  title: LText(diagnostic ? '保存排障备份' : '保存备份'),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        LText(diagnostic
                            ? '这份文件保留原始数据，仅供排查问题，不能直接导入恢复。请私下保存。'
                            : '选择保存位置。以后可以通过“选择备份文件”重新导入，请妥善保管。'),
                        if (!canCopy)
                          const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LText('内容较多，请保存为文件。')),
                        if (message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: LText(message!)),
                        if (busy) const LinearProgressIndicator(),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: busy ? null : () => Navigator.pop(ctx),
                        child: const LText('关闭')),
                    if (canCopy)
                      TextButton(
                          onPressed: busy ? null : () => perform(true),
                          child: const LText('复制内容')),
                    FilledButton(
                        onPressed: busy ? null : () => perform(false),
                        child: const LText('保存文件')),
                  ],
                ));
          }));
}
