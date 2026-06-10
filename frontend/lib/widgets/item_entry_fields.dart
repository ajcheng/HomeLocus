import 'package:flutter/material.dart';

/// 拍照/录音识别后的可编辑物品字段
class ItemEntryFields extends StatelessWidget {
  final TextEditingController labelCtrl;
  final TextEditingController brandCtrl;
  final TextEditingController categoryCtrl;
  final TextEditingController colorCtrl;
  final bool showChargeable;
  final bool chargeable;
  final ValueChanged<bool>? onChargeableChanged;

  const ItemEntryFields({
    super.key,
    required this.labelCtrl,
    required this.brandCtrl,
    required this.categoryCtrl,
    required this.colorCtrl,
    this.showChargeable = false,
    this.chargeable = false,
    this.onChargeableChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(
            labelText: '物品名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: brandCtrl,
          decoration: const InputDecoration(
            labelText: '品牌（可选）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                  labelText: '分类（可选）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: colorCtrl,
                decoration: const InputDecoration(
                  labelText: '颜色（可选）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (showChargeable && onChargeableChanged != null) ...[
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: chargeable,
            title: const Text('需充电设备'),
            onChanged: (v) => onChargeableChanged!(v ?? false),
          ),
        ],
      ],
    );
  }
}
