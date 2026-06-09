import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
      return CachedNetworkImage(
        imageUrl: remote,
        fit: fit,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) => placeholder ?? _broken(),
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
