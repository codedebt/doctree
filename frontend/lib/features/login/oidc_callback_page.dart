import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';

class OidcCallbackPage extends ConsumerStatefulWidget {
  const OidcCallbackPage({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<OidcCallbackPage> createState() => _OidcCallbackPageState();
}

class _OidcCallbackPageState extends ConsumerState<OidcCallbackPage> {
  bool _invalidToken = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _completeLogin());
  }

  Future<void> _completeLogin() async {
    final token = widget.token?.trim();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _invalidToken = true);
      return;
    }
    await ref.read(authProvider.notifier).handleOidcCallback(token);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final failed =
        _invalidToken || (!authState.isLoading && authState.error != null);

    return Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    failed
                        ? Icons.link_off_rounded
                        : Icons.verified_user_outlined,
                    size: 48,
                    color: failed
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    failed ? '认证未完成' : '正在完成登录',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    failed ? '登录链接无效或已过期，请重新发起登录。' : '正在验证您的身份，请稍候…',
                    textAlign: TextAlign.center,
                  ),
                  if (!failed) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ] else ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('返回登录'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
