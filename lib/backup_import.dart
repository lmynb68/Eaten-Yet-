import 'package:flutter/material.dart';
import 'backup_files.dart';
import 'language.dart';

Future<bool?> showBackupImportDialog<T>(
  BuildContext context, {
  required String title,
  required String inputLabel,
  required String checkLabel,
  required String saveLabel,
  required int maxBytes,
  required T Function(String) parse,
  required String Function(T) describe,
  required Future<void> Function(T) onSave,
}) =>
    showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BackupImportDialog<T>(
            title: title,
            inputLabel: inputLabel,
            checkLabel: checkLabel,
            saveLabel: saveLabel,
            maxBytes: maxBytes,
            parse: parse,
            describe: describe,
            onSave: onSave));

class _BackupImportDialog<T> extends StatefulWidget {
  final String title, inputLabel, checkLabel, saveLabel;
  final int maxBytes;
  final T Function(String) parse;
  final String Function(T) describe;
  final Future<void> Function(T) onSave;
  const _BackupImportDialog(
      {required this.title,
      required this.inputLabel,
      required this.checkLabel,
      required this.saveLabel,
      required this.maxBytes,
      required this.parse,
      required this.describe,
      required this.onSave});
  @override
  State<_BackupImportDialog<T>> createState() => _BackupImportDialogState<T>();
}

class _BackupImportDialogState<T> extends State<_BackupImportDialog<T>> {
  final input = TextEditingController();
  String? fileText, error;
  T? parsed;
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void check() {
    try {
      final value = widget.parse(fileText ?? input.text);
      setState(() {
        parsed = value;
        error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        parsed = null;
        error = e.message == '这份菜单不是新版，请选择更新的菜单文件。'
            ? e.message
            : '文件读不出来，请选择正确的备份文件。';
      });
    } catch (_) {
      setState(() {
        parsed = null;
        error = '文件读不出来，请选择正确的备份文件。';
      });
    }
  }

  Future<void> chooseFile() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await BackupFiles.open(limit: widget.maxBytes);
      if (!mounted || value == null) return;
      // Keep large file contents out of the editable text field and Binder.
      setState(() {
        fileText = value;
        parsed = null;
        input.clear();
      });
      check();
    } catch (_) {
      if (mounted) setState(() => error = '文件未能读取，请检查文件大小和内容后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || parsed == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(parsed as T);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = '导入未能保存，内容已保留，请重试。';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    TextButton.icon(
                        onPressed: busy ? null : chooseFile,
                        icon: const Icon(Icons.folder_open),
                        label: const LText('选择备份文件')),
                    if (fileText != null) const LText('已选择文件，检查无误后确认导入。'),
                    TextField(
                        controller: input,
                        enabled: !busy,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                            labelText: tr(context, widget.inputLabel)),
                        onChanged: (_) => setState(() {
                              fileText = null;
                              parsed = null;
                              error = null;
                            })),
                    if (parsed != null) Text(widget.describe(parsed as T)),
                    if (error != null)
                      LText(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (busy) const LinearProgressIndicator(),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const LText('关闭')),
            TextButton(
                onPressed: busy ? null : check,
                child: LText(widget.checkLabel)),
            FilledButton(
                onPressed: busy || parsed == null ? null : save,
                child: LText(widget.saveLabel)),
          ]));
}
