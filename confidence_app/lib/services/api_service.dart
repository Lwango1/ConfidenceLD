import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiConfig {
  static const String baseUrl = 'https://confidenceld-backend.onrender.com';
}

class ApiService {
  static String? token;
  static String? username;
  static int? userId;
  static String? displayName;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String displayName,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/register'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        'displayName': displayName,
      }),
    );
    _handleError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    _handleError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getUsers() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/users'),
      headers: _headers,
    );
    _handleError(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> uploadMedia({
    required String filePath,
    required String mimeType,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${token ?? ''}';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _handleError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static void _handleError(http.Response res) {
    if (res.statusCode >= 400) {
      String msg = 'Erreur (${res.statusCode})';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['error'] != null) msg = body['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
  }
}