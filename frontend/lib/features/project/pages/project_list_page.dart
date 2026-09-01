import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/project.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../template/template_provider.dart';
import '../project_provider.dart';

class ProjectListPage extends ConsumerStatefulWidget {
  const ProjectListPage({super.key});

  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  bool _isBusy = false;

  Future<void> _refresh() async {
    ref.invalidate(projectListProvider);
    await ref.read(projectListProvider.future);
  }

  Future<void> _createProject() async {
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreateProjectDialog(),
    );
    if (data == null || !mounted) return;
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.projects,
            data: data,
          );
      final created = _projectFromResponse(response.data);
      ref.invalidate(projectListProvider);
      if (mounted) context.push('/projects/${created.id}');
    }, successMessage: '项目已创建');
  }

  Future<void> _importProject() async {
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
      final data = decoded.containsKey('data') ? decoded['data'] : decoded;
      await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.projectImport,
            data: data,
          );
      await _refresh();
    }, successMessage: '项目导入成功');
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除项目',
      message: '确认删除“${project.name}”？此操作无法撤销。',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction(() async {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.project(project.id),
          );
      await _refresh();
    }, successMessage: '项目已删除');
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (mounted) _message(successMessage);
    } catch (error) {
      if (mounted) _message('操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _message(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 680;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页',
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('项目管理'),
        actions: [
          IconButton(
            tooltip: '导入',
            onPressed: _isBusy ? null : _importProject,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: wide
                ? FilledButton.icon(
                    onPressed: _isBusy ? null : _createProject,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('创建项目'),
                  )
                : IconButton.filled(
                    tooltip: '创建项目',
                    onPressed: _isBusy ? null : _createProject,
                    icon: const Icon(Icons.add_rounded),
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ProjectGridPainter()),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('把复杂，组织成清晰。',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 5),
                    Text(
                      '选择一个项目继续编辑，或从已发布模板开始新的内容树。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: projects.when(
                        loading: () => const LoadingWidget(message: '正在读取项目…'),
                        error: (error, _) => AppErrorWidget(
                          message: '项目加载失败\n$error',
                          retryLabel: '重新加载',
                          onRetry: () => ref.invalidate(projectListProvider),
                        ),
                        data: (items) => RefreshIndicator(
                          onRefresh: _refresh,
                          child: items.isEmpty
                              ? const _EmptyProjects()
                              : ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final project = items[index];
                                    return _ProjectCard(
                                      project: project,
                                      onTap: () => context
                                          .push('/projects/${project.id}'),
                                      onDelete: () => _deleteProject(project),
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
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(projectTemplateProvider(project.templateId));
    final published = project.status == 'published';
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: published
                      ? const Color(0xFFE7F5EC)
                      : const Color(0xFFFFF1D6),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  published ? Icons.task_alt_rounded : Icons.edit_document,
                  color: published
                      ? const Color(0xFF18794E)
                      : const Color(0xFF9A4A00),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Text(project.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        _StatusBadge(status: project.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        _Meta(Icons.key_outlined, project.key),
                        _Meta(Icons.layers_outlined, project.version),
                        _Meta(
                          Icons.account_tree_outlined,
                          template.when(
                            data: (item) => '${item.name} · ${item.version}',
                            loading: () => '模板读取中…',
                            error: (_, __) => '模板信息不可用',
                          ),
                        ),
                        _Meta(Icons.schedule_outlined,
                            _formatDate(project.createdAt)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除项目',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
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
  const _Meta(this.icon, this.text);

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
    final published = status == 'published';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: published ? const Color(0xFFE7F5EC) : const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        published ? '已发布' : '草稿',
        style: TextStyle(
          color: published ? const Color(0xFF18794E) : const Color(0xFF9A4A00),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.folder_open_outlined,
              size: 60, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('还没有项目',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('从一个已发布模板创建你的第一棵内容树。', textAlign: TextAlign.center),
        ],
      );
}

class _CreateProjectDialog extends ConsumerStatefulWidget {
  const _CreateProjectDialog();

  @override
  ConsumerState<_CreateProjectDialog> createState() =>
      _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _description = TextEditingController();
  final _version = TextEditingController(text: 'v1.0.0');
  final _note = TextEditingController();
  String? _templateId;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _description.dispose();
    _version.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templateListProvider('published'));
    return AlertDialog(
      title: const Text('创建项目'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '项目名称'),
                  validator: _required,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _key,
                  decoration: const InputDecoration(labelText: '项目 Key'),
                  validator: _required,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '项目描述'),
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _version,
                  decoration: const InputDecoration(labelText: '版本'),
                  validator: _required,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '版本说明'),
                ),
                const SizedBox(height: 13),
                templates.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('模板加载失败：$error'),
                  data: (items) => DropdownButtonFormField<String>(
                    value: _templateId,
                    decoration: const InputDecoration(labelText: '项目模板'),
                    items: items
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text('${item.name} · ${item.version}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _templateId = value),
                    validator: (value) => value == null ? '请选择已发布模板' : null,
                  ),
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
              'description': _description.text.trim(),
              'version': _version.text.trim(),
              'version_note': _note.text.trim(),
              'template_id': _templateId!,
            });
          },
          child: const Text('创建'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;
}

class _ProjectGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0B1565C0)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Project _projectFromResponse(dynamic body) {
  final data = body is Map && body.containsKey('data') ? body['data'] : body;
  return Project.fromJson(Map<String, dynamic>.from(data as Map));
}

String _formatDate(DateTime? value) {
  if (value == null) return '时间未知';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
