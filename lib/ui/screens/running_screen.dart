import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/models/process_status.dart';
import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/process_provider.dart';
import '../../state/projects_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/tactile_press.dart';
import '../widgets/terminal_view.dart';

class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key});

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  String? _selectedProjectId;
  String? _lastAppSelectedId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final projectsProvider = context.watch<ProjectsProvider>();
    final processProvider = context.watch<ProcessProvider>();

    final allProjects = projectsProvider.projects;

    if (appState.selectedProjectId != null && appState.selectedProjectId != _lastAppSelectedId) {
      _lastAppSelectedId = appState.selectedProjectId;
      _selectedProjectId = appState.selectedProjectId;
    }
    if ((_selectedProjectId == null || projectsProvider.getProjectById(_selectedProjectId) == null) &&
        allProjects.isNotEmpty) {
      _selectedProjectId = appState.selectedProjectId ?? allProjects.first.id;
    }

    final currentProject = projectsProvider.getProjectById(_selectedProjectId);
    final isRunning = currentProject?.status == ProjectState.running;
    final List<LogEntry> currentLogs = _selectedProjectId != null
        ? processProvider.getLogsForProject(_selectedProjectId!)
        : <LogEntry>[];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Process Manager & Live Console',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${projectsProvider.runningCount} running • ${projectsProvider.projects.length} total projects managed',
                        style: AppTheme.tabularNumberStyle.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (currentProject != null) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (!isRunning) ...[
                          TactilePress(
                            onTap: () => projectsProvider.startProject(currentProject, processProvider),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                              icon: const Icon(Icons.play_arrow, size: 16),
                              label: const Text('Start Project'),
                              onPressed: () => projectsProvider.startProject(currentProject, processProvider),
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                            label: const Text('Install Dependencies'),
                            onPressed: () => projectsProvider.reinstallDependencies(currentProject, processProvider),
                          ),
                        ] else ...[
                          TactilePress(
                            onTap: () => projectsProvider.stopProject(currentProject, processProvider),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                              icon: const Icon(Icons.stop, size: 16),
                              label: const Text('Stop Project'),
                              onPressed: () => projectsProvider.stopProject(currentProject, processProvider),
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Restart'),
                            onPressed: () => projectsProvider.restartProject(currentProject, processProvider),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                            label: const Text('Reinstall Deps'),
                            onPressed: () => projectsProvider.reinstallDependencies(currentProject, processProvider),
                          ),
                          TactilePress(
                            onTap: () async {
                              final uri = Uri.parse(currentProject.displayUrl);
                              if (await canLaunchUrl(uri)) await launchUrl(uri);
                            },
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_browser, size: 16),
                              label: Text('Open ${currentProject.displayUrl}'),
                              onPressed: () async {
                                final uri = Uri.parse(currentProject.displayUrl);
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 18),

            if (allProjects.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_off_outlined, size: 54, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No Projects Installed',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Install a project from GitHub to manage and run processes locally.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => appState.setTab(NavigationTab.installNew),
                        child: const Text('Install New Project'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Project Selector Chips
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: allProjects.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final p = allProjects[index];
                    final isSel = p.id == _selectedProjectId;
                    final active = p.status == ProjectState.running;
                    return ChoiceChip(
                      selected: isSel,
                      avatar: active
                          ? const Center(
                              child: PulsingLiveDot(color: AppTheme.successGreen, size: 7),
                            )
                          : const Icon(
                              Icons.stop_circle_outlined,
                              color: Colors.grey,
                              size: 14,
                            ),
                      label: Text(
                        '${p.name} (Port ${p.port})',
                        style: AppTheme.tabularNumberStyle.copyWith(fontSize: 12.5),
                      ),
                      onSelected: (_) => setState(() => _selectedProjectId = p.id),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              if (currentProject != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Text(
                        currentProject.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(width: 12),
                      StatusBadge(status: currentProject.status),
                      const SizedBox(width: 16),
                      Text(
                        'Local: ${currentProject.displayUrl}',
                        style: AppTheme.tabularNumberStyle.copyWith(
                          color: AppTheme.accentCyan,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Tooltip(
                          message: currentProject.localPath,
                          child: Text(
                            'Path: ${currentProject.localPath}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (currentProject != null &&
                  currentProject.status == ProjectState.error &&
                  currentProject.lastError != null &&
                  currentProject.lastError!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          currentProject.lastError!,
                          style: const TextStyle(color: AppTheme.errorRed, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              Expanded(
                child: TerminalView(
                  title: 'Process Output - ${currentProject?.name ?? "Terminal"}',
                  logs: currentLogs,
                  onClear: () {
                    if (_selectedProjectId != null) {
                      processProvider.clearLogs(_selectedProjectId!);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
