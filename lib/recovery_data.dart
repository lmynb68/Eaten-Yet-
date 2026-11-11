import 'dart:convert';

/// Preserve supported preference values even when they are not valid JSON.
/// Strings stay byte-for-byte unchanged for diagnosis and later recovery.
String encodeRecoveryValue(Object? value) {
  if (value is String) return value;
  if (value is double && !value.isFinite) {
    return jsonEncode({'type': 'double', 'value': value.toString()});
  }
  return jsonEncode(value);
}
