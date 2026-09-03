import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
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
import '../../../shared/widgets/reorder_handle.dart';
import '../template_provider.dart';
import '../widgets/node_type_editor.dart';
import '../widgets/rule_editor.dart';

class TemplateEditPage extends ConsumerStatefulWidget {
  const TemplateEditPage({required this.templateId, super.key});

  final String templateId;

  @override
  ConsumerState<TemplateEditPage> createState() => _TemplateEditPageState();
}

class _TemplateEditPageState extends ConsumerState<TemplateEditPage> {
  bool _actionBusy = false;

  // 通过刷新 templateDetailProvider 拉取，使结构变更（新增/删除/排序）同时写回该 provider 的缓存，
  // 否则页面重建时仍会拿到变更前的旧数据。
  Future<Template> _fetchDetail() async {
    final template = await ref.refresh(
      templateDetailProvider(widget.templateId).future,
    );
    ref
        .read(templateEditorProvider(widget.templateId).notifier)
        .loadTemplate(template);
    return template;
  }

  Future<void> _publish(Template template) async {
    await ref.read(templateEditorProvider(widget.templateId).notifier).flush();
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '发布模板',
      message: '确认发布此模板？发布后将无法编辑。',
      confirmLabel: '确认发布',
      cancelLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.templatePublish(template.id),
          );
      final published = _templateFromResponse(response.data);
      ref
          .read(templateEditorProvider(widget.templateId).notifier)
          .loadTemplate(published);
      ref.invalidate(templateDetailProvider(widget.templateId));
      ref.invalidate(templateListProvider(''));
      ref.invalidate(templateListProvider('draft'));
      ref.invalidate(templateListProvider('published'));
    }, successMessage: '模板已发布');
  }

  Future<void> _newVersion(Template template) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _NewVersionDialog(currentVersion: template.version),
    );
    if (result == null || !mounted) return;
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.templateNewVersion(template.id),
            data: result,
          );
      final created = _templateFromResponse(response.data);
      ref.invalidate(templateListProvider(''));
      if (mounted) context.go('/templates/${created.id}');
    }, successMessage: '新版本已创建');
  }

  Future<void> _export(Template template) async {
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).get<dynamic>(
            ApiEndpoints.templateExport(template.id),
          );
      final body = response.data;
      final data =
          body is Map && body.containsKey('data') ? body['data'] : body;
      final json = const JsonEncoder.withIndent('  ').convert(data);
      await FileSaver.instance.saveFile(
        name: '${template.key}-${template.version}',
        bytes: Uint8List.fromList(utf8.encode(json)),
        ext: 'json',
        mimeType: MimeType.json,
      );
    }, successMessage: '模板已导出');
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _actionBusy = true);
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
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
    final detail = ref.watch(templateDetailProvider(widget.templateId));
    final edited = ref.watch(templateEditorProvider(widget.templateId));
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回模板列表',
            onPressed: () => context.go('/templates'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(edited?.name ?? detail.valueOrNull?.name ?? '模板编辑器'),
          actions: [
            if (edited?.status == 'draft')
              _ActionButton(
                icon: Icons.rocket_launch_outlined,
                label: '发布',
                compact: !wide,
                onPressed: _actionBusy ? null : () => _publish(edited!),
              ),
            if (edited?.status == 'published')
              _ActionButton(
                icon: Icons.fork_right_outlined,
                label: '新版本',
                compact: !wide,
                onPressed: _actionBusy ? null : () => _newVersion(edited!),
              ),
            _ActionButton(
              icon: Icons.download_outlined,
              label: '导出',
              compact: !wide,
              onPressed:
                  edited == null || _actionBusy ? null : () => _export(edited),
            ),
            const SizedBox(width: 12),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.tune_outlined), text: '基本信息'),
              Tab(icon: Icon(Icons.account_tree_outlined), text: '节点类型'),
              Tab(icon: Icon(Icons.device_hub_outlined), text: '节点规则'),
            ],
          ),
        ),
        body: Stack(
          children: [
            detail.when(
              loading: () => const LoadingWidget(message: '正在打开模板…'),
              error: (error, _) => AppErrorWidget(
                message: '模板加载失败\n$error',
                retryLabel: '重新加载',
                onRetry: () =>
                    ref.invalidate(templateDetailProvider(widget.templateId)),
              ),
              data: (template) {
                if (edited == null) {
                  Future.microtask(
                    () => ref
                        .read(
                            templateEditorProvider(widget.templateId).notifier)
                        .loadTemplate(template),
                  );
                }
                final current = edited ?? template;
                final editable = current.status == 'draft';
                return TabBarView(
                  children: [
                    _BasicInfoTab(
                      template: current,
                      editable: editable,
                      onChanged: (field, value) => ref
                          .read(templateEditorProvider(widget.templateId)
                              .notifier)
                          .updateField(field, value),
                    ),
                    _NodeTypesTab(
                      templateId: current.id,
                      nodeTypes: current.nodeTypes,
                      isEditable: editable,
                      onStructureChanged: _fetchDetail,
                    ),
                    _ScrollableTab(
                      child: RuleEditor(
                        templateId: current.id,
                        rules: current.nodeRules,
                        nodeTypes: current.nodeTypes,
                        isEditable: editable,
                        onChanged: _fetchDetail,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_actionBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _BasicInfoTab extends StatefulWidget {
  const _BasicInfoTab({
    required this.template,
    required this.editable,
    required this.onChanged,
  });

  final Template template;
  final bool editable;
  final void Function(String field, String value) onChanged;

  @override
  State<_BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends State<_BasicInfoTab> {
  late final TextEditingController _name;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template.name);
    _note = TextEditingController(text: widget.template.versionNote);
  }

  @override
  void didUpdateWidget(covariant _BasicInfoTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.id != widget.template.id) {
      _name.text = widget.template.name;
      _note.text = widget.template.versionNote;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('模板档案',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 5),
                        Text(
                          widget.editable ? '内容会在输入后自动保存' : '已发布版本仅供查看',
                        ),
                      ],
                    ),
                  ),
                  _EditorStatus(status: widget.template.status),
                ],
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                enabled: widget.editable,
                onChanged: (value) => widget.onChanged('name', value),
                decoration: const InputDecoration(
                  labelText: '模板名称',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final keyField = TextFormField(
                    initialValue: widget.template.key,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: '模板 Key',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  );
                  final versionField = TextFormField(
                    initialValue: widget.template.version,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: '版本',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      children: [
                        keyField,
                        const SizedBox(height: 16),
                        versionField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: keyField),
                      const SizedBox(width: 16),
                      Expanded(child: versionField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                enabled: widget.editable,
                onChanged: (value) => widget.onChanged('version_note', value),
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: '版本说明',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 70),
                    child: Icon(Icons.notes_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorStatus extends StatelessWidget {
  const _EditorStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final published = status == 'published';
    return Chip(
      avatar: Icon(
        published ? Icons.verified_outlined : Icons.edit_note_outlined,
        size: 18,
        color: published ? const Color(0xFF18794E) : const Color(0xFF9A4A00),
      ),
      label: Text(published ? '已发布' : '草稿'),
      backgroundColor:
          published ? const Color(0xFFE7F5EC) : const Color(0xFFFFF1D6),
      side: BorderSide.none,
    );
  }
}

class _NodeTypesTab extends ConsumerStatefulWidget {
  const _NodeTypesTab({
    required this.templateId,
    required this.nodeTypes,
    required this.isEditable,
    required this.onStructureChanged,
  });

  final String templateId;
  final List<NodeType> nodeTypes;
  final bool isEditable;
  final Future<Template> Function() onStructureChanged;

  @override
  ConsumerState<_NodeTypesTab> createState() => _NodeTypesTabState();
}

class _NodeTypesTabState extends ConsumerState<_NodeTypesTab> {
  late List<NodeType> _nodeTypes;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _nodeTypes = _orderedNodeTypes(widget.nodeTypes);
    _selectedId = _nodeTypes.isEmpty ? null : _nodeTypes.first.id;
  }

  @override
  void didUpdateWidget(covariant _NodeTypesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodeTypes, widget.nodeTypes)) {
      _nodeTypes = _orderedNodeTypes(widget.nodeTypes);
      if (!_nodeTypes.any((item) => item.id == _selectedId)) {
        _selectedId = _nodeTypes.isEmpty ? null : _nodeTypes.first.id;
      }
    }
  }

  Future<void> _addNodeType() async {
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _NodeTypeDialog(),
    );
    if (data == null || !mounted) return;
    try {
      final response = await ref.read(apiClientProvider).post<dynamic>(
            ApiEndpoints.templateNodeTypes(widget.templateId),
            data: data,
          );
      final body = response.data as Map;
      final nodeType = NodeType.fromJson(
        Map<String, dynamic>.from(body['data'] as Map? ?? body),
      );
      setState(() {
        _nodeTypes.add(nodeType);
        _selectedId = nodeType.id;
      });
      await widget.onStructureChanged();
    } catch (error) {
      if (mounted) _showError('创建节点类型失败：$error');
    }
  }

  Future<void> _reload() async {
    try {
      await widget.onStructureChanged();
    } catch (error) {
      if (mounted) _showError('刷新失败：$error');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    await _move(oldIndex, newIndex);
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final previous = List<NodeType>.from(_nodeTypes);
    setState(() {
      final item = _nodeTypes.removeAt(oldIndex);
      _nodeTypes.insert(newIndex, item);
    });
    try {
      await ref.read(apiClientProvider).put<dynamic>(
        ApiEndpoints.templateNodeTypeSort(widget.templateId),
        data: {'ids': _nodeTypes.map((item) => item.id).toList()},
      );
      await widget.onStructureChanged();
    } catch (error) {
      if (mounted) {
        setState(() => _nodeTypes = previous);
        _showError('节点类型排序失败：$error');
      }
    }
  }

  void _removeSelected() {
    setState(() {
      _nodeTypes.removeWhere((item) => item.id == _selectedId);
      _selectedId = _nodeTypes.isEmpty ? null : _nodeTypes.first.id;
    });
    _reload();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _nodeTypes
        .where((item) => item.id == _selectedId)
        .cast<NodeType?>()
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final navigation = _NodeTypeNavigation(
          nodeTypes: _nodeTypes,
          selectedId: _selectedId,
          editable: widget.isEditable,
          onSelected: (id) => setState(() => _selectedId = id),
          onAdd: _addNodeType,
          onReorder: _reorder,
        );
        final editor = selected == null
            ? const _NoNodeTypeSelected()
            : NodeTypeEditor(
                key: ValueKey(selected.id),
                templateId: widget.templateId,
                nodeType: selected,
                isEditable: widget.isEditable,
                onDeleted: _removeSelected,
                onChanged: _reload,
              );
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 280, child: navigation),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: editor,
                  ),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              navigation,
              const SizedBox(height: 14),
              editor,
            ],
          ),
        );
      },
    );
  }
}

class _NodeTypeNavigation extends StatelessWidget {
  const _NodeTypeNavigation({
    required this.nodeTypes,
    required this.selectedId,
    required this.editable,
    required this.onSelected,
    required this.onAdd,
    required this.onReorder,
  });

  final List<NodeType> nodeTypes;
  final String? selectedId;
  final bool editable;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('节点类型',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (editable)
                      IconButton.filledTonal(
                        tooltip: '添加节点类型',
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded),
                      ),
                  ],
                ),
              ),
              if (nodeTypes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('暂无节点类型'),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: reorderProxyDecorator,
                  itemCount: nodeTypes.length,
                  onReorder: onReorder,
                  itemBuilder: (context, index) {
                    final nodeType = nodeTypes[index];
                    final selected = nodeType.id == selectedId;
                    return Padding(
                      key: ValueKey(nodeType.id),
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: selected
                            ? const Color(0xFFE9F1FB)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => onSelected(nodeType.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nodeType.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      Text(
                                        nodeType.key,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (editable) ...[
                                  const SizedBox(width: 6),
                                  ReorderHandle(index: index),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
}

class _NoNodeTypeSelected extends StatelessWidget {
  const _NoNodeTypeSelected();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
          child: Column(
            children: [
              const Icon(Icons.account_tree_outlined, size: 48),
              const SizedBox(height: 12),
              Text('选择或创建节点类型', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
}

class _ScrollableTab extends StatelessWidget {
  const _ScrollableTab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: child,
          ),
        ),
      );
}

class _NodeTypeDialog extends StatefulWidget {
  const _NodeTypeDialog();

  @override
  State<_NodeTypeDialog> createState() => _NodeTypeDialogState();
}

class _NodeTypeDialogState extends State<_NodeTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加节点类型'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '节点类型名称'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _key,
                  decoration: const InputDecoration(labelText: '节点类型 Key'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '说明'),
                ),
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
                'name': _name.text.trim(),
                'key': _key.text.trim(),
                'description': _description.text.trim(),
              });
            },
            child: const Text('添加'),
          ),
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;
}

class _NewVersionDialog extends StatefulWidget {
  const _NewVersionDialog({required this.currentVersion});

  final String currentVersion;

  @override
  State<_NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends State<_NewVersionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _version = TextEditingController();
  final _note = TextEditingController();

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
          width: 440,
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
                      value == null || value.trim().isEmpty ? '请输入新版本号' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '版本说明'),
                ),
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
              });
            },
            child: const Text('创建'),
          ),
        ],
      );
}

List<NodeType> _orderedNodeTypes(List<NodeType> source) {
  final result = List<NodeType>.from(source);
  result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return result;
}

Template _templateFromResponse(dynamic body) {
  final data = body is Map && body.containsKey('data') ? body['data'] : body;
  return Template.fromJson(Map<String, dynamic>.from(data as Map));
}
