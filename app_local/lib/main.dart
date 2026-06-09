import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'app/theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const HomelocusLocalApp(),
    ),
  );
}

class HomelocusLocalApp extends StatelessWidget {
  const HomelocusLocalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeLocus 本地版',
      theme: HomelocusTheme.light,
      home: Consumer<AppState>(
        builder: (_, state, __) {
          if (!state.initialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
