import 'package:flutter/material.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.battery_charging_full),
            title: Text('充电提醒'),
            subtitle: Text('暂无待充电设备'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.assignment_return),
            title: Text('借出/归位提醒'),
            subtitle: Text('暂无借出物品'),
          ),
        ],
      ),
    );
  }
}
