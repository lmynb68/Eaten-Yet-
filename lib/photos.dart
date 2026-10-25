import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'domain.dart';

// Match the same store, window and exact dish name; never borrow another meal's photo.
String dishAssetForEntry(Entry entry) {
  for (final plan in entry.db.ricePlans) {
    if (plan.storeKey == entry.placeKey && entry.offer.window.isNotEmpty &&
        plan.location.replaceAll(' ', '') == '${entry.place.name}${entry.offer.window}'.replaceAll(' ', '')) {
      final asset = plan.dishPhotos[entry.offer.name];
      if (asset != null) return asset;
    }
  }
  return '';
}

Future<String?> pickDishPhoto() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery,
    maxWidth: 900, maxHeight: 900, imageQuality: 65, requestFullMetadata: false);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 300000) throw const FormatException('照片过大，请选择小于300KB的图片');
  return base64Encode(bytes);
}

class DishPhoto extends StatefulWidget {
  final String data;
  final String asset;
  final bool large;
  const DishPhoto({super.key, this.data = '', this.asset = '', this.large = false});
  @override
  State<DishPhoto> createState() => _DishPhotoState();
}
class _DishPhotoState extends State<DishPhoto> {
  Uint8List? bytes;
  void decode() {
    try { bytes = widget.data.isEmpty ? null : base64Decode(widget.data); }
    catch (_) { bytes = null; }
  }
  @override
  void initState() { super.initState(); decode(); }
  @override
  void didUpdateWidget(covariant DishPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) decode();
  }
  @override
  Widget build(BuildContext context) {
    final large = widget.large;
    const placeholder = SizedBox.expand();
    Widget child = placeholder;
    if (widget.asset.isNotEmpty) {
      child = Image.asset(widget.asset, fit: BoxFit.cover,
        cacheWidth: large ? 640 : 160, errorBuilder: (_, error, stack) => placeholder);
    }
    if (bytes != null) {
      try { child = Image.memory(bytes!, fit: BoxFit.cover,
        cacheWidth: large ? 900 : 160, errorBuilder: (_, error, stack) => placeholder); }
      catch (_) { child = placeholder; }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(
      width: large ? double.infinity : 56, height: large ? 180 : 56, child: child));
  }
}
