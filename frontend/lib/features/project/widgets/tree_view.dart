import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/node.dart';
import '../../../models/template.dart';
import '../../../shared/widgets/browser_context_menu_scope.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../project_provider.dart';
import 'context_menu.dart';
import 'permission_dialog.dart';

class ProjectTreeView extends ConsumerStatefulWidget {
  const ProjectTreeView({
    required this.projectId,
    required this.nodes,
    required this.template,
    required this.isEditable,
    required this.canManagePermissions,
    required this.onNodeSelected,
    this.onTreeChanged,
    super.key,
  });

  final String projectId;
  final List<TreeNode> nodes;
  final Template template;
  final bool isEditable;
  final bool canManagePermissions;
  final ValueChanged<TreeNode> onNodeSelected;
  final VoidCallback? onTreeChanged;

  @override
  ConsumerState<ProjectTreeView> createState() => _ProjectTreeViewState();
}

class _ProjectTreeViewState extends ConsumerState<ProjectTreeView> {
  List<TreeNode> _lastNodes = const [];

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  @override
  void didUpdateWidget(covariant ProjectTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes)) _loadNodes();
  }

  void _loadNodes() {
    _lastNodes = widget.nodes;
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(projectTreeStateProvider(widget.projectId).notifier)
          .load(_lastNodes);
    });
  }

  Future<void> _addChild(TreeNode parent, String nodeTypeKey) async {
    final type = widget.template.nodeTypes
        .where((item) => item.key == nodeTypeKey)
        .firstOrNull;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _AddNodeDialog(typeName: type?.name ?? '节点'),
    );
    if (name == null || !mounted) return;
    try {
      final response = await ref.read(apiClientProvider).post<dynamic>(
        ApiEndpoints.projectNodes(widget.projectId),
        data: {
          'parent_id': parent.id,
          'node_type_key': nodeTypeKey,
          'name': name,
        },
      );
      final body = response.data;
      final data =
          body is Map && body.containsKey('data') ? body['data'] : body;
      final created = TreeNode.fromJson(Map<String, dynamic>.from(data as Map));
      ref
          .read(projectTreeStateProvider(widget.projectId).notifier)
          .addNode(created);
      widget.onTreeChanged?.call();
      if (mounted) _message('节点已添加');
    } catch (error) {
      if (mounted) _message('添加失败：$error', error: true);
    }
  }

  Future<void> _delete(TreeNode node) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点',
      message: '确认删除“${node.name}”及其全部子节点？',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.projectNode(widget.projectId, node.id),
          );
      ref
          .read(projectTreeStateProvider(widget.projectId).notifier)
          .deleteNode(node.id);
      if (ref.read(selectedNodeProvider)?.id == node.id) {
        ref.read(selectedNodeProvider.notifier).state = null;
      }
      widget.onTreeChanged?.call();
      if (mounted) _message('节点已删除');
    } catch (error) {
      if (mounted) _message('删除失败：$error', error: true);
    }
  }

  Future<void> _showMenu(TreeNode node, Offset position) async {
    if (!widget.isEditable && !widget.canManagePermissions) return;
    await BrowserContextMenuScope.keepDisabled(
      () => NodeContextMenu.show(
        context,
        node: node,
        template: widget.template,
        isEditable: widget.isEditable,
        canManagePermissions: widget.canManagePermissions,
        allNodes: widget.nodes,
        position: position,
        onAddChild: (key) => _addChild(node, key),
        onDelete: () => _delete(node),
        onManagePermissions: () {
          PermissionDialog.show(
            context,
            projectId: widget.projectId,
            nodeId: node.id,
            nodeName: node.name,
          );
        },
      ),
    );
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(projectTreeStateProvider(widget.projectId));
    final notifier =
        ref.read(projectTreeStateProvider(widget.projectId).notifier);
    final selectedId = notifier.selectedNodeId;
    final visible = <({TreeNode node, int depth})>[];

    void collect(TreeNode node, int depth) {
      visible.add((node: node, depth: depth));
      if (notifier.expandedNodeIds.contains(node.id)) {
        for (final child in node.children) {
          collect(child, depth + 1);
        }
      }
    }

    for (final root in tree) {
      collect(root, 0);
    }

    if (tree.isEmpty) {
      return const Center(child: Text('暂无节点'));
    }
    return BrowserContextMenuScope(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                return TreeNodeItem(
                  node: item.node,
                  depth: item.depth,
                  isExpanded: notifier.expandedNodeIds.contains(item.node.id),
                  isSelected: item.node.id == selectedId,
                  hasChildren: item.node.children.isNotEmpty,
                  nodeType: widget.template.nodeTypes
                      .where((type) => type.key == item.node.nodeTypeKey)
                      .firstOrNull,
                  onToggle: () => notifier.toggleExpand(item.node.id),
                  onSelected: () {
                    notifier.selectNode(item.node.id);
                    ref.read(selectedNodeProvider.notifier).state = item.node;
                    widget.onNodeSelected(item.node);
                  },
                  onSecondaryTap: (position) => _showMenu(item.node, position),
                );
              },
            ),
          ),
          if (widget.isEditable &&
              tree.length == 1 &&
              tree.first.children.isEmpty)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.ads_click_outlined, size: 18),
                  SizedBox(width: 9),
                  Expanded(child: Text('暂无节点，右键根节点添加')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TreeNodeItem extends StatelessWidget {
  const TreeNodeItem({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.hasChildren,
    required this.onToggle,
    required this.onSelected,
    required this.onSecondaryTap,
    this.nodeType,
    super.key,
  });

  final TreeNode node;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool hasChildren;
  final NodeType? nodeType;
  final VoidCallback onToggle;
  final VoidCallback onSelected;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final typeColor = _parseColor(nodeType?.color);
    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0, bottom: 3),
      child: GestureDetector(
        onDoubleTap: hasChildren ? onToggle : null,
        onLongPressStart: (details) => onSecondaryTap(details.globalPosition),
        onSecondaryTapDown: (details) =>
            onSecondaryTap(details.globalPosition),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onSelected,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: hasChildren
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: isExpanded ? '折叠' : '展开',
                            onPressed: onToggle,
                            icon: Icon(
                              isExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 20,
                            ),
                          )
                        : null,
                  ),
                  Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      depth == 0
                          ? Icons.account_tree_outlined
                          : Icons.description_outlined,
                      color: typeColor,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          nodeType?.name ?? node.nodeTypeKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddNodeDialog extends StatefulWidget {
  const _AddNodeDialog({required this.typeName});

  final String typeName;

  @override
  State<_AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<_AddNodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('添加${widget.typeName}'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '节点名称'),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: _submit, child: const Text('添加')),
        ],
      );

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }
}

Color _parseColor(String? value) {
  final normalized = value?.replaceFirst('#', '') ?? '';
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return const Color(0xFF1565C0);
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}
