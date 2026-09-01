import 'package:flutter/material.dart';

import '../../../models/node.dart';
import '../../../models/template.dart';

class NodeContextMenu {
  NodeContextMenu._();

  static Future<void> show(
    BuildContext context, {
    required TreeNode node,
    required Template template,
    required bool isEditable,
    required bool canManagePermissions,
    required ValueChanged<String> onAddChild,
    required VoidCallback onDelete,
    required VoidCallback onManagePermissions,
    required Offset position,
    List<TreeNode> allNodes = const [],
  }) async {
    final allowed = _allowedChildren(node, template, allNodes);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isEditable) ...[
          if (allowed.isEmpty)
            const PopupMenuItem<String>(
              enabled: false,
              child: _MenuLabel(
                icon: Icons.add_circle_outline,
                label: '没有可添加的子节点类型',
              ),
            )
          else
            for (final item in allowed)
              PopupMenuItem<String>(
                value: item.enabled ? 'add:${item.type.key}' : null,
                enabled: item.enabled,
                child: _MenuLabel(
                  icon: Icons.add_rounded,
                  label: '添加 ${item.type.name}',
                  trailing: item.enabled ? null : '已达上限',
                ),
              ),
          if (canManagePermissions || node.parentId != null)
            const PopupMenuDivider(),
        ],
        if (canManagePermissions)
          const PopupMenuItem<String>(
            value: 'permissions',
            child: _MenuLabel(
              icon: Icons.admin_panel_settings_outlined,
              label: '权限管理',
            ),
          ),
        if (isEditable && node.parentId != null)
          const PopupMenuItem<String>(
            value: 'delete',
            child: _MenuLabel(
              icon: Icons.delete_outline,
              label: '删除节点',
              destructive: true,
            ),
          ),
      ],
    );
    if (!context.mounted || selected == null) return;
    if (selected.startsWith('add:')) {
      onAddChild(selected.substring(4));
    } else if (selected == 'delete') {
      onDelete();
    } else if (selected == 'permissions') {
      onManagePermissions();
    }
  }

  static List<_AllowedType> _allowedChildren(
    TreeNode node,
    Template template,
    List<TreeNode> allNodes,
  ) {
    NodeType? parentType;
    for (final type in template.nodeTypes) {
      if (type.key == node.nodeTypeKey) {
        parentType = type;
        break;
      }
    }
    if (parentType == null) return const [];

    final result = <_AllowedType>[];
    for (final rule in template.nodeRules) {
      final parentMatches = !rule.isRootRule &&
          (rule.parentNodeTypeId == parentType.id ||
              rule.parentNodeTypeId == parentType.key);
      if (!parentMatches) continue;
      NodeType? childType;
      for (final type in template.nodeTypes) {
        if (type.id == rule.childNodeTypeId ||
            type.key == rule.childNodeTypeId) {
          childType = type;
          break;
        }
      }
      if (childType == null) continue;
      final childCount = allNodes
          .where((item) =>
              item.parentId == node.id && item.nodeTypeKey == childType!.key)
          .length;
      result.add(
        _AllowedType(
          type: childType,
          enabled: rule.maxCount <= 0 || childCount < rule.maxCount,
        ),
      );
    }
    result.sort((a, b) => a.type.sortOrder.compareTo(b.type.sortOrder));
    return result;
  }
}

class _AllowedType {
  const _AllowedType({required this.type, required this.enabled});

  final NodeType type;
  final bool enabled;
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({
    required this.icon,
    required this.label,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: color))),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}
