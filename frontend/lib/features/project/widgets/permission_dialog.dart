import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/api/app_exception.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/node.dart';

class PermissionDialog extends ConsumerStatefulWidget {
  const PermissionDialog({
    required this.projectId,
    required this.nodeId,
    required this.nodeName,
    super.key,
  });

  final String projectId;
  final String nodeId;
  final String nodeName;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required String nodeId,
    required String nodeName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => PermissionDialog(
        projectId: projectId,
        nodeId: nodeId,
        nodeName: nodeName,
      ),
    );
  }

  @override
  ConsumerState<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends ConsumerState<PermissionDialog> {
  final _userId = TextEditingController();
  String _permissionType = 'editor';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<NodePermission> _permissions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).get<dynamic>(
            ApiEndpoints.projectNodePermissions(
              widget.projectId,
              widget.nodeId,
            ),
          );
      final body = response.data;
      final data =
          body is Map && body.containsKey('data') ? body['data'] : body;
      final items = (data as List? ?? const [])
          .map((item) =>
              NodePermission.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      if (mounted) setState(() => _permissions = items);
    } catch (error) {
      if (mounted) setState(() => _error = '权限加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final userId = _userId.text.trim();
    if (userId.isEmpty) {
      _message('请输入用户 ID', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post<dynamic>(
        ApiEndpoints.projectNodePermissions(widget.projectId, widget.nodeId),
        data: {
          'user_id': userId,
          'permission_type': _permissionType,
        },
      );
      _userId.clear();
      await _load();
      if (mounted) _message('权限已添加');
    } on ValidationException catch (error) {
      if (!mounted) return;
      final message = error.message.toLowerCase() == 'user does not exist'
          ? '用户不存在'
          : '添加失败：$error';
      _message(message, error: true);
    } catch (error) {
      if (mounted) _message('添加失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(NodePermission permission) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.projectNodePermission(
              widget.projectId,
              widget.nodeId,
              permission.id,
            ),
          );
      await _load();
      if (mounted) _message('权限已删除');
    } catch (error) {
      if (mounted) _message('删除失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('权限管理 - ${widget.nodeName}'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 19),
                    SizedBox(width: 9),
                    Expanded(child: Text('权限将应用于此节点及其所有子节点')),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('当前权限', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Center(
                  child: Column(
                    children: [
                      Text(_error!),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (_permissions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('尚未设置节点权限')),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const _PermissionHeader(),
                      const Divider(height: 1),
                      for (final permission in _permissions)
                        _PermissionRow(
                          permission: permission,
                          busy: _busy,
                          onDelete: () => _delete(permission),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              Text('添加权限', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final userField = TextField(
                    controller: _userId,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: '用户 ID',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onSubmitted: (_) => _add(),
                  );
                  final typeField = DropdownButtonFormField<String>(
                    value: _permissionType,
                    decoration: const InputDecoration(labelText: '权限类型'),
                    items: const [
                      DropdownMenuItem(value: 'editor', child: Text('编辑')),
                      DropdownMenuItem(value: 'viewer', child: Text('查看')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                              () => _permissionType = value ?? 'editor',
                            ),
                  );
                  final button = FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加'),
                  );
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        userField,
                        const SizedBox(height: 10),
                        typeField,
                        const SizedBox(height: 10),
                        button,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 3, child: userField),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: typeField),
                      const SizedBox(width: 10),
                      button,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _PermissionHeader extends StatelessWidget {
  const _PermissionHeader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text('用户')),
            Expanded(flex: 2, child: Text('权限类型')),
            SizedBox(width: 44, child: Text('操作')),
          ],
        ),
      );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.busy,
    required this.onDelete,
  });

  final NodePermission permission;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final editor = permission.permissionType == 'editor';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              permission.userId,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(editor ? '编辑' : '查看'),
                avatar: Icon(
                  editor ? Icons.edit_outlined : Icons.visibility_outlined,
                  size: 16,
                ),
                backgroundColor:
                    editor ? const Color(0xFFE9F1FB) : const Color(0xFFF0F2F5),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: '删除权限',
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
