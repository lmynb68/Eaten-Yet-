// No Flutter or package dependencies: run directly with the Dart SDK.
import 'dart:io';

import '../lib/domain.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart scripts/validate_catalog.dart <catalog.json>');
    exitCode = 64;
    return;
  }
  try {
    final db = MenuDb.decode(
        File(arguments.single).readAsStringSync(), Source.official);
    final encoded = db.encode(compact: true);
    final restored = MenuDb.decode(encoded, Source.official);
    if (restored.encode(compact: true) != encoded) {
      throw const FormatException('Catalog changed during encoding round trip');
    }
    stdout.writeln('Application decoder PASS: revision ${db.revision}, '
        '${db.places.length} restaurants, ${db.offers.length} offers');
  } catch (error) {
    final message = error.toString();
    stderr.writeln('Application decoder FAIL: '
        '${message.length > 500 ? message.substring(0, 500) : message}');
    exitCode = 1;
  }
}
