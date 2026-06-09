class VoiceParseResult {
  final String label;
  final String? color;
  final List<String> tags;

  const VoiceParseResult({
    required this.label,
    this.color,
    this.tags = const [],
  });
}

VoiceParseResult parseVoiceText(String text) {
  final raw = text.trim();
  if (raw.isEmpty) {
    return const VoiceParseResult(label: '');
  }

  const colorMap = {
    '红色': '红',
    '绿色': '绿',
    '蓝色': '蓝',
    '黑色': '黑',
    '白色': '白',
    '黄色': '黄',
    '粉色': '粉',
    '紫色': '紫',
    '灰色': '灰',
    '棕色': '棕',
    '橙色': '橙',
  };

  String? color;
  final tags = <String>{};

  for (final entry in colorMap.entries) {
    if (raw.contains(entry.key) || raw.contains(entry.value)) {
      color = entry.key;
      tags.add(entry.key);
      tags.add(entry.value);
      break;
    }
  }

  final deParts = raw.split('的').where((p) => p.trim().isNotEmpty).toList();
  var label = deParts.isNotEmpty ? deParts.last.trim() : raw;
  label = label.replaceAll(RegExp(r'^(有一?件?|有一?个?)'), '').trim();

  final colorItem = RegExp(r'(.+色)的(.+)').firstMatch(label);
  if (colorItem != null) {
    color ??= colorItem.group(1);
    label = colorItem.group(2)!.trim();
  } else if (color != null && label.startsWith(color)) {
    label = label.substring(color.length).replaceFirst(RegExp(r'^的?'), '').trim();
  }

  if (label.isEmpty) label = raw;

  tags.add(label);
  for (final part in deParts) {
    final p = part.trim();
    if (p.isNotEmpty && p.length <= 12) tags.add(p);
  }

  final keywords = RegExp(r'[\u4e00-\u9fff]{2,6}')
      .allMatches(raw)
      .map((m) => m.group(0)!)
      .where((w) => !{'有一件', '有一个', '一件', '一个'}.contains(w));
  tags.addAll(keywords);

  return VoiceParseResult(
    label: label.length > 50 ? label.substring(0, 50) : label,
    color: color,
    tags: tags.where((t) => t.length >= 2).take(8).toList(),
  );
}
