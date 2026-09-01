import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import 'login_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  String? _launchingProvider;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authProvider.notifier)
        .devLogin(_usernameController.text.trim());
  }

  Future<void> _openProvider(String provider) async {
    setState(() => _launchingProvider = provider);
    try {
      final service = ref.read(authServiceProvider);
      var uri = Uri.parse(service.getOidcLoginUrl(provider));
      if (!kIsWeb) {
        uri = uri.replace(
          queryParameters: {...uri.queryParameters, 'client': 'native'},
        );
      }
      final opened = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('浏览器无法打开');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开认证页面，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _launchingProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final providers = ref.watch(loginProvidersProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 920;

    return Scaffold(
      backgroundColor: const Color(0xFF102A2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(size: 30),
            SizedBox(width: 10),
            Text('Doctree'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _ForestPainter())),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isWide ? 72 : 20,
                28,
                isWide ? 72 : 20,
                36,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height - 128,
                ),
                child: isWide
                    ? Row(
                        children: [
                          const Expanded(child: _LoginIntroduction()),
                          const SizedBox(width: 72),
                          SizedBox(
                            width: 460,
                            child: _buildLoginCard(authState, providers),
                          ),
                        ],
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: _buildLoginCard(authState, providers),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(
    AuthState authState,
    AsyncValue<List<Map<String, dynamic>>> providers,
  ) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 24 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: Card(
        elevation: 18,
        shadowColor: Colors.black.withOpacity(0.24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(child: _BrandMark(size: 58)),
              const SizedBox(height: 20),
              Text(
                '欢迎回到知识森林',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '登录后继续整理项目、模板与团队知识。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              providers.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, __) => _ProviderNotice(
                  onRetry: () => ref.invalidate(loginProvidersProvider),
                ),
                data: (items) => items.isEmpty
                    ? const SizedBox.shrink()
                    : _ProviderButtons(
                        providers: items,
                        launchingProvider: _launchingProvider,
                        onPressed: _openProvider,
                      ),
              ),
              if (providers.valueOrNull?.isNotEmpty ?? false) ...[
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('开发者入口'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _usernameController,
                  enabled: !authState.isLoading,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.username],
                  onFieldSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '请输入开发账号',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入用户名' : null,
                ),
              ),
              if (authState.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  authState.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: authState.isLoading ? null : _login,
                icon: authState.isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(authState.isLoading ? '正在登录…' : '开发者登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderButtons extends StatelessWidget {
  const _ProviderButtons({
    required this.providers,
    required this.launchingProvider,
    required this.onPressed,
  });

  final List<Map<String, dynamic>> providers;
  final String? launchingProvider;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('企业账号登录', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final provider in providers) ...[
          OutlinedButton.icon(
            onPressed: launchingProvider == null
                ? () => onPressed(provider['name']?.toString() ?? '')
                : null,
            icon: launchingProvider == provider['name']
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.corporate_fare_outlined),
            label: Text('使用 ${_providerLabel(provider)} 登录'),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _providerLabel(Map<String, dynamic> provider) {
    final name = provider['name']?.toString().trim();
    return name == null || name.isEmpty ? '统一身份认证' : name;
  }
}

class _ProviderNotice extends StatelessWidget {
  const _ProviderNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF9A5B13)),
          const SizedBox(width: 10),
          const Expanded(child: Text('暂时无法加载企业登录方式。')),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _LoginIntroduction extends StatelessWidget {
  const _LoginIntroduction();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: const Padding(
        padding: EdgeInsets.only(left: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '让文档生长，\n让知识相连。',
              style: TextStyle(
                color: Color(0xFFF2F0E6),
                fontSize: 52,
                height: 1.16,
                letterSpacing: -2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 440,
              child: Text(
                '从一棵清晰的结构树开始，管理团队的项目、模板与每一次知识沉淀。',
                style: TextStyle(
                  color: Color(0xFFB7CDC7),
                  fontSize: 18,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE9784D),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(Icons.account_tree_outlined,
          color: Colors.white, size: size * .6),
    );
  }
}

class _ForestPainter extends CustomPainter {
  const _ForestPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF31504B)
      ..strokeWidth = 1;
    final glow = Paint()..color = const Color(0x1526C6A2);
    canvas.drawCircle(Offset(size.width * .14, size.height * .18), 180, glow);
    canvas.drawCircle(Offset(size.width * .86, size.height * .78), 240, glow);
    for (var i = 0; i < 8; i++) {
      final x = size.width * (.06 + i * .135);
      canvas.drawLine(Offset(x, 0), Offset(x - 180, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
