import 'dart:convert';
import 'package:http/http.dart' as http;

const appVersion = '1.0.0';
const appBuild = 25;
const releasesUrl = 'https://github.com/lmynb68/Eaten-Yet-/releases';
const catalogUrl = 'https://raw.githubusercontent.com/lmynb68/Eaten-Yet-/main/assets/official.json';

Future<String> fetchText(String url, {int maxBytes = 12000000}) async {
  final client = http.Client();
  try {
    return await (() async {
      final response = await client.send(http.Request('GET', Uri.parse(url))..headers['Accept']='application/json');
      if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) throw const FormatException('数据过大');
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    })().timeout(const Duration(seconds: 25));
  } finally { client.close(); }
}

// Compare numeric release versions, with stable versions after prereleases.
int compareVersions(String a, String b) {
  List<int>? parts(String v) {
    final m=RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(v);
    return m == null ? null : [for(var i=1;i<=3;i++) int.parse(m.group(i)!)];
  }
  final x=parts(a), y=parts(b);
  if (x == null || y == null) throw const FormatException('版本标签格式无效');
  for(var i=0;i<3;i++) { final c=x[i].compareTo(y[i]);if(c != 0)return c; }
  return (a.contains('-') ? 0 : 1).compareTo(b.contains('-') ? 0 : 1);
}
class AppRelease {
  final String version, notes, url;
  final bool prerelease;
  final List<UpdateAsset> assets;
  const AppRelease(this.version,this.notes,this.url,this.prerelease, [this.assets = const []]);
  UpdateAsset? installer(List<String> abis) {
    final verified = assets.where((a) => a.sha256 != null);
    if (abis.contains('arm64-v8a')) {
      for (final a in verified) { if (a.name.endsWith('-android-arm64.apk')) return a; }
    }
    for (final a in verified) { if (a.name.endsWith('-android-universal.apk')) return a; }
    return null;
  }
  static AppRelease? latest(String text, {bool includePrereleases = false}) {
    final list=jsonDecode(text) as List;
    final results=<AppRelease>[];
    for(final item in list) {
      if(item is! Map || item['draft'] == true) continue;
      if (!includePrereleases && item['prerelease'] == true) continue;
      final tag=item['tag_name'];
      if(tag is! String) continue;
      if (!includePrereleases && tag.split('+').first.contains('-')) continue;
      final assets = item['assets'];
      if (assets is! List || !assets.any((a) => a is Map && a['state'] == 'uploaded' &&
        a['size'] is num && a['size'] > 0 && a['name'] is String &&
        (a['name'] as String).endsWith('.apk') && a['browser_download_url'] is String &&
        (a['browser_download_url'] as String).startsWith('$releasesUrl/download/$tag/'))) continue;
      try { compareVersions(tag,appVersion); } catch (_) { continue; }
      final url=item['html_url'];
      if(url is! String || !url.startsWith('$releasesUrl/tag/')) continue;
      results.add(AppRelease(tag,item['body'] is String ? item['body'] : '',url,item['prerelease'] == true, assets.map((a) => UpdateAsset.parse(a, tag)).whereType<UpdateAsset>().toList()));
    }
    results.sort((a,b)=>compareVersions(b.version,a.version));
    return results.firstOrNull;
  }
}

class UpdateAsset {
  final String name, url;
  final int size;
  final String? sha256;
  const UpdateAsset(this.name, this.url, this.size, this.sha256);
  static UpdateAsset? parse(dynamic value, String tag) {
    if (value is! Map || value['state'] != 'uploaded') return null;
    final name = value['name'], url = value['browser_download_url'], size = value['size'];
    if (name is! String || !name.endsWith('.apk') || url is! String ||
        !url.startsWith('$releasesUrl/download/$tag/') || size is! int || size <= 0 || size > 200 * 1024 * 1024) return null;
    final digest = value['digest'];
    final hash = digest is String && RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)
        ? digest.substring(7).toLowerCase() : null;
    return UpdateAsset(name, url, size, hash);
  }
}
