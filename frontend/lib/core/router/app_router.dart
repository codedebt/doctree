import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/pages/system_settings_page.dart';
import '../../features/admin/pages/user_management_page.dart';
import '../../features/home/home_page.dart';
import '../../features/login/login_page.dart';
import '../../features/login/oidc_callback_page.dart';
import '../../features/project/pages/project_edit_page.dart';
import '../../features/project/pages/project_list_page.dart';
import '../../features/template/pages/template_edit_page.dart';
import '../../features/template/pages/template_list_page.dart';
import '../auth/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<AuthState>(
    authProvider,
    (_, __) => refreshNotifier.refresh(),
  );

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      if (authState.isLoading) return null;

      final isLoginRoute = state.matchedLocation == '/login';
      final isCallbackRoute = state.matchedLocation == '/auth/callback';
      if (!authState.isAuthenticated) {
        return isLoginRoute || isCallbackRoute ? null : '/login';
      }
      if (isLoginRoute || isCallbackRoute) return '/home';

      final user = authState.user;
      final requiresTemplateAdmin =
          state.matchedLocation.startsWith('/templates');
      final requiresProjectAdmin =
          state.matchedLocation.startsWith('/admin/users');
      final requiresSystemAdmin =
          state.matchedLocation.startsWith('/admin/settings');
      if (requiresTemplateAdmin &&
          !(user?.hasAtLeastRole('template_admin') ?? false)) {
        return '/home';
      }
      if (requiresProjectAdmin &&
          !(user?.hasAtLeastRole('project_admin') ?? false)) {
        return '/home';
      }
      if (requiresSystemAdmin &&
          !(user?.hasAtLeastRole('system_admin') ?? false)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => OidcCallbackPage(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TemplateListPage(),
      ),
      GoRoute(
        path: '/templates/:id',
        builder: (context, state) => TemplateEditPage(
          templateId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/projects',
        builder: (context, state) => const ProjectListPage(),
      ),
      GoRoute(
        path: '/projects/:id',
        builder: (context, state) => ProjectEditPage(
          projectId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const UserManagementPage(),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (context, state) => const SystemSettingsPage(),
      ),
    ],
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
