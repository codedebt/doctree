import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../models/user.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final destinations = <_Destination>[
      const _Destination(
        title: '项目管理',
        description: '组织项目结构，协作编辑与发布内容',
        route: '/projects',
        icon: Icons.folder_outlined,
        color: Color(0xFFE9784D),
      ),
      if (user.hasAtLeastRole('template_admin'))
        const _Destination(
          title: '模板管理',
          description: '定义内容规范，让团队保持一致',
          route: '/templates',
          icon: Icons.description_outlined,
          color: Color(0xFF2A7C73),
        ),
      if (user.hasAtLeastRole('project_admin'))
        const _Destination(
          title: '用户管理',
          description: '管理成员账号与访问角色',
          route: '/admin/users',
          icon: Icons.people_outline_rounded,
          color: Color(0xFF365B8C),
        ),
      if (user.hasAtLeastRole('system_admin'))
        const _Destination(
          title: '系统设置',
          description: '查看认证方式与系统运行信息',
          route: '/admin/settings',
          icon: Icons.settings_outlined,
          color: Color(0xFF8A623F),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeBrandMark(),
            SizedBox(width: 10),
            Text('Doctree'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: _UserChip(user: user),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '退出登录',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 1000 ? 72.0 : 24.0;
          final columns = constraints.maxWidth >= 1180
              ? 4
              : constraints.maxWidth >= 720
                  ? 2
                  : 1;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    horizontalPadding, 52, horizontalPadding, 24),
                sliver: SliverToBoxAdapter(
                  child: _WelcomeHeader(user: user),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    horizontalPadding, 16, horizontalPadding, 56),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    childAspectRatio: columns == 1 ? 2.25 : 1.18,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _DestinationCard(
                      destination: destinations[index],
                      index: index,
                    ),
                    childCount: destinations.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF102A2A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180B2523),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -8,
            top: -30,
            child: Icon(
              Icons.account_tree_outlined,
              color: Color(0x223BD1AD),
              size: 150,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '工作台',
                style: TextStyle(
                  color: Color(0xFFE9784D),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${user.username}，今天从哪里开始？',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择一个工作区，继续构建清晰、可追溯的知识结构。',
                style: TextStyle(color: Color(0xFFB7CDC7), fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatefulWidget {
  const _DestinationCard({required this.destination, required this.index});

  final _Destination destination;
  final int index;

  @override
  State<_DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends State<_DestinationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.destination;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 420 + widget.index * 90),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 18 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _hovered ? 1.018 : 1,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.go(item.route),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(item.icon, color: item.color, size: 28),
                        ),
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 180),
                          offset: _hovered ? const Offset(.15, 0) : Offset.zero,
                          child: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 7),
                        Text(item.description),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DFEA)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFFE4EFEC),
            child: Text(
              user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF245D55)),
            ),
          ),
          const SizedBox(width: 8),
          Text(user.username,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 7),
          Text(
            _roleLabel(user.role),
            style: const TextStyle(fontSize: 12, color: Color(0xFF66768B)),
          ),
        ],
      ),
    );
  }
}

class _HomeBrandMark extends StatelessWidget {
  const _HomeBrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFFE9784D),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.account_tree_outlined,
          color: Colors.white, size: 19),
    );
  }
}

class _Destination {
  const _Destination({
    required this.title,
    required this.description,
    required this.route,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final String route;
  final IconData icon;
  final Color color;
}

String _roleLabel(String role) => switch (role) {
      'super_admin' => '超级管理员',
      'system_admin' => '系统管理员',
      'template_admin' => '模板管理员',
      'project_admin' => '项目管理员',
      'editor' => '编辑者',
      _ => '访客',
    };
