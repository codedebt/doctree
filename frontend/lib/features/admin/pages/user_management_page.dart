import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../admin_provider.dart';

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  int _page = 1;
  String? _updatingUserId;

  Future<void> _changeRole(User user, String role) async {
    if (role == user.role) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '确认调整角色',
      message:
          '将 ${user.username} 的角色从“${_roleLabel(user.role)}”调整为“${_roleLabel(role)}”？',
      confirmLabel: '确认调整',
      cancelLabel: '取消',
    );
    if (!confirmed || !mounted) return;

    setState(() => _updatingUserId = user.id);
    try {
      await ref.read(apiClientProvider).post<dynamic>(
        ApiEndpoints.userRole(user.id),
        data: {'role': role},
      );
      ref.invalidate(usersProvider(_page));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('用户角色已更新。')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('角色更新失败，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;
    final usersValue = ref.watch(usersProvider(_page));

    return Scaffold(
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(usersProvider(_page)),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminHeader(currentUser: currentUser),
            const SizedBox(height: 18),
            Expanded(
              child: usersValue.when(
                loading: () => const LoadingWidget(message: '正在加载用户…'),
                error: (_, __) => AppErrorWidget(
                  message: '用户列表加载失败，请检查网络后重试。',
                  retryLabel: '重新加载',
                  onRetry: () => ref.invalidate(usersProvider(_page)),
                ),
                data: (payload) {
                  final users = _parseUsers(payload['data']);
                  if (users.isEmpty) return const _EmptyUsers();
                  return LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 820
                            ? _UsersTable(
                                users: users,
                                currentUser: currentUser,
                                updatingUserId: _updatingUserId,
                                onRoleChanged: _changeRole,
                              )
                            : _UsersList(
                                users: users,
                                currentUser: currentUser,
                                updatingUserId: _updatingUserId,
                                onRoleChanged: _changeRole,
                              ),
                  );
                },
              ),
            ),
            usersValue.maybeWhen(
              data: (payload) {
                final total = _asInt(payload['total']);
                final totalPages =
                    math.max(1, (total / adminUsersPageSize).ceil());
                return _Pagination(
                  page: _page,
                  totalPages: totalPages,
                  total: total,
                  onChanged: (page) => setState(() => _page = page),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  List<User> _parseUsers(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => User.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.currentUser});

  final User? currentUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF102A2A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF20433F),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.people_outline, color: Color(0xFF7DDFC7)),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '团队成员与权限',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 19,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '角色调整会立即影响用户可访问的工作区。',
                  style: TextStyle(color: Color(0xFFB7CDC7)),
                ),
              ],
            ),
          ),
          if (currentUser != null)
            Text(
              '当前角色：${_roleLabel(currentUser!.role)}',
              style: const TextStyle(color: Color(0xFFB7CDC7)),
            ),
        ],
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.currentUser,
    required this.updatingUserId,
    required this.onRoleChanged,
  });

  final List<User> users;
  final User? currentUser;
  final String? updatingUserId;
  final void Function(User, String) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(const Color(0xFFF0F5F3)),
            columns: const [
              DataColumn(label: Text('用户名')),
              DataColumn(label: Text('邮箱')),
              DataColumn(label: Text('角色')),
              DataColumn(label: Text('创建时间')),
              DataColumn(label: Text('操作')),
            ],
            rows: users
                .map(
                  (user) => DataRow(
                    cells: [
                      DataCell(Row(children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFFE4EFEC),
                          child: Text(
                              user.username.isEmpty ? '?' : user.username[0]),
                        ),
                        const SizedBox(width: 10),
                        Text(user.username),
                      ])),
                      DataCell(Text(user.email.isEmpty ? '—' : user.email)),
                      DataCell(_RoleBadge(role: user.role)),
                      DataCell(Text(_formatDate(user.createdAt))),
                      DataCell(_RoleAction(
                        user: user,
                        currentUser: currentUser,
                        isUpdating: updatingUserId == user.id,
                        onChanged: onRoleChanged,
                      )),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.users,
    required this.currentUser,
    required this.updatingUserId,
    required this.onRoleChanged,
  });

  final List<User> users;
  final User? currentUser;
  final String? updatingUserId;
  final void Function(User, String) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE4EFEC),
                      child:
                          Text(user.username.isEmpty ? '?' : user.username[0]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.username,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(user.email.isEmpty ? '未设置邮箱' : user.email),
                        ],
                      ),
                    ),
                    _RoleAction(
                      user: user,
                      currentUser: currentUser,
                      isUpdating: updatingUserId == user.id,
                      onChanged: onRoleChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoleBadge(role: user.role),
                    Text('加入于 ${_formatDate(user.createdAt)}'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleAction extends StatelessWidget {
  const _RoleAction({
    required this.user,
    required this.currentUser,
    required this.isUpdating,
    required this.onChanged,
  });

  final User user;
  final User? currentUser;
  final bool isUpdating;
  final void Function(User, String) onChanged;

  @override
  Widget build(BuildContext context) {
    if (isUpdating) {
      return const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final operator = currentUser;
    final canManage = operator != null &&
        operator.id != user.id &&
        !user.hasAtLeastRole(operator.role);
    final roles =
        operator == null ? const <String>[] : _assignableRoles(operator.role);
    if (!canManage || roles.isEmpty) {
      return const Tooltip(
        message: '无法调整此用户角色',
        child: Icon(Icons.lock_outline_rounded, color: Color(0xFF94A0AE)),
      );
    }
    return PopupMenuButton<String>(
      tooltip: '调整角色',
      onSelected: (role) => onChanged(user, role),
      itemBuilder: (context) => roles
          .map(
            (role) => PopupMenuItem(
              value: role,
              child: Row(
                children: [
                  if (role == user.role) const Icon(Icons.check, size: 18),
                  if (role == user.role) const SizedBox(width: 8),
                  Text(_roleLabel(role)),
                ],
              ),
            ),
          )
          .toList(),
      icon: const Icon(Icons.manage_accounts_outlined),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EFEC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _roleLabel(role),
        style: const TextStyle(
          color: Color(0xFF245D55),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.onChanged,
  });

  final int page;
  final int totalPages;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('共 $total 位用户  ·  第 $page / $totalPages 页'),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: '上一页',
            onPressed: page > 1 ? () => onChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: '下一页',
            onPressed: page < totalPages ? () => onChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_outlined, size: 46, color: Color(0xFF94A0AE)),
          SizedBox(height: 12),
          Text('暂无用户'),
        ],
      ),
    );
  }
}

List<String> _assignableRoles(String operatorRole) {
  const roles = [
    'super_admin',
    'system_admin',
    'template_admin',
    'project_admin',
    'editor',
    'viewer',
  ];
  const rank = {
    'super_admin': 6,
    'system_admin': 5,
    'template_admin': 4,
    'project_admin': 3,
    'editor': 2,
    'viewer': 1,
  };
  final operatorRank = rank[operatorRole] ?? 0;
  return roles.where((role) => (rank[role] ?? 0) < operatorRank).toList();
}

String _roleLabel(String role) => switch (role) {
      'super_admin' => '超级管理员',
      'system_admin' => '系统管理员',
      'template_admin' => '模板管理员',
      'project_admin' => '项目管理员',
      'editor' => '编辑者',
      _ => '访客',
    };

String _formatDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}
