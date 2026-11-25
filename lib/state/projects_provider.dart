import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/supported_technologies.dart';
import '../core/models/installation_plan.dart';
import '../core/models/process_status.dart';
import '../core/models/project.dart';
import '../core/models/test_result.dart';
import '../core/storage/database_helper.dart';
import '../core/utils/port_detector.dart';
import '../services/execution/process_manager.dart';
import '../services/github/github_service.dart';
import '../services/github/repo_analyzer.dart';
import '../services/runtime/dependency_installer.dart';
import '../services/testing/testing_engine.dart';
import 'process_provider.dart';

enum InstallFlowStage {
  idle,
  validating,
  fetching,
  cloning,
  analyzing,
  analysisReady,
  installing,
  launching,
  completed,
  failed,
}

class ProjectsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final ProcessManager _processManager = ProcessManager();

  List<Project> _projects = [];
  bool _isLoading = false;
  RepoAnalysisResult? _currentAnalysis;
  bool _isAnalyzing = false;
  bool _isInstalling = false;
  String? _analysisError;
  InstallFlowStage _installStage = InstallFlowStage.idle;
  String _installStageLabel = '';
  String _activeInstallUrl = '';
  String _activeProjectName = '';
  final List<LogEntry> _installLogs = [];
  TestSuiteReport? _lastTestReport;
  bool _isRunningTests = false;

  List<Project> get projects => _projects;
  bool get isLoading => _isLoading;
  RepoAnalysisResult? get currentAnalysis => _currentAnalysis;
  bool get isAnalyzing => _isAnalyzing;
  bool get isInstalling => _isInstalling;
  bool get isBusy => _isAnalyzing || _isInstalling;
  String? get analysisError => _analysisError;
  InstallFlowStage get installStage => _installStage;
  String get installStageLabel => _installStageLabel;
  String get activeInstallUrl => _activeInstallUrl;
  String get activeProjectName => _activeProjectName;
  List<LogEntry> get installLogs => List.unmodifiable(_installLogs);
  TestSuiteReport? get lastTestReport => _lastTestReport;
  bool get isRunningTests => _isRunningTests;

  void setActiveInstallUrl(String url) {
    _activeInstallUrl = url;
  }

  void setActiveProjectName(String name) {
    _activeProjectName = name;
  }

  void clearInstallLogs() {
    _installLogs.clear();
    notifyListeners();
  }

  void _emitInstallLog(
    String text,
    bool isError, [
    void Function(String output, bool isError)? externalLog,
  ]) {
    _installLogs.add(LogEntry(
      timestamp: DateTime.now(),
      text: text,
      isError: isError,
    ));
    externalLog?.call(text, isError);
    notifyListeners();
  }

  int get runningCount => _projects.where((p) => p.status == ProjectState.running).length;
  int get stoppedCount => _projects.where((p) => p.status != ProjectState.running).length;

  Future<void> loadProjects() async {
    _isLoading = true;
    notifyListeners();

    _projects = await _db.loadProjects();

    // Verify process states
    for (final p in _projects) {
      if (_processManager.isRunning(p.id)) {
        p.status = ProjectState.running;
      } else if (p.status == ProjectState.running) {
        p.status = ProjectState.ready;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<RepoAnalysisResult?> analyzeRepository(
    String url, {
    void Function(String output, bool isError)? onLog,
  }) async {
    _activeInstallUrl = url;
    _isAnalyzing = true;
    _analysisError = null;
    _currentAnalysis = null;
    _installLogs.clear();
    _installStage = InstallFlowStage.validating;
    _installStageLabel = 'Validating GitHub repository URL...';
    notifyListeners();

    try {
      _emitInstallLog('Validating GitHub repository URL...', false, onLog);
      if (!GitHubService.isValidGitHubUrl(url)) {
        throw Exception('Invalid GitHub URL. Expected https://github.com/owner/repo format');
      }

      _installStage = InstallFlowStage.fetching;
      _installStageLabel = 'Fetching repository metadata from GitHub...';
      _emitInstallLog('Fetching repository metadata from GitHub...', false, onLog);
      await GitHubService.fetchMetadata(url);

      _installStage = InstallFlowStage.cloning;
      _installStageLabel = 'Cloning / downloading repository...';
      _emitInstallLog('Cloning repository for local inspection...', false, onLog);
      final localPath = await GitHubService.cloneRepository(
        url,
        onProgress: (line, isErr) => _emitInstallLog(line, isErr, onLog),
      );

      _installStage = InstallFlowStage.analyzing;
      _installStageLabel = 'Analyzing files, tech stack & dependencies...';
      _emitInstallLog('Analyzing repository file structure and dependencies...', false, onLog);
      final analysis = await RepoAnalyzer.analyze(localPath);

      _currentAnalysis = analysis;
      _isAnalyzing = false;
      _installStage = InstallFlowStage.analysisReady;
      _installStageLabel = 'Analysis complete — ready to install & run';
      _emitInstallLog(
        '✓ Detected ${analysis.techStack.language.displayName} (${analysis.techStack.framework.displayName}). Ready to install!',
        false,
        onLog,
      );
      return analysis;
    } catch (e) {
      _analysisError = e.toString();
      _isAnalyzing = false;
      _installStage = InstallFlowStage.failed;
      _installStageLabel = 'Analysis failed';
      _emitInstallLog('Analysis error: $e', true, onLog);
      return null;
    }
  }

  Future<Project> installProject({
    required String name,
    required String githubUrl,
    required RepoAnalysisResult analysis,
    required ProcessProvider processProvider,
    required Future<bool> Function(InstallationStep step) requestApproval,
  }) async {
    _activeProjectName = name;
    _isInstalling = true;
    _installStage = InstallFlowStage.installing;
    _installStageLabel = 'Setting up runtimes & installing dependencies...';
    notifyListeners();

    final port = await PortDetector.findAvailablePort(
      startPort: analysis.techStack.recommendedPort,
    );

    final project = Project(
      id: const Uuid().v4(),
      name: name,
      githubUrl: githubUrl,
      localPath: analysis.repoPath,
      techStack: analysis.techStack,
      status: ProjectState.installing,
      port: port,
      localUrl: 'http://localhost:$port',
      databaseType: analysis.techStack.databaseRequirement,
      envVariables: analysis.suggestedEnv,
    );

    final plan = DependencyInstaller.generatePlan(project);
    project.installationPlan = plan;

    _projects.add(project);
    await _db.saveProject(project);
    notifyListeners();

    void logHandler(String line, bool isError) {
      processProvider.addLog(project.id, line, isError);
      _emitInstallLog(line, isError);
    }

    try {
      logHandler('Starting installation for ${project.name}...', false);

      final success = await DependencyInstaller.executeAllSteps(
        plan,
        project: project,
        onLine: logHandler,
        requestApproval: requestApproval,
        onStageUpdate: (label) {
          _installStageLabel = label;
          notifyListeners();
        },
      );

      if (success) {
        project.status = ProjectState.ready;
        _installStage = InstallFlowStage.launching;
        _installStageLabel = 'Dependencies installed — ready to launch';
        logHandler('✓ Installation completed successfully! Ready to run.', false);
      } else {
        project.status = ProjectState.error;
        project.lastError = 'Installation steps did not all succeed.';
        _installStage = InstallFlowStage.failed;
        _installStageLabel = 'Installation failed';
        logHandler('✗ Installation encountered errors.', true);
      }

      await _db.saveProject(project);
      return project;
    } catch (e) {
      project.status = ProjectState.error;
      project.lastError = e.toString();
      _installStage = InstallFlowStage.failed;
      _installStageLabel = 'Installation failed';
      logHandler('✗ Installation error: $e', true);
      await _db.saveProject(project);
      return project;
    } finally {
      _isInstalling = false;
      notifyListeners();
    }
  }

  void markInstallCompleted(String projectName) {
    _installStage = InstallFlowStage.completed;
    _installStageLabel = '$projectName is running!';
    notifyListeners();
  }

  void markInstallFailed(String message) {
    _installStage = InstallFlowStage.failed;
    _installStageLabel = message;
    notifyListeners();
  }

  Future<bool> startProject(
    Project project,
    ProcessProvider processProvider, {
    bool streamToInstallLogs = false,
  }) async {
    project.status = ProjectState.starting;
    notifyListeners();

    final started = await _processManager.startProject(
      project,
      onLog: (line, isError) {
        processProvider.addLog(project.id, line, isError);
        if (streamToInstallLogs) {
          _emitInstallLog(line, isError);
        }
      },
      onStatusChanged: (newStatus) async {
        project.status = newStatus;
        await _db.saveProject(project);
        notifyListeners();
      },
    );

    if (started && _processManager.isRunning(project.id)) {
      project.status = ProjectState.running;
      project.lastStartedAt = DateTime.now();
    } else if (!started) {
      project.status = ProjectState.error;
    }

    await _db.saveProject(project);
    notifyListeners();
    return started;
  }

  Future<void> stopProject(Project project, ProcessProvider processProvider) async {
    project.status = ProjectState.stopping;
    notifyListeners();

    await _processManager.stopProject(project.id);
    project.status = ProjectState.ready;
    processProvider.addLog(project.id, 'Project stopped by user.', false);

    await _db.saveProject(project);
    notifyListeners();
  }

  Future<void> restartProject(Project project, ProcessProvider processProvider) async {
    await stopProject(project, processProvider);
    await Future.delayed(const Duration(milliseconds: 600));
    await startProject(project, processProvider);
  }

  Future<bool> reinstallDependencies(Project project, ProcessProvider processProvider) async {
    processProvider.addLog(project.id, 'Installing project dependencies...', false);
    final success = await _processManager.reinstallDependencies(
      project,
      onLog: (line, isError) => processProvider.addLog(project.id, line, isError),
    );
    notifyListeners();
    return success;
  }

  Future<void> deleteProject(String projectId) async {
    await _processManager.stopProject(projectId);
    _projects.removeWhere((p) => p.id == projectId);
    await _db.deleteProject(projectId);
    notifyListeners();
  }

  Future<TestSuiteReport> runTests(Project project, ProcessProvider processProvider) async {
    _isRunningTests = true;
    notifyListeners();

    final report = await TestingEngine.runTests(
      project,
      onLog: (line, isError) => processProvider.addLog(project.id, '[TEST] $line', isError),
    );

    _lastTestReport = report;
    _isRunningTests = false;
    notifyListeners();
    return report;
  }

  Future<void> updateProjectEnv(Project project, Map<String, String> newEnv) async {
    project.envVariables = newEnv;
    await _db.saveProject(project);
    notifyListeners();
  }

  Project? getProjectById(String? id) {
    if (id == null) return null;
    return _projects.cast<Project?>().firstWhere(
      (p) => p?.id == id,
      orElse: () => null,
    );
  }
}

