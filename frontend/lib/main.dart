import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _DeepLinkHandler(child: DoctreeApp())));
}

class _DeepLinkHandler extends ConsumerStatefulWidget {
  const _DeepLinkHandler({required this.child});

  final Widget child;

  @override
  ConsumerState<_DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends ConsumerState<_DeepLinkHandler> {
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _subscription = AppLinks().uriLinkStream.listen(
            (uri) => unawaited(_handleLink(uri)),
          );
    }
  }

  Future<void> _handleLink(Uri uri) async {
    final isAuthCallback = uri.scheme == 'doctree' &&
        uri.host == 'auth' &&
        uri.path == '/callback';
    final token = uri.queryParameters['token'];
    if (isAuthCallback && token != null && token.isNotEmpty) {
      await ref.read(authProvider.notifier).handleOidcCallback(token);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
