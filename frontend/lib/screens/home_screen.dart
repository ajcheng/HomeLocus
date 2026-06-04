import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';
import 'space_screen.dart';
import 'search_screen.dart';
import 'reminders_screen.dart';
import 'voice_input_screen.dart';
import 'photo_upload_screen.dart';
import 'family_screen.dart';
import 'settings_screen.dart';
import 'user_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  int _reminderBadge = 0;

  final _screens = const [
    SpaceScreen(),
    SearchScreen(),
    RemindersScreen(),
    FamilyScreen(),
  ];

  @override
  void initState() {
    super.initState();
    context.read<AppState>().addListener(_syncTabFromAppState);
    _loadReminderCount();
    PushService.registerIfSaved();
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_syncTabFromAppState);
    super.dispose();
  }

  Future<void> _loadReminderCount() async {
    try {
      final locId = context.read<AppState>().activeLocationId;
      final path = locId.isNotEmpty
          ? '/reminders/pending/count?location_id=$locId'
          : '/reminders/pending/count';
      final data = await ApiClient().get(path);
      if (mounted) setState(() => _reminderBadge = data['count'] ?? 0);
    } catch (_) {}
  }

  void _syncTabFromAppState() {
    final tab = context.read<AppState>().homeTabIndex;
    if (tab != _currentIndex && mounted) {
      setState(() => _currentIndex = tab);
      if (tab == 1) context.read<AppState>().refreshSearchItems();
      if (tab == 2) _loadReminderCount();
    }
  }

  Widget _badgeIcon(IconData icon, {bool selected = false}) {
    return Badge(
      isLabelVisible: _reminderBadge > 0,
      label: Text('$_reminderBadge'),
      child: Icon(selected ? Icons.notifications : icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          context.read<AppState>().setHomeTabIndex(i);
          if (i == 1) context.read<AppState>().refreshSearchItems();
          if (i == 2) _loadReminderCount();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '空间'),
          const NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(
            icon: _badgeIcon(Icons.notifications_outlined),
            selectedIcon: _badgeIcon(Icons.notifications, selected: true),
            label: '提醒',
          ),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '家庭'),
        ],
      ),
      appBar: AppBar(
        title: const Text('HomeLocus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: '用户管理',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _AddButton(
                    icon: Icons.camera_alt,
                    label: '拍照添加',
                    color: Colors.blue,
                    onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotoUploadScreen())); },
                  ),
                  _AddButton(
                    icon: Icons.mic,
                    label: '语音添加',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(ctx);
                      final locId = context.read<AppState>().activeLocationId;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => VoiceInputScreen(locationId: locId),
                      ));
                    },
                  ),
                ]),
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AddButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 28, backgroundColor: color.withAlpha(40), child: Icon(icon, color: color, size: 28)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      ),
    );
  }
}
