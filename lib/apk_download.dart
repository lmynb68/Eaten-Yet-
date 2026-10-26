import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'updates.dart';

const updateChannel = MethodChannel('local.eatwhat.campus/update');

class UpdateCancelled implements Exception {}

/// One foreground download. Leaving the page cancels and removes partial data.
class ApkDownload {
  final http.Client client;
  bool _cancelled = false;
  ApkDownload({http.Client? client}) : client = client ?? http.Client();
  void cancel() { _cancelled = true; client.close(); }

  Future<void> save(UpdateAsset asset, File file, void Function(int) progress) async {
    RandomAccessFile? output;
    bool complete = false;
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    try {
      if (asset.sha256 == null || asset.size <= 0 || asset.size > 200 * 1024 * 1024) {
        throw const FormatException('安装包信息不完整');
      }
      var uri = Uri.parse(asset.url);
      http.StreamedResponse? response;
      // Explicit redirects keep downloads on GitHub HTTPS asset hosts.
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (_cancelled) throw UpdateCancelled();
        if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443 ||
            !{'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}.contains(uri.host)) {
          throw const FormatException('下载地址不可信');
        }
        response = await client.send(http.Request('GET', uri)..followRedirects = false)
            .timeout(const Duration(seconds: 30));
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen(null).cancel();
          if (location == null || redirects == 5) throw const FormatException('下载跳转失败');
          uri = uri.resolve(location);
          continue;
        }
        break;
      }
      if (response == null || response.statusCode != 200) throw const HttpException('下载服务器暂不可用');
      if (response.contentLength != null && response.contentLength != asset.size) {
        throw const FormatException('安装包大小不匹配');
      }
      output = await file.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw UpdateCancelled();
        if (DateTime.now().isAfter(deadline)) throw TimeoutException('下载超时');
        received += chunk.length;
        if (received > asset.size) throw const FormatException('安装包超出预期大小');
        await output.writeFrom(chunk);
        progress(received);
      }
      if (_cancelled) throw UpdateCancelled();
      if (received != asset.size) throw const FormatException('安装包下载不完整');
      await output.flush();
      complete = true;
    } catch (_) {
      if (_cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      await output?.close();
      client.close();
      if (!complete && await file.exists()) await file.delete();
    }
  }
}
