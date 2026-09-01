import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user.dart';
import '../api/api_client.dart';
import 'auth_service.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final bool isAuthenticated;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.isAuthenticated = false,
    this.error,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    bool? isAuthenticated,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this.apiClient, this.authService)
      : super(const AuthState(isLoading: true)) {
    unawaited(checkAuth());
  }

  final ApiClient apiClient;
  final AuthService authService;

  Future<void> checkAuth() async {
    state = state.copyWith(isLoading: true);
    try {
      final token = await apiClient.getToken();
      if (token == null || token.isEmpty) {
        state = const AuthState();
        return;
      }
      final user = await authService.getCurrentUser();
      state = AuthState(user: user, isAuthenticated: true);
    } catch (_) {
      await apiClient.clearToken();
      state = const AuthState();
    }
  }

  Future<void> devLogin(String username) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await authService.devLogin(username.trim());
      final token = result['token'];
      final userData = result['user'];
      if (token is! String || token.isEmpty || userData is! Map) {
        throw const FormatException('登录响应格式不正确');
      }
      await apiClient.saveToken(token);
      final user = User.fromJson(Map<String, dynamic>.from(userData));
      state = AuthState(user: user, isAuthenticated: true);
    } catch (_) {
      await apiClient.clearToken();
      state = const AuthState(error: '登录失败，请检查用户名或稍后重试。');
    }
  }

  Future<void> logout() async {
    await apiClient.clearToken();
    state = const AuthState();
  }

  Future<void> handleOidcCallback(String token) async {
    if (token.trim().isEmpty) {
      state = const AuthState(error: '登录凭证无效，请重新登录。');
      return;
    }
    state = state.copyWith(isLoading: true, error: null);
    await apiClient.saveToken(token);
    await checkAuth();
    if (!state.isAuthenticated) {
      state = const AuthState(error: '身份验证失败，请重新登录。');
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.read(apiClientProvider)),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.read(apiClientProvider),
    ref.read(authServiceProvider),
  ),
);
