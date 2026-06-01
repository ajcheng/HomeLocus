import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'app/theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const HomeLocusApp(),
    ),
  );
}

class HomeLocusApp extends StatelessWidget {
  const HomeLocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeLocus',
      theme: HomelocusTheme.light,
      darkTheme: HomelocusTheme.dark,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
