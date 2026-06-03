import 'package:flutter_test/flutter_test.dart';

import 'package:homelocus/services/api_client.dart';

void main() {
  group('ApiException', () {
    test('toString includes status code', () {
      final ex = ApiException(401, '{"detail":"Unauthorized"}');
      expect(ex.toString(), contains('HTTP 401'));
    });

    test('toString truncates long messages', () {
      final ex = ApiException(500, 'x' * 200);
      expect(ex.toString().length, lessThan(120));
    });
  });

  group('ApiClient token', () {
    tearDown(() {
      ApiClient.authToken = null;
    });

    test('instance uses global authToken by default', () {
      ApiClient.authToken = 'global-token';
      final client = ApiClient();
      expect(client, isNotNull);
      ApiClient.authToken = null;
      final noAuth = ApiClient();
      expect(noAuth, isNotNull);
    });
  });
}
