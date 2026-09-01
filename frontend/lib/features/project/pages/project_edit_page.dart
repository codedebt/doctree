import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/project.dart';
import '../../../models/template.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../template/template_provider.dart';
import '../project_provider.dart';
import '../widgets/node_detail_panel.dart';
import '../widgets/tree_view.dart';

class ProjectEditPage extends ConsumerStatefulWidget {
  const ProjectEditPage({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<ProjectEditPage> createState() => _ProjectEditPageState();
}

class _ProjectEditPageState extends ConsumerState<ProjectEditPage> {
  bool _busy = false;

  Future<void> _refreshTree() async {
    ref.invalidate(projectTreeProvider(widget.projectId));
    final nodes = await ref.read(projectTreeProvider(widget.projectId).future);
    final selected = ref.read(selectedNodeProvider);
    if (selected != null) {
      final replacement =
          nodes.where((node) => node.id == selected.id).firstOrNull;
      ref.read(selectedNodeProvider.notifier).state = replacement;
    }
  }

  Future<void> _publish(Project project) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '发布项目',
      message: '确认发布“${project.name}”当前版本？发布后将无法编辑。',
      confirmLabel: '确认发布',
      cancelLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    await _runAction(() async {
      await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.projectPublish(project.id),
          );
      ref.invalidate(projectDetailProvider(widget.projectId));
      ref.invalidate(projectListProvider);
      await ref.read(projectDetailProvider(widget.projectId).future);
    }, successMessage: '项目已发布');
  }

  Future<void> _newVersion(Project project, Template template) async {
    List<Template> candidates = const [];
    try {
      final templates =
          await ref.read(templateListProvider('published').future);
      candidates = templates
          .where((item) => item.key == template.key && item.id != template.id)
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));
    } catch (_) {
      candidates = const [];
    }
    if (!mounted) return;
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NewVersionDialog(
        currentVersion: project.version,
        currentTemplate: template,
        templateVersions: candidates,
      ),
    );
    if (data == null || !mounted) return;
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.projectNewVersion(project.id),
            data: data,
          );
      final created = _projectFromResponse(response.data);
      ref.invalidate(projectListProvider);
      ref.read(selectedNodeProvider.notifier).state = null;
      if (mounted) context.go('/projects/${created.id}');
    }, successMessage: '新版本已创建');
  }

  Future<void> _export(Project project, String format) async {
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).get<dynamic>(
            ApiEndpoints.projectExport(project.id, format),
          );
      final name = '${project.key}-${project.version}';
      if (format == 'json') {
        final body = response.data;
        final data =
            body is Map && body.containsKey('data') ? body['data'] : body;
        final text = const JsonEncoder.withIndent('  ').convert(data);
        await FileSaver.instance.saveFile(
          name: name,
          bytes: Uint8List.fromList(utf8.encode(text)),
          ext: 'json',
          mimeType: MimeType.json,
        );
      } else {
        final text = response.data?.toString() ?? '';
        await FileSaver.instance.saveFile(
          name: name,
          bytes: Uint8List.fromList(utf8.encode(text)),
          ext: 'md',
          mimeType: MimeType.text,
        );
      }
    }, successMessage: format == 'json' ? 'JSON 已导出' : 'Markdown 已导出');
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败：$error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(projectDetailProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回项目列表',
          onPressed: () {
            ref.read(selectedNodeProvider.notifier).state = null;
            context.go('/projects');
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(detail.valueOrNull?.name ?? '项目编辑器'),
        actions: [
          if (detail.valueOrNull != null)
            _ProjectStatusChip(status: detail.valueOrNull!.status),
          if (detail.valueOrNull?.status == 'draft')
            TextButton.icon(
              onPressed: _busy ? null : () => _publish(detail.valueOrNull!),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('发布'),
            ),
          if (detail.valueOrNull?.status == 'published')
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final project = detail.valueOrNull!;
                      final template = await ref.read(
                        projectTemplateProvider(project.templateId).future,
                      );
                      if (mounted) _newVersion(project, template);
                    },
              icon: const Icon(Icons.fork_right_outlined),
              label: const Text('新版本'),
            ),
          PopupMenuButton<String>(
            tooltip: '导出项目',
            enabled: detail.valueOrNull != null && !_busy,
            onSelected: (format) => _export(detail.valueOrNull!, format),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'json',
                child: _MenuItem(
                  icon: Icons.data_object_rounded,
                  label: '导出 JSON',
                ),
              ),
              PopupMenuItem(
                value: 'markdown',
                child: _MenuItem(
                  icon: Icons.text_snippet_outlined,
                  label: '导出 Markdown',
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          detail.when(
            loading: () => const LoadingWidget(message: '正在打开项目…'),
            error: (error, _) => AppErrorWidget(
              message: '项目加载失败\n$error',
              retryLabel: '重新加载',
              onRetry: () =>
                  ref.invalidate(projectDetailProvider(widget.projectId)),
            ),
            data: (project) => _ProjectWorkspace(
              project: project,
              onTreeChanged: _refreshTree,
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectWorkspace extends ConsumerWidget {
  const _ProjectWorkspace({
    required this.project,
    required this.onTreeChanged,
  });

  final Project project;
  final Future<void> Function() onTreeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(projectTemplateProvider(project.templateId));
    final tree = ref.watch(projectTreeProvider(project.id));
    final selected = ref.watch(selectedNodeProvider);
    final user = ref.watch(authProvider).user;
    final editable = project.status == 'draft' &&
        (user?.hasAtLeastRole('editor') ?? false);
    final canManagePermissions =
        user?.hasAtLeastRole('project_admin') ?? false;
    return template.when(
      loading: () => const LoadingWidget(message: '正在读取项目模板…'),
      error: (error, _) => AppErrorWidget(
        message: '项目模板加载失败\n$error',
        retryLabel: '重新加载',
        onRetry: () =>
            ref.invalidate(projectTemplateProvider(project.templateId)),
      ),
      data: (template) => tree.when(
        loading: () => const LoadingWidget(message: '正在构建内容树…'),
        error: (error, _) => AppErrorWidget(
          message: '内容树加载失败\n$error',
          retryLabel: '重新加载',
          onRetry: () => ref.invalidate(projectTreeProvider(project.id)),
        ),
        data: (nodes) => Column(
          children: [
            if (!editable)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF1D6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      project.status == 'draft'
                          ? '当前账号仅有查看权限'
                          : '此版本已发布，不可编辑',
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final leftWidth = constraints.maxWidth < 900
                      ? constraints.maxWidth * 0.36
                      : 320.0;
                  return Row(
                    children: [
                      SizedBox(
                        width: leftWidth.clamp(270.0, 360.0),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              right: BorderSide(color: Color(0xFFD7DFEA)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ProjectSummary(
                                project: project,
                                template: template,
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 5),
                                child: Text(
                                  '内容树',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Expanded(
                                child: ProjectTreeView(
                                  projectId: project.id,
                                  nodes: nodes,
                                  template: template,
                                  isEditable: editable,
                                  canManagePermissions: canManagePermissions,
                                  onNodeSelected: (_) {},
                                  onTreeChanged: onTreeChanged,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: selected == null
                            ? const _NoNodeSelected()
                            : NodeDetailPanel(
                                key: ValueKey(selected.id),
                                node: selected,
                                template: template,
                                projectId: project.id,
                                isEditable: editable,
                                onNodeUpdated: onTreeChanged,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project, required this.template});

  final Project project;
  final Template template;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SummaryLine(Icons.key_outlined, 'Key', project.key),
            _SummaryLine(Icons.layers_outlined, '版本', project.version),
            _SummaryLine(
              Icons.account_tree_outlined,
              '模板',
              '${template.name} · ${template.version}',
            ),
          ],
        ),
      );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF77839A)),
            const SizedBox(width: 7),
            Text('$label：', style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _NoNodeSelected extends StatelessWidget {
  const _NoNodeSelected();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 52, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text('请选择节点查看详情', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            const Text('从左侧内容树选择任意节点'),
          ],
        ),
      );
}

class _ProjectStatusChip extends StatelessWidget {
  const _ProjectStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final published = status == 'published';
    return Chip(
      avatar: Icon(
        published ? Icons.verified_outlined : Icons.edit_note_outlined,
        size: 17,
        color: published ? const Color(0xFF18794E) : const Color(0xFF9A4A00),
      ),
      label: Text(published ? '已发布' : '草稿'),
      backgroundColor:
          published ? const Color(0xFFE7F5EC) : const Color(0xFFFFF1D6),
      side: BorderSide.none,
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 10),
          Text(label),
        ],
      );
}

class _NewVersionDialog extends StatefulWidget {
  const _NewVersionDialog({
    required this.currentVersion,
    required this.currentTemplate,
    required this.templateVersions,
  });

  final String currentVersion;
  final Template currentTemplate;
  final List<Template> templateVersions;

  @override
  State<_NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends State<_NewVersionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _version;
  final _note = TextEditingController();
  String? _newTemplateId;

  @override
  void initState() {
    super.initState();
    _version =
        TextEditingController(text: _incrementVersion(widget.currentVersion));
  }

  @override
  void dispose() {
    _version.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('创建新版本'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _version,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '新版本',
                    helperText: '当前版本：${widget.currentVersion}',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入版本号' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '版本说明'),
                ),
                if (widget.templateVersions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    value: _newTemplateId,
                    decoration: const InputDecoration(
                      labelText: '模板版本（可选）',
                      helperText: '留空则继续使用当前模板版本',
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          '${widget.currentTemplate.name} · ${widget.currentTemplate.version}',
                        ),
                      ),
                      ...widget.templateVersions.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text('${item.name} · ${item.version}'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _newTemplateId = value),
                  ),
                ],
              ],
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
                'version': _version.text.trim(),
                'version_note': _note.text.trim(),
                if (_newTemplateId != null) 'new_template_id': _newTemplateId,
              });
            },
            child: const Text('创建'),
          ),
        ],
      );
}

String _incrementVersion(String version) {
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(version.trim());
  if (match == null) return '$version.1';
  final prefix = match.group(1)!;
  final number = int.tryParse(match.group(2)!) ?? 0;
  return '$prefix${number + 1}';
}

Project _projectFromResponse(dynamic body) {
  final data = body is Map && body.containsKey('data') ? body['data'] : body;
  return Project.fromJson(Map<String, dynamic>.from(data as Map));
}
