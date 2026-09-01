import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';

const adminUsersPageSize = 20;

final usersProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, page) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.get<dynamic>(
    ApiEndpoints.users,
    queryParameters: {'page': page, 'page_size': adminUsersPageSize},
  );
  if (response.data is! Map) {
    throw const FormatException('用户列表格式不正确');
  }
  return Map<String, dynamic>.from(response.data as Map);
});
