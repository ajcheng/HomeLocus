import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  static String baseUrl = 'https://home.ajcheng.com:8443/api/v1';
  static String? authToken; // Set after login, used by all instances

  final String _baseUrl;
  final String? _token;
  final http.Client _client = http.Client();

  ApiClient({String? baseUrl, String? token})
      : _baseUrl = baseUrl ?? ApiClient.baseUrl,
        _token = token ?? ApiClient.authToken;

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) h['Authorization'] = 'Bearer $_token';
    return h;
  }

  Future<dynamic> get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final response = await _client.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(response);
  }

  Future<http.StreamedResponse> uploadFile(String path, File imageFile, Map<String, String> fields) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    request.fields.addAll(fields);
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    return request.send();
  }

  /// Multipart upload and parse JSON response (e.g. image search).
  Future<dynamic> uploadAudio(
    String path,
    File audioFile, {
    Map<String, String> fields = const {},
    int timeoutSeconds = 120,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
    request.files.add(await http.MultipartFile.fromPath('audio', audioFile.path));
    request.fields.addAll(fields);
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed).timeout(Duration(seconds: timeoutSeconds));
    return _handleResponse(response);
  }

  Future<dynamic> uploadMultipart(
    String path,
    File file, {
    Map<String, String> fields = const {},
    int timeoutSeconds = 120,
  }) async {
    final streamed = await uploadFile(path, file, fields);
    final response = await http.Response.fromStream(streamed).timeout(Duration(seconds: timeoutSeconds));
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
