import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Default API base URL. Override per instance or change globally.
  /// - Web (same-origin): "/api/v1"
  /// - Android emulator: "http://10.0.2.2:8000/api/v1"
  /// - Physical device: "https://your-server.com:8443/api/v1"
  static String baseUrl = '/api/v1';

  final String _baseUrl;
  final http.Client _client = http.Client();

  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? ApiClient.baseUrl;

  Future<dynamic> get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl$path'),
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    throw ApiException(response.statusCode, response.body);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'HTTP $statusCode: ${message.length > 80 ? '${message.substring(0, 80)}...' : message}';
}
