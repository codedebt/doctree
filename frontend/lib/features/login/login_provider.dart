import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';

final loginProvidersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authService = ref.read(authServiceProvider);
  return authService.getProviders();
});
