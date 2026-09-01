import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_endpoints.dart';
import 'app_exception.dart';

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(
            error.copyWith(error: AppException.fromDio(error)),
          );
        },
      ),
    );
  }

  static final ApiClient _instance = ApiClient._internal();

  factory ApiClient() => _instance;

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';

  Future<void> setToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> saveToken(String token) => setToken(token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _guard(
        _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: options,
        ),
      );

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _guard(
        _dio.post<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
        ),
      );

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _guard(
        _dio.put<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
        ),
      );

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _guard(
        _dio.patch<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
        ),
      );

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _guard(
        _dio.delete<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
        ),
      );

  Future<Response<T>> _guard<T>(Future<Response<T>> request) async {
    try {
      return await request;
    } on DioException catch (error) {
      final converted = error.error;
      if (converted is AppException) throw converted;
      throw AppException.fromDio(error);
    }
  }
}
