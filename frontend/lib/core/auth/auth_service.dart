import '../../models/user.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';

class AuthService {
  const AuthService(this.apiClient);

  final ApiClient apiClient;

  Future<List<Map<String, dynamic>>> getProviders() async {
    final response = await apiClient.get<dynamic>(ApiEndpoints.authProviders);
    final payload = response.data;
    final providers =
        payload is Map ? payload['data'] ?? payload['providers'] : payload;
    if (providers is! List) return const [];
    return providers
        .whereType<Map>()
        .map((provider) => Map<String, dynamic>.from(provider))
        .toList();
  }

  Future<Map<String, dynamic>> devLogin(String username) async {
    final response = await apiClient.post<dynamic>(
      ApiEndpoints.devLogin,
      data: {'username': username},
    );
    final payload = response.data;
    if (payload is! Map) {
      throw const FormatException('登录响应格式不正确');
    }
    final result = payload['data'] is Map ? payload['data'] as Map : payload;
    return Map<String, dynamic>.from(result);
  }

  Future<User> getCurrentUser() async {
    final response = await apiClient.get<dynamic>(ApiEndpoints.authMe);
    final payload = response.data;
    if (payload is! Map) {
      throw const FormatException('用户信息格式不正确');
    }
    final userData = payload['data'] is Map
        ? payload['data'] as Map
        : payload['user'] is Map
            ? payload['user'] as Map
            : payload;
    return User.fromJson(Map<String, dynamic>.from(userData));
  }

  String getOidcLoginUrl(String provider) {
    return '${ApiEndpoints.baseUrl}${ApiEndpoints.oidcLogin(provider)}';
  }
}
