import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../login/login_provider.dart';

class SystemSettingsPage extends ConsumerWidget {
  const SystemSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(loginProvidersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102A2A),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 38,
                        color: Color(0xFF7DDFC7),
                      ),
                      SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '系统概览',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              '查看当前认证配置与服务状态。',
                              style: TextStyle(color: Color(0xFFB7CDC7)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: providers.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (_, __) => _SettingsError(
                        onRetry: () => ref.invalidate(loginProvidersProvider),
                      ),
                      data: (items) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            icon: Icons.shield_outlined,
                            label: '认证模式',
                            value: items.isEmpty ? '开发模式' : 'OIDC 与开发模式',
                          ),
                          const Divider(height: 32),
                          _InfoRow(
                            icon: Icons.hub_outlined,
                            label: 'OIDC 提供方',
                            value: items.isEmpty
                                ? '未配置'
                                : items
                                    .map((item) =>
                                        item['name']?.toString() ?? '未命名')
                                    .join('、'),
                          ),
                          const Divider(height: 32),
                          const _InfoRow(
                            icon: Icons.check_circle_outline,
                            label: '认证服务',
                            value: '运行中',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF1D3AF)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.construction_outlined,
                          color: Color(0xFF9A5B13)),
                      SizedBox(width: 14),
                      Expanded(child: Text('更多设置管理功能即将推出。')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2A7C73)),
        const SizedBox(width: 14),
        SizedBox(
          width: 120,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36),
        const SizedBox(height: 10),
        const Text('认证配置读取失败。'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
      ],
    );
  }
}
