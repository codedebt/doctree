import 'package:flutter/material.dart';

class TemplateListPage extends StatelessWidget {
  const TemplateListPage({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderScaffold(
        title: '模板管理',
      );
}

class TemplateEditPage extends StatelessWidget {
  const TemplateEditPage({required this.templateId, super.key});

  final String templateId;

  @override
  Widget build(BuildContext context) => _PlaceholderScaffold(
        title: '模板编辑',
        subtitle: templateId,
      );
}

class ProjectListPage extends StatelessWidget {
  const ProjectListPage({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderScaffold(
        title: '项目管理',
      );
}

class ProjectEditPage extends StatelessWidget {
  const ProjectEditPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) => _PlaceholderScaffold(
        title: '项目编辑',
        subtitle: projectId,
      );
}

class _PlaceholderScaffold extends StatelessWidget {
  const _PlaceholderScaffold({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
