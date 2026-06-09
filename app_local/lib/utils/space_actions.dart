import 'package:flutter/material.dart';

import 'name_dialog.dart';

Future<void> showRenameDeleteSheet(
  BuildContext context, {
  required String typeLabel,
  required String currentName,
  required Future<void> Function(String newName) onRename,
  required Future<void> Function() onDelete,
  int itemCount = 0,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(typeLabel),
            subtitle: Text(currentName),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('重命名'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await showNameDialog(
                context,
                title: '重命名$typeLabel',
                label: '名称',
                initial: currentName,
              );
              if (name != null && name != currentName) {
                await onRename(name);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
            title: Text('删除', style: TextStyle(color: Colors.red.shade700)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await _confirmDelete(
                context,
                typeLabel: typeLabel,
                name: currentName,
                itemCount: itemCount,
              );
              if (ok) await onDelete();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String typeLabel,
  required String name,
  required int itemCount,
}) async {
  final itemHint = itemCount > 0 ? '\n其中 $itemCount 件物品将移入「历史」检索。' : '';
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('删除$typeLabel'),
      content: Text('确定删除「$name」？\n下级结构和关联物品将一并删除。$itemHint'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return result == true;
}
