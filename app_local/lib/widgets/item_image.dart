import 'dart:io';

import 'package:flutter/material.dart';

/// 优先显示本地原图，缺失时回退到上传后的远程 URL
class ItemImage extends StatelessWidget {
  final String? localPath;
  final String? remoteUrl;
  final BoxFit fit;
  final Widget? placeholder;

  const ItemImage({
    super.key,
    this.localPath,
    this.remoteUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final local = localPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      return Image.file(File(local), fit: fit);
    }

    final remote = remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return Image.network(
        remote,
        fit: fit,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (_, __, ___) => placeholder ?? _broken(),
      );
    }

    return placeholder ?? _broken();
  }

  Widget _broken() {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image),
    );
  }
}
