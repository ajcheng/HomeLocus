import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homelocus/app/app_state.dart';
import 'package:homelocus/main.dart';
import 'package:homelocus/services/api_client.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiClient.authToken = null;
    ApiClient.baseUrl = 'http://127.0.0.1:8000/api/v1';
  });

  testWidgets('shows login screen when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const HomeLocusApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('家庭物品存放管理系统'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
  });

  testWidgets('opens home with bottom navigation when token is preset', (WidgetTester tester) async {
    ApiClient.authToken = 'test-token';

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const HomeLocusApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('空间'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('家庭'), findsOneWidget);
  });
}
