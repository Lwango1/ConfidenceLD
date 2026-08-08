import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class Session {
  static Future<void> save({
    required String token,
    required int userId,
    required String username,
    required String displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setInt('userId', userId);
    await prefs.setString('username', username);
    await prefs.setString('displayName', displayName);
    ApiService.token = token;
    ApiService.userId = userId;
    ApiService.username = username;
    ApiService.displayName = displayName;
  }

  static Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return false;
    ApiService.token = token;
    ApiService.userId = prefs.getInt('userId');
    ApiService.username = prefs.getString('username');
    ApiService.displayName = prefs.getString('displayName');
    return true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    ApiService.token = null;
    ApiService.userId = null;
  }
}