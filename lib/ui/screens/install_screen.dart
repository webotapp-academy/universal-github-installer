import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/models/installation_plan.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';
import '../../services/github/github_service.dart';
import '../../services/github/repo_analyzer.dart';
import '../../state/app_state.dart';
import '../../state/process_provider.dart';
import '../../state/projects_provider.dart';
import '../../state/runtime_provider.dart';
import '../widgets/command_approval_dialog.dart';
import '../widgets/terminal_view.dart';

class InstallScreen extends StatefulWidget {
  const InstallScreen({super.key});

  @override
  State<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends State<InstallScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final projectsProvider = context.read<ProjectsProvider>();
    if (projectsProvider.activeInstallUrl.isNotEmpty) {
      _urlController.text = projectsProvider.activeInstallUrl;
    }
    if (projectsProvider.activeProjectName.isNotEmpty) {
      _nameController.text = projectsProvider.activeProjectName;
    } else if (projectsProvider.currentAnalysis != null) {
      final parsed = GitHubService.parseUrl(projectsProvider.activeInstallUrl);
      if (parsed != null) {
        _nameController.text = parsed.repo;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    if (appState.pendingInstallUrl != null) {
      final url = appState.pendingInstallUrl!;
      appState.clearPendingInstallUrl();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _urlController.text = url;
          final parsed = GitHubService.parseUrl(url);
          if (parsed != null) {
            _nameController.text = parsed.repo;
            context.read<ProjectsProvider>().setActiveProjectName(parsed.repo);
          }
          _startAnalysis();
        }
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final projectsProvider = context.read<ProjectsProvider>();
    if (projectsProvider.isBusy) return;

    final parsed = GitHubService.parseUrl(url);
    if (parsed != null && _nameController.text.isEmpty) {
      _nameController.text = parsed.repo;
      projectsProvider.setActiveProjectName(parsed.repo);
    }

    await projectsProvider.analyzeRepository(url);
  }

  Future<void> _runInstallation(RepoAnalysisResult analysis) async {
    final projectsProvider = context.read<ProjectsProvider>();
    if (projectsProvider.isBusy) return;

    final processProvider = context.read<ProcessProvider>();
    final runtimeProvider = context.read<RuntimeProvider>();
    final appState = context.read<AppState>();

    final projectName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Project-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final project = await projectsProvider.installProject(
        name: projectName,
        githubUrl: _urlController.text.trim(),
        analysis: analysis,
        processProvider: processProvider,
        requestApproval: (InstallationStep step) async {
          final dialogCtx = appNavigatorKey.currentContext ?? (mounted ? context : null);
          if (dialogCtx == null) return false;
          return await showDialog<bool>(
                context: dialogCtx,
                barrierDismissible: false,
                builder: (ctx) => CommandApprovalDialog(step: step),
              ) ??
              false;
        },
      );

      // Refresh detected runtimes in case portable binaries were bootstrapped
      runtimeProvider.refresh();

      if (project.status != ProjectState.ready) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.errorRed,
              content: Text('Installation failed. See terminal output for details.'),
            ),
          );
        }
        return;
      }

      final started = await projectsProvider.startProject(
        project,
        processProvider,
        streamToInstallLogs: true,
      );
      if (started) {
        projectsProvider.markInstallCompleted(project.name);
      } else {
        projectsProvider.markInstallFailed(
          project.lastError ?? 'Installed, but server failed to bind port ${project.port}',
        );
      }

      if (mounted) {
        if (started) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.successGreen,
              content: Text('✓ ${project.name} installed and listening on port ${project.port}!'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.errorRed,
              content: Text(
                '${project.name} installed, but failed to start on port ${project.port}. Check live console logs.',
              ),
            ),
          );
        }
        appState.setTab(NavigationTab.runningProjects, projectId: project.id);
      }
    } catch (e) {
      projectsProvider.markInstallFailed('Installation error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsProvider = context.watch<ProjectsProvider>();
    final analysis = projectsProvider.currentAnalysis;
    final isAnalyzing = projectsProvider.isAnalyzing;
    final isInstalling = projectsProvider.isInstalling;
    final isBusy = projectsProvider.isBusy;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Install New GitHub Project',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter any public or private GitHub repository to automatically detect framework, dependencies, and launch locally.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),

            const SizedBox(height: 24),

            // URL input & actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GitHub Repository URL',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            enabled: !isBusy,
                            onChanged: projectsProvider.setActiveInstallUrl,
                            decoration: const InputDecoration(
                              hintText: 'https://github.com/username/project-name',
                              prefixIcon: Icon(Icons.link),
                            ),
                            onSubmitted: (_) => _startAnalysis(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton.icon(
                          icon: isAnalyzing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.analytics_outlined),
                          label: Text(isAnalyzing ? 'Analyzing...' : 'Analyze Repository'),
                          onPressed: isBusy ? null : _startAnalysis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.code, size: 14),
                          label: const Text('Try Laravel Demo'),
                          onPressed: isBusy
                              ? null
                              : () {
                                  _urlController.text = 'https://github.com/laravel/laravel';
                                  _startAnalysis();
                                },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.javascript, size: 14),
                          label: const Text('Try Next.js Demo'),
                          onPressed: isBusy
                              ? null
                              : () {
                                  _urlController.text = 'https://github.com/vercel/next-learn';
                                  _startAnalysis();
                                },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.terminal, size: 14),
                          label: const Text('Try FastAPI Demo'),
                          onPressed: isBusy
                              ? null
                              : () {
                                  _urlController.text = 'https://github.com/tiangolo/fastapi';
                                  _startAnalysis();
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (projectsProvider.analysisError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.errorRed),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorRed),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        projectsProvider.analysisError!,
                        style: const TextStyle(color: AppTheme.errorRed),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Analysis Results Display
            if (analysis != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Repository Analysis & Execution Plan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Project Name field
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              enabled: !isInstalling,
                              onChanged: projectsProvider.setActiveProjectName,
                              decoration: const InputDecoration(
                                labelText: 'Project Display Name',
                                prefixIcon: Icon(Icons.title),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                            ),
                            icon: isInstalling
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.rocket_launch),
                            label: Text(
                              isInstalling ? 'Installing...' : 'Install & Run',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            onPressed: isBusy ? null : () => _runInstallation(analysis),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Tech Spec Grid
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailTile(
                              title: 'Language',
                              value: analysis.techStack.language.displayName,
                              icon: Icons.code,
                            ),
                          ),
                          Expanded(
                            child: _detailTile(
                              title: 'Framework',
                              value: analysis.techStack.framework.displayName,
                              icon: Icons.layers,
                            ),
                          ),
                          Expanded(
                            child: _detailTile(
                              title: 'Database Requirement',
                              value: analysis.techStack.databaseRequirement.displayName,
                              icon: Icons.storage,
                            ),
                          ),
                          Expanded(
                            child: _detailTile(
                              title: 'Target Port',
                              value: '${analysis.techStack.recommendedPort}',
                              icon: Icons.numbers,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      if (analysis.techStack.dependencyFiles.isNotEmpty) ...[
                        Text(
                          'Dependency Files: ${analysis.techStack.dependencyFiles.join(", ")}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (analysis.techStack.detectedTestFrameworks.isNotEmpty) ...[
                        Text(
                          'Detected Test Suites: ${analysis.techStack.detectedTestFrameworks.join(", ")}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (analysis.readmeSummary.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'README Excerpt:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            analysis.readmeSummary,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            if (projectsProvider.installStage != InstallFlowStage.idle ||
                projectsProvider.installLogs.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildProgressCard(projectsProvider),
            ],

            const SizedBox(height: 16),

            // Live Analysis/Install Terminal
            SizedBox(
              height: 280,
              child: TerminalView(
                title: isBusy
                    ? 'Installation Output & Live Logs (Running...)'
                    : 'Installation Output & Live Logs',
                logs: projectsProvider.installLogs,
                onClear: isBusy ? null : projectsProvider.clearInstallLogs,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(ProjectsProvider provider) {
    final stage = provider.installStage;
    final isFailed = stage == InstallFlowStage.failed;
    final isDone = stage == InstallFlowStage.completed;

    final steps = [
      ('Fetch', InstallFlowStage.fetching),
      ('Clone', InstallFlowStage.cloning),
      ('Analyze', InstallFlowStage.analyzing),
      ('Install', InstallFlowStage.installing),
      ('Launch', InstallFlowStage.launching),
    ];

    int activeIdx = switch (stage) {
      InstallFlowStage.validating || InstallFlowStage.fetching => 0,
      InstallFlowStage.cloning => 1,
      InstallFlowStage.analyzing => 2,
      InstallFlowStage.analysisReady => 3,
      InstallFlowStage.installing => 3,
      InstallFlowStage.launching => 4,
      InstallFlowStage.completed => 5,
      _ => -1,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (provider.isBusy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isFailed
                        ? Icons.error_outline
                        : (isDone ? Icons.check_circle : Icons.info_outline),
                    size: 18,
                    color: isFailed
                        ? AppTheme.errorRed
                        : (isDone ? AppTheme.successGreen : AppTheme.accentCyan),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider.installStageLabel.isNotEmpty
                        ? provider.installStageLabel
                        : 'Ready',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: isFailed ? AppTheme.errorRed : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: provider.isBusy
                    ? null
                    : (isDone ? 1.0 : (activeIdx > 0 ? activeIdx / 5.0 : 0.0)),
                minHeight: 5,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isFailed
                      ? AppTheme.errorRed
                      : (isDone ? AppTheme.successGreen : AppTheme.accentCyan),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  Expanded(
                    child: _stagePill(
                      index: i + 1,
                      label: steps[i].$1,
                      isCompleted: !isFailed && (activeIdx > i || isDone),
                      isActive: provider.isBusy && activeIdx == i,
                      isFailed: isFailed && activeIdx == i,
                    ),
                  ),
                  if (i < steps.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stagePill({
    required int index,
    required String label,
    required bool isCompleted,
    required bool isActive,
    required bool isFailed,
  }) {
    final Color color = isFailed
        ? AppTheme.errorRed
        : isCompleted
            ? AppTheme.successGreen
            : isActive
                ? AppTheme.accentCyan
                : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFailed
                ? Icons.close
                : isCompleted
                    ? Icons.check_circle
                    : isActive
                        ? Icons.sync
                        : Icons.radio_button_unchecked,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$index. $label',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive || isCompleted ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile({required String title, required String value, required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.accentCyan),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}

