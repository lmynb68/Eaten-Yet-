import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<String?> pickDishPhoto() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery,
    maxWidth: 900, maxHeight: 900, imageQuality: 65, requestFullMetadata: false);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 300000) throw const FormatException('照片过大，请选择小于300KB的图片');
  return base64Encode(bytes);
}

class DishPhoto extends StatelessWidget {
  final String data;
  final bool large;
  const DishPhoto({super.key, this.data = '', this.large = false});
  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.restaurant, color: Colors.brown)));
    Widget child = placeholder;
    if (data.isNotEmpty) {
      try { child = Image.memory(base64Decode(data), fit: BoxFit.cover,
        cacheWidth: large ? 900 : 160, errorBuilder: (_, error, stack) => placeholder); }
      catch (_) { child = placeholder; }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(
      width: large ? double.infinity : 56, height: large ? 180 : 56, child: child));
  }
}
