import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Only temporary file paths cross the platform channel, never backup contents.
class BackupFiles {
  static const channel = MethodChannel('local.eatwhat.campus/backup');
  static const maxBytes = 64 * 1024 * 1024;
  static const clipboardBytes = 128 * 1024;

  static Future<bool> save(String text, String name) async {
    final bytes = utf8.encode(text);
    if (bytes.length > maxBytes) throw const FormatException('备份文件太大');
    final path = await channel.invokeMethod<String>('prepareExport');
    if (path == null) throw const FileSystemException('无法创建备份文件');
    final file = File(path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await channel
              .invokeMethod<bool>('saveFile', {'path': path, 'name': name}) ??
          false;
    } finally {
      await _remove(file);
    }
  }

  static Future<String?> open({int limit = maxBytes}) async {
    if (limit <= 0 || limit > maxBytes) throw ArgumentError.value(limit);
    final path =
        await channel.invokeMethod<String>('openFile', {'maxBytes': limit});
    if (path == null) return null;
    final file = File(path);
    try {
      if (await file.length() > limit) throw const FormatException('备份文件太大');
      final bytes = await file.readAsBytes();
      if (bytes.length > limit) throw const FormatException('备份文件太大');
      return utf8.decode(bytes);
    } finally {
      await _remove(file);
    }
  }

  static Future<void> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Native completion may already have removed the temporary file.
    }
  }
}
