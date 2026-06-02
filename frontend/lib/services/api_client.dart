import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Default API base URL. Configurable in login screen settings.
  static String baseUrl = 'https://home.ajcheng.com:8443/api/v1';

  final String _baseUrl;
  final http.Client _client = http.Client();

  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? ApiClient.baseUrl;

  Future<dynamic> get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> put(String path, {Object? body}) async {
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

  Future<http.StreamedResponse> uploadFile(String path, File imageFile, Map<String, String> fields) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    request.fields.addAll(fields);
    return request.send();
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
