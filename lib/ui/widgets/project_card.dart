import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/models/project.dart';
import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/process_provider.dart';
import '../../state/projects_provider.dart';
import 'status_badge.dart';
import 'tactile_press.dart';

class ProjectCard extends StatelessWidget {
  final Project project;

  const ProjectCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final projectsProvider = context.read<ProjectsProvider>();
    final processProvider = context.read<ProcessProvider>();
    final appState = context.read<AppState>();
    final isRunning = project.status == ProjectState.running;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.code, color: AppTheme.primaryBlue, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              project.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          StatusBadge(status: project.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project.githubUrl,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Port & URL pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_rounded, size: 14, color: AppTheme.accentCyan),
                      const SizedBox(width: 5),
                      Text(
                        'Port ${project.port}',
                        style: AppTheme.tabularNumberStyle.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            // Tags row (Language, Framework, Database)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.code_rounded, size: 14),
                  label: Text(project.techStack.language.displayName),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.layers_outlined, size: 14),
                  label: Text(project.techStack.framework.displayName),
                  visualDensity: VisualDensity.compact,
                ),
                if (project.databaseType != DatabaseType.none)
                  Chip(
                    avatar: const Icon(Icons.storage, size: 14),
                    label: Text(project.databaseType.displayName),
                    visualDensity: VisualDensity.compact,
                  ),
                if (project.techStack.packageManager != null)
                  Chip(
                    avatar: const Icon(Icons.inventory_2_outlined, size: 14),
                    label: Text(project.techStack.packageManager!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Action Buttons (Wrap prevents horizontal overflow on narrower widths)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isRunning)
                        TactilePress(
                          onTap: () => projectsProvider.startProject(project, processProvider),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                            icon: const Icon(Icons.play_arrow_rounded, size: 17),
                            label: const Text('Start'),
                            onPressed: () => projectsProvider.startProject(project, processProvider),
                          ),
                        )
                      else ...[
                        TactilePress(
                          onTap: () => projectsProvider.stopProject(project, processProvider),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                            icon: const Icon(Icons.stop_rounded, size: 17),
                            label: const Text('Stop'),
                            onPressed: () => projectsProvider.stopProject(project, processProvider),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Restart'),
                          onPressed: () => projectsProvider.restartProject(project, processProvider),
                        ),
                      ],
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: const Text('Open Browser'),
                        onPressed: () async {
                          final uri = Uri.parse(project.displayUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.terminal_rounded, size: 16),
                        label: const Text('Logs'),
                        onPressed: () {
                          appState.setTab(NavigationTab.runningProjects, projectId: project.id);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.public_rounded, size: 16),
                        label: const Text('Expose'),
                        onPressed: () {
                          appState.setTab(NavigationTab.tunnelManager, projectId: project.id);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More actions',
                  onSelected: (val) {
                    if (val == 'reinstall') {
                      projectsProvider.reinstallDependencies(project, processProvider);
                      appState.setTab(NavigationTab.runningProjects, projectId: project.id);
                    } else if (val == 'test') {
                      appState.setTab(NavigationTab.testingCenter, projectId: project.id);
                    } else if (val == 'delete') {
                      projectsProvider.deleteProject(project.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'reinstall',
                      child: Row(
                        children: [
                          Icon(Icons.download_for_offline_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Reinstall Dependencies'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'test',
                      child: Row(
                        children: [
                          Icon(Icons.fact_check, size: 18),
                          SizedBox(width: 8),
                          Text('Run Tests'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: AppTheme.errorRed, size: 18),
                          SizedBox(width: 8),
                          Text('Delete Project', style: TextStyle(color: AppTheme.errorRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

