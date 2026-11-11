import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eat_what/backup_dialog.dart';
import 'package:eat_what/backup_files.dart';
import 'package:eat_what/backup_import.dart';
import 'package:eat_what/history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_lazy_list_test.dart' show backup, record;
import 'save_failure_test.dart' show FailingPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('eaten-yet-backup-test-');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(BackupFiles.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  File temporaryFile(String name) => File('${temporary.path}/$name');

  test(
      'a backup over 1 MB round trips with only file paths crossing the channel',
      () async {
    final text = '菜单😀\n' * 150000;
    final bytes = utf8.encode(text);
    expect(bytes.length, greaterThan(1024 * 1024));
    final outgoing = temporaryFile('outgoing.json');
    final saved = temporaryFile('saved.json');
    final incoming = temporaryFile('incoming.json');
    final methods = <String>[];
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      methods.add(call.method);
      switch (call.method) {
        case 'prepareExport':
          expect(call.arguments, isNull);
          return outgoing.path;
        case 'saveFile':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          expect(arguments.keys, unorderedEquals(['path', 'name']));
          expect(arguments['name'], 'my-history.json');
          expect(arguments['path'], outgoing.path);
          expect(await outgoing.readAsBytes(), bytes);
          await outgoing.copy(saved.path);
          return true;
        case 'openFile':
          expect(call.arguments, {'maxBytes': BackupFiles.maxBytes});
          await saved.copy(incoming.path);
          return incoming.path;
        default:
          fail('Unexpected backup operation: ${call.method}');
      }
    });

    expect(await BackupFiles.save(text, 'my-history.json'), isTrue);
    expect(await outgoing.exists(), isFalse);
    expect(await BackupFiles.open(), text);
    expect(await incoming.exists(), isFalse);
    expect(await saved.readAsBytes(), bytes);
    expect(methods, ['prepareExport', 'saveFile', 'openFile']);
  });

  for (final canceled in [true, false]) {
    test(
        'export ${canceled ? 'cancellation' : 'failure'} removes temporary data',
        () async {
      final file = temporaryFile('export.json');
      messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
        if (call.method == 'prepareExport') return file.path;
        expect(call.method, 'saveFile');
        expect(await file.readAsString(), '保留原菜单');
        if (canceled) return false;
        throw PlatformException(code: 'write_failed');
      });
      if (canceled) {
        expect(await BackupFiles.save('保留原菜单', 'menu.json'), isFalse);
      } else {
        await expectLater(BackupFiles.save('保留原菜单', 'menu.json'),
            throwsA(isA<PlatformException>()));
      }
      expect(await file.exists(), isFalse);
    });
  }

  test('failure to prepare a file does not start the save operation', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      methods.add(call.method);
      return null;
    });
    await expectLater(BackupFiles.save('menu', 'menu.json'),
        throwsA(isA<FileSystemException>()));
    expect(methods, ['prepareExport']);
  });

  test('an oversized export is rejected before opening the document picker',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      calls++;
      return null;
    });
    // Use multi-byte characters so this also checks bytes rather than length.
    final text = '中' * (BackupFiles.maxBytes ~/ 3 + 1);
    expect(text.length, lessThan(BackupFiles.maxBytes));
    await expectLater(
        BackupFiles.save(text, 'menu.json'), throwsFormatException);
    expect(calls, 0);
  });

  test('canceling file selection returns null without reading a file',
      () async {
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      expect(call.method, 'openFile');
      expect(call.arguments, {'maxBytes': 32});
      return null;
    });
    expect(await BackupFiles.open(limit: 32), isNull);
    expect(await temporary.list().toList(), isEmpty);
  });

  test('invalid UTF-8 is rejected and its temporary file is removed', () async {
    final file = temporaryFile('invalid.json');
    await file.writeAsBytes([0xc3, 0x28]);
    messenger.setMockMethodCallHandler(
        BackupFiles.channel, (call) async => file.path);
    await expectLater(BackupFiles.open(), throwsFormatException);
    expect(await file.exists(), isFalse);
  });

  test('import limit uses UTF-8 bytes and accepts the exact boundary',
      () async {
    final file = temporaryFile('limit.json');
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      expect(call.arguments, {'maxBytes': 6});
      return file.path;
    });
    await file.writeAsBytes(utf8.encode('中北'));
    expect(await BackupFiles.open(limit: 6), '中北');
    expect(await file.exists(), isFalse);
    await file.writeAsBytes(utf8.encode('中北a'));
    await expectLater(BackupFiles.open(limit: 6), throwsFormatException);
    expect(await file.exists(), isFalse);
  });

  test('invalid import limits are rejected before platform calls', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(BackupFiles.channel, (call) async {
      calls++;
      return null;
    });
    for (final limit in [0, -1, BackupFiles.maxBytes + 1]) {
      await expectLater(
          BackupFiles.open(limit: limit), throwsA(isA<ArgumentError>()));
    }
    expect(calls, 0);
  });

  Future<void> openImport(WidgetTester tester,
      {required Future<void> Function(String) onSave,
      ValueChanged<bool?>? onResult}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            final result = await showBackupImportDialog<String>(context,
                title: '导入用餐历史',
                inputLabel: '粘贴历史备份',
                checkLabel: '检查备份',
                saveLabel: '导入',
                maxBytes: HistoryStore.maxBytes,
                parse: (text) {
                  HistoryStore.decode(text);
                  return text;
                },
                describe: (text) =>
                    '已读取 ${HistoryStore.decode(text).length} 条用餐记录',
                onSave: onSave);
            onResult?.call(result);
          },
          child: const Text('打开导入'),
        );
      })),
    ));
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'failed import retains checked content and can retry durable save',
      (tester) async {
    final preferences = FailingPreferences();
    final store = await HistoryStore.load(preferences);
    await store.import(backup([record(0)]));
    final previous = preferences.disk[HistoryStore.storageKey];
    final input = backup([record(1)]);
    bool? result;
    await openImport(tester,
        onSave: store.import, onResult: (value) => result = value);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), input);
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    expect(find.text('已读取 1 条用餐记录'), findsOneWidget);

    preferences.failNext = true;
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入未能保存，内容已保留，请重试。'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        input);
    expect(preferences.disk[HistoryStore.storageKey], previous);
    expect(store.records.map((row) => row.id), ['record-0']);
    expect(result, isNull);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isTrue);
    final reloaded = await HistoryStore.load(preferences);
    expect(reloaded.records.map((row) => row.id),
        unorderedEquals(['record-0', 'record-1']));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing checked input requires rechecking and rejects invalid JSON',
      (tester) async {
    var saves = 0;
    await openImport(tester, onSave: (_) async => saves++);
    await tester.enterText(find.byType(TextField), backup([record(0)]));
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.enterText(find.byType(TextField), '{broken');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    expect(find.text('文件读不出来，请选择正确的备份文件。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(saves, 0);
  });

  testWidgets(
      'import cancellation does not save and pending saves cannot duplicate',
      (tester) async {
    var saves = 0;
    final pending = Completer<void>();
    bool? result;
    await openImport(tester,
        onSave: (_) async {
          saves++;
          await pending.future;
        },
        onResult: (value) => result = value);
    await tester.enterText(find.byType(TextField), backup([record(0)]));
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(saves, 0);

    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), backup([record(0)]));
    await tester.tap(find.text('检查备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
            .onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(saves, 1);
  });

  Future<void> openExport(WidgetTester tester, String text,
      {bool diagnostic = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showBackupExportDialog(context,
                        text: text,
                        name: 'backup.json',
                        diagnostic: diagnostic),
                    child: const Text('打开备份'))))));
    await tester.tap(find.text('打开备份'));
    await tester.pumpAndSettle();
  }

  testWidgets('large multi-byte backups offer files without clipboard transfer',
      (tester) async {
    final text = '中' * (BackupFiles.clipboardBytes ~/ 3 + 1);
    expect(text.length, lessThan(BackupFiles.clipboardBytes));
    var clipboardCalls = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls++;
      return null;
    });
    await openExport(tester, text);
    expect(find.text('内容较多，请保存为文件。'), findsOneWidget);
    expect(find.text('复制内容'), findsNothing);
    expect(find.text('保存文件'), findsOneWidget);
    expect(clipboardCalls, 0);
  });

  testWidgets(
      'small backup copy reports failure and retries with unchanged content',
      (tester) async {
    final text = backup([record(0)]);
    var attempts = 0;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        attempts++;
        if (attempts == 1) throw PlatformException(code: 'clipboard_failed');
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await openExport(tester, text);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(find.text('备份没有保存成功，请重试。原数据仍在。'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(find.text('内容已复制，请私下保存。'), findsOneWidget);
    expect(copied, text);
    expect(attempts, 2);
  });

  testWidgets('diagnostic exports clearly distinguish unreadable raw data',
      (tester) async {
    await openExport(tester, '{broken history', diagnostic: true);
    expect(find.text('保存排障备份'), findsOneWidget);
    expect(find.text('这份文件保留原始数据，仅供排查问题，不能直接导入恢复。请私下保存。'), findsOneWidget);
    expect(find.text('保存文件'), findsOneWidget);
  });
}
