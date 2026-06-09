import 'package:flutter/material.dart';

Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String label = '名称',
  String? hint,
  String? initial,
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final v = ctrl.text.trim();
            if (v.isEmpty) return;
            Navigator.pop(ctx, v);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}
