import 'package:dio/dio.dart';

class AppException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  const AppException(this.message, {this.statusCode, this.data});

  factory AppException.fromDio(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    final message = _responseMessage(data) ?? error.message ?? 'Request failed';

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return NetworkException(message, data: data);
    }

    switch (statusCode) {
      case 400:
      case 422:
        return ValidationException(
          message,
          statusCode: statusCode,
          data: data,
        );
      case 401:
        return UnauthorizedException(message, data: data);
      case 403:
        return ForbiddenException('您没有权限执行此操作', data: data);
      case 404:
        return NotFoundException(message, data: data);
      default:
        if (statusCode != null && statusCode >= 500) {
          return ServerException(message, statusCode: statusCode, data: data);
        }
        return AppException(message, statusCode: statusCode, data: data);
    }
  }

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.data});
}

class UnauthorizedException extends AppException {
  const UnauthorizedException(super.message, {super.data})
      : super(statusCode: 401);
}

class ForbiddenException extends AppException {
  const ForbiddenException(super.message, {super.data})
      : super(statusCode: 403);
}

class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.data}) : super(statusCode: 404);
}

class ValidationException extends AppException {
  const ValidationException(
    super.message, {
    super.statusCode,
    super.data,
  });
}

class ServerException extends AppException {
  const ServerException(
    super.message, {
    super.statusCode,
    super.data,
  });
}

String? _responseMessage(dynamic data) {
  if (data is Map) {
    final message = data['message'] ?? data['error'] ?? data['detail'];
    if (message is String && message.isNotEmpty) return message;
  }
  if (data is String && data.isNotEmpty) return data;
  return null;
}
