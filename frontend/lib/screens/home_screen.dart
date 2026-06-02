import 'package:flutter/material.dart';

import 'space_screen.dart';
import 'search_screen.dart';
import 'reminders_screen.dart';
import 'voice_input_screen.dart';
import 'family_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    SpaceScreen(),
    SearchScreen(),
    RemindersScreen(),
    FamilyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '空间'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.notifications), label: '提醒'),
          NavigationDestination(icon: Icon(Icons.people), label: '家庭'),
        ],
      ),
      appBar: AppBar(
        title: const Text('HomeLocus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VoiceInputScreen(locationId: '')),
        ),
        icon: const Icon(Icons.mic),
        label: const Text('语音添加'),
      ),
    );
  }
}
