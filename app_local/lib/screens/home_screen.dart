import 'package:flutter/material.dart';

import 'photo_capture_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'space_screen.dart';
import 'voice_input_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static final _pages = <Widget>[
    const SpaceScreen(),
    const SearchScreen(),
    const PhotoCaptureScreen(),
    const VoiceInputScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_tree), label: '空间'),
          NavigationDestination(icon: Icon(Icons.search), label: '检索'),
          NavigationDestination(icon: Icon(Icons.camera_alt), label: '拍照'),
          NavigationDestination(icon: Icon(Icons.mic), label: '语音'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
