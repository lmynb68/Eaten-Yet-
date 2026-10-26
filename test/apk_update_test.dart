import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eat_what/apk_download.dart';
import 'package:eat_what/updates.dart';

void main() {
  final hash = List.filled(64, 'a').join();
  const url = '$releasesUrl/download/v1.0.2/app.apk';
  late Directory dir;
  setUp(() async { dir = await Directory.systemTemp.createTemp('apk-test-'); });
  tearDown(() async { await dir.delete(recursive: true); });

  test('select verified architecture, fall back to universal, never unverified APK', () {
    Map<String, Object> asset(String name, {bool digest = true}) => {
      'name': name, 'state': 'uploaded', 'size': 3,
      'browser_download_url': '$releasesUrl/download/v1.0.2/$name',
      if (digest) 'digest': 'sha256:$hash',
    };
    final release = AppRelease.latest(jsonEncode([{
      'tag_name': 'v1.0.2', 'html_url': '$releasesUrl/tag/v1.0.2',
      'assets': [asset('x-android-arm64.apk'), asset('x-android-universal.apk')],
    }]))!;
    expect(release.installer(['arm64-v8a'])!.name, 'x-android-arm64.apk');
    expect(release.installer(['x86_64'])!.name, 'x-android-universal.apk');
    expect(UpdateAsset.parse(asset('x.apk', digest: false), 'v1.0.2')!.sha256, isNull);
    expect(UpdateAsset.parse({...asset('x.apk'), 'browser_download_url': 'https://evil.invalid/app.apk'}, 'v1.0.2'), isNull);
  });
  test('download streams to file and reports actual bytes', () async {
    final file = File('${dir.path}/update.apk');
    final progress = <int>[];
    final task = ApkDownload(client: MockClient((_) async => http.Response.bytes([1,2,3], 200)));
    await task.save(UpdateAsset('app.apk', url, 3, hash), file, progress.add);
    expect(await file.readAsBytes(), [1,2,3]);
    expect(progress.last, 3);
  });
  test('truncated stream is removed', () async {
    final file = File('${dir.path}/update.apk');
    final task = ApkDownload(client: MockClient.streaming((request, body) async => http.StreamedResponse(Stream.value([1]), 200)));
    await expectLater(task.save(UpdateAsset('app.apk', url, 3, hash), file, (_) {}), throwsFormatException);
    expect(await file.exists(), isFalse);
  });
  test('oversized stream is removed', () async {
    final file = File('${dir.path}/update.apk');
    final task = ApkDownload(client: MockClient.streaming((request, body) async => http.StreamedResponse(Stream.value([1,2,3,4]), 200)));
    await expectLater(task.save(UpdateAsset('app.apk', url, 3, hash), file, (_) {}), throwsFormatException);
    expect(await file.exists(), isFalse);
  });
  test('redirect to HTTP or unknown host is rejected before requesting it', () async {
    var requests = 0;
    final task = ApkDownload(client: MockClient((_) async {
      requests++; return http.Response('', 302, headers: {'location': 'http://evil.invalid/a.apk'});
    }));
    await expectLater(task.save(UpdateAsset('app.apk', url, 3, hash), File('${dir.path}/update.apk'), (_) {}), throwsFormatException);
    expect(requests, 1);
  });
  test('cancelled download removes partial bytes', () async {
    late ApkDownload task;
    task = ApkDownload(client: MockClient.streaming((request, body) async => http.StreamedResponse(Stream.fromIterable([[1], [2], [3]]), 200)));
    final file = File('${dir.path}/update.apk');
    await expectLater(task.save(UpdateAsset('app.apk', url, 3, hash), file, (_) => task.cancel()), throwsA(isA<UpdateCancelled>()));
    expect(await file.exists(), isFalse);
  });
  test('write failure propagates and does not report success', () async {
    final task = ApkDownload(client: MockClient((_) async => http.Response.bytes([1,2,3], 200)));
    await expectLater(task.save(UpdateAsset('app.apk', url, 3, hash), File('${dir.path}/missing/update.apk'), (_) {}), throwsA(isA<FileSystemException>()));
  });
}
