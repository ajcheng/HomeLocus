import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_state.dart';
import 'app/theme.dart';
import 'services/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore saved auth from persistent storage
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('auth_token');
  final savedUrl = prefs.getString('server_url');

  if (savedToken != null && savedToken.isNotEmpty) {
    ApiClient.authToken = savedToken;
  }
  if (savedUrl != null && savedUrl.isNotEmpty) {
    ApiClient.baseUrl = savedUrl;
  }

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
      initialRoute: ApiClient.authToken != null ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
