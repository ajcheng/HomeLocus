import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'item_image.dart';

class ItemMediaActions extends StatefulWidget {
  final String? imagePath;
  final String? audioPath;
  final String? remoteImageUrl;

  const ItemMediaActions({
    super.key,
    this.imagePath,
    this.audioPath,
    this.remoteImageUrl,
  });

  @override
  State<ItemMediaActions> createState() => _ItemMediaActionsState();
}

class _ItemMediaActionsState extends State<ItemMediaActions> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _localImageOk = false;
  bool _audioOk = false;

  @override
  void initState() {
    super.initState();
    _checkFiles();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _checkFiles() async {
    final img = widget.imagePath;
    final aud = widget.audioPath;
    final localImageOk = img != null && img.isNotEmpty && await File(img).exists();
    final audioOk = aud != null && aud.isNotEmpty && await File(aud).exists();
    if (mounted) {
      setState(() {
        _localImageOk = localImageOk;
        _audioOk = audioOk;
      });
    }
  }

  bool get _canShowImage =>
      _localImageOk || (widget.remoteImageUrl != null && widget.remoteImageUrl!.isNotEmpty);

  Future<void> _toggleAudio() async {
    final path = widget.audioPath;
    if (path == null || path.isEmpty) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    await _player.play(DeviceFileSource(path));
    setState(() => _playing = true);
  }

  void _viewImage() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            maxWidth: MediaQuery.of(ctx).size.width * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: ItemImage(
                    localPath: _localImageOk ? widget.imagePath : null,
                    remoteUrl: widget.remoteImageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canShowImage && !_audioOk) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('本机媒体', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_canShowImage && _localImageOk)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _viewImage,
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ItemImage(localPath: widget.imagePath, fit: BoxFit.cover),
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: Icon(Icons.zoom_in, color: Colors.white, size: 36),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_canShowImage)
          OutlinedButton.icon(
            onPressed: _viewImage,
            icon: const Icon(Icons.photo),
            label: const Text('查看照片'),
          ),
        if (_audioOk) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _toggleAudio,
            icon: Icon(_playing ? Icons.stop_circle : Icons.play_circle),
            label: Text(_playing ? '停止播放录音' : '播放录音'),
          ),
        ],
      ],
    );
  }
}
