import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/template.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../template_provider.dart';

class TemplateListPage extends ConsumerStatefulWidget {
  const TemplateListPage({super.key});

  @override
  ConsumerState<TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends ConsumerState<TemplateListPage> {
  String _status = '';
  bool _isBusy = false;

  Future<void> _refresh() async {
    ref.invalidate(templateListProvider(_status));
    await ref.read(templateListProvider(_status).future);
  }

  Future<void> _createTemplate() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreateTemplateDialog(),
    );
    if (result == null || !mounted) return;
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.templates,
            data: result,
          );
      final body = response.data as Map;
      final template = Template.fromJson(
        Map<String, dynamic>.from(body['data'] as Map? ?? body),
      );
      ref.invalidate(templateListProvider(_status));
      if (mounted) context.push('/templates/${template.id}');
    }, successMessage: '模板已创建');
  }

  Future<void> _importTemplate() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !mounted) return;
    await _runAction(() async {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('JSON 根节点必须是对象');
      final importData =
          decoded.containsKey('data') ? decoded['data'] : decoded;
      await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.templateImport,
            data: importData,
          );
      await _refresh();
    }, successMessage: '模板导入成功');
  }

  Future<void> _deleteTemplate(Template template) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除模板',
      message: '确认删除“${template.name}”？此操作会将模板移入已删除状态。',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction(() async {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.template(template.id),
          );
      await _refresh();
    }, successMessage: '模板已删除');
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : AppTheme.ink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templateListProvider(_status));
    final wide = MediaQuery.sizeOf(context).width >= 680;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页',
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('模板管理'),
        actions: [
          if (wide)
            TextButton.icon(
              onPressed: _isBusy ? null : _importTemplate,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导入模板'),
            )
          else
            IconButton(
              tooltip: '导入模板',
              onPressed: _isBusy ? null : _importTemplate,
              icon: const Icon(Icons.file_upload_outlined),
            ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: wide
                ? FilledButton.icon(
                    onPressed: _isBusy ? null : _createTemplate,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('创建模板'),
                  )
                : IconButton.filled(
                    tooltip: '创建模板',
                    onPressed: _isBusy ? null : _createTemplate,
                    icon: const Icon(Icons.add_rounded),
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _GridBackdrop()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ListHeader(count: templates.valueOrNull?.length),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        children: [
                          _filterChip('全部', ''),
                          _filterChip('草稿', 'draft'),
                          _filterChip('已发布', 'published'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: templates.when(
                          loading: () =>
                              const LoadingWidget(message: '正在整理模板…'),
                          error: (error, _) => AppErrorWidget(
                            message: '模板加载失败\n$error',
                            retryLabel: '重新加载',
                            onRetry: () => ref.invalidate(
                              templateListProvider(_status),
                            ),
                          ),
                          data: (items) => RefreshIndicator(
                            onRefresh: _refresh,
                            child: items.isEmpty
                                ? const _EmptyTemplates()
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final template = items[index];
                                      return Dismissible(
                                        key: ValueKey(template.id),
                                        direction: DismissDirection.endToStart,
                                        confirmDismiss: (_) async {
                                          await _deleteTemplate(template);
                                          return false;
                                        },
                                        background: Container(
                                          alignment: Alignment.centerRight,
                                          padding:
                                              const EdgeInsets.only(right: 28),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.white,
                                          ),
                                        ),
                                        child: _TemplateCard(
                                          template: template,
                                          onTap: () => context.push(
                                            '/templates/${template.id}',
                                          ),
                                          onDelete: () =>
                                              _deleteTemplate(template),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isBusy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _status == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      avatar: selected ? const Icon(Icons.check, size: 17) : null,
      onSelected: (_) => setState(() => _status = value),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '结构，从这里生长。',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '定义节点、字段与层级规则，构建可复用的文档骨架。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        if (count != null)
          Text(
            '$count 个模板',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.primary,
                ),
          ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onTap,
    required this.onDelete,
  });

  final Template template;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: template.status == 'published'
                      ? const Color(0xFFE7F5EC)
                      : const Color(0xFFFFF2D8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  template.status == 'published'
                      ? Icons.verified_outlined
                      : Icons.architecture_outlined,
                  color: template.status == 'published'
                      ? const Color(0xFF18794E)
                      : const Color(0xFFB25E09),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            template.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusBadge(status: template.status),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 16,
                      runSpacing: 5,
                      children: [
                        _Meta(icon: Icons.key_outlined, text: template.key),
                        _Meta(
                          icon: Icons.layers_outlined,
                          text: template.version,
                        ),
                        _Meta(
                          icon: Icons.schedule_outlined,
                          text: _formatDate(template.createdAt),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.more_horiz),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF77839A)),
          const SizedBox(width: 5),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (status) {
      'published' => ('已发布', const Color(0xFF18794E), const Color(0xFFE7F5EC)),
      'deleted' => ('已删除', const Color(0xFFB42318), const Color(0xFFFEECEB)),
      _ => ('草稿', const Color(0xFF9A4A00), const Color(0xFFFFF1D6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyTemplates extends StatelessWidget {
  const _EmptyTemplates();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.account_tree_outlined,
            size: 58,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有符合条件的模板',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('创建一个模板，开始定义内容结构。', textAlign: TextAlign.center),
        ],
      );
}

class _GridBackdrop extends StatelessWidget {
  const _GridBackdrop();

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _GridPainter(),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0B1565C0)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CreateTemplateDialog extends StatefulWidget {
  const _CreateTemplateDialog();

  @override
  State<_CreateTemplateDialog> createState() => _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends State<_CreateTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _version = TextEditingController(text: 'v1.0.0');
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _version.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('创建模板'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '模板名称'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _key,
                    decoration: const InputDecoration(
                      labelText: '模板 Key',
                      helperText: '建议使用小写字母、数字和下划线',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _version,
                    decoration: const InputDecoration(labelText: '版本'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '版本说明'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'key': _key.text.trim(),
                'version': _version.text.trim(),
                'version_note': _note.text.trim(),
              });
            },
            child: const Text('创建'),
          ),
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;
}

String _formatDate(DateTime? value) {
  if (value == null) return '时间未知';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
