import 'package:flutter/material.dart';
import 'language.dart';

const maxQuantity = 99;

class QuantityPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final String label;
  const QuantityPicker({super.key, required this.value, required this.onChanged, this.label = '份数'});
  @override
  Widget build(BuildContext context) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
    LText(label),
    IconButton(tooltip: tr(context, '减少一份'), onPressed: value > 1 ? () => onChanged(value - 1) : null,
      icon: const Icon(Icons.remove_circle_outline)),
    Text('$value', semanticsLabel: tr(context, '{count} 份', params: {'count': value})),
    IconButton(tooltip: tr(context, '增加一份'), onPressed: value < maxQuantity ? () => onChanged(value + 1) : null,
      icon: const Icon(Icons.add_circle_outline)),
  ]);
}
