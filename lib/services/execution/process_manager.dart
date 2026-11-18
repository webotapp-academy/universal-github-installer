import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/models/process_status.dart';
import '../../core/models/project.dart';
import '../../core/utils/command_runner.dart';
import '../../core/utils/port_detector.dart';
import '../database/database_manager.dart';
import '../runtime/dependency_installer.dart';

class ProcessManager {
  static final ProcessManager _instance = ProcessManager._internal();
  factory ProcessManager() => _instance;
  ProcessManager._internal();

  final Map<String, Process> _runningProcesses = {};
  final Map<String, Process> _companionProcesses = {};
  final Map<String, ProjectProcessInfo> _processInfos = {};
  final Map<String, StreamController<LogEntry>> _logControllers = {};

  Stream<LogEntry>? getLogStream(String projectId) {
    return _logControllers[projectId]?.stream;
  }

  List<LogEntry> getLogs(String projectId) {
    return _processInfos[projectId]?.logs ?? [];
  }

  bool isRunning(String projectId) {
    return _runningProcesses.containsKey(projectId);
  }

  ProjectProcessInfo? getProcessInfo(String projectId) {
    return _processInfos[projectId];
  }

  Future<bool> _openBrowserForProject(
    Project project,
    void Function(String line, bool isError) logHandler,
  ) async {
    try {
      final uri = Uri.parse(project.displayUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        logHandler('🚀 Application is live! Automatically opened ${project.displayUrl} in your default browser.', false);
        return true;
      } else {
        logHandler('Note: You can open the project in your browser at: ${project.displayUrl}', false);
        return false;
      }
    } catch (e) {
      logHandler('Note: Browser opener: $e. You can access it at: ${project.displayUrl}', false);
      return false;
    }
  }

  Future<bool> _ensureDependenciesInstalled(
    Project project,
    void Function(String line, bool isError) logHandler, {
    bool force = false,
  }) async {
    final localPath = project.localPath;
    if (!Directory(localPath).existsSync()) return true;

    // 1. Node.js dependencies check
    final packageJson = File(p.join(localPath, 'package.json'));
    if (packageJson.existsSync()) {
      final nodeModules = Directory(p.join(localPath, 'node_modules'));
      final binDir = Directory(p.join(localPath, 'node_modules', '.bin'));
      bool needsInstall = force || !nodeModules.existsSync() || !binDir.existsSync();

      if (!needsInstall) {
        try {
          if (nodeModules.listSync().isEmpty || binDir.listSync().isEmpty) {
            needsInstall = true;
          }
        } catch (_) {
          needsInstall = true;
        }
      }

      // Check if specific scripts require binaries (like vite, next, nuxt)
      if (!needsInstall) {
        try {
          final pkgContent = packageJson.readAsStringSync();
          final pkgJson = jsonDecode(pkgContent) as Map<String, dynamic>;
          final scripts = (pkgJson['scripts'] as Map?) ?? {};
          final devScript = scripts['dev']?.toString() ?? '';
          final startScript = scripts['start']?.toString() ?? '';

          if (devScript.contains('vite') || startScript.contains('vite')) {
            final viteBin = File(p.join(localPath, 'node_modules', '.bin', 'vite'));
            final viteWin = File(p.join(localPath, 'node_modules', '.bin', 'vite.cmd'));
            if (!viteBin.existsSync() && !viteWin.existsSync()) {
              needsInstall = true;
              logHandler('🔍 Detected "vite" in package.json scripts, but node_modules/.bin/vite does not exist.', false);
            }
          }
          if (devScript.contains('next') || startScript.contains('next')) {
            final nextBin = File(p.join(localPath, 'node_modules', '.bin', 'next'));
            final nextWin = File(p.join(localPath, 'node_modules', '.bin', 'next.cmd'));
            if (!nextBin.existsSync() && !nextWin.existsSync()) {
              needsInstall = true;
              logHandler('🔍 Detected "next" in package.json scripts, but node_modules/.bin/next does not exist.', false);
            }
          }
        } catch (_) {}
      }

      if (needsInstall) {
        final pkgMgr = project.techStack.packageManager ?? 'npm';
        logHandler('📦 Dependencies missing or incomplete in node_modules.', false);
        logHandler('>>> Executing automated dependency installation: $pkgMgr install...', false);
        final res = await CommandRunner.run(
          pkgMgr,
          ['install'],
          workingDirectory: localPath,
          onLine: logHandler,
        );
        if (!res.isSuccess) {
          logHandler('⚠️ Warning: "$pkgMgr install" exited with code ${res.exitCode}. Output:\n${res.stderr}', true);
        } else {
          logHandler('✓ Dependencies installed successfully.', false);
        }
      }
    }

    // 2. Python dependencies check
    final reqTxt = File(p.join(localPath, 'requirements.txt'));
    final pyProj = File(p.join(localPath, 'pyproject.toml'));
    if (reqTxt.existsSync() || pyProj.existsSync()) {
      final venvDir = Directory(p.join(localPath, '.venv'));
      if (force || !venvDir.existsSync()) {
        logHandler('📦 Python virtual environment not found. Creating .venv...', false);
        final pyCmd = Platform.isWindows ? 'python' : 'python3';
        await CommandRunner.run(pyCmd, ['-m', 'venv', '.venv'], workingDirectory: localPath, onLine: logHandler);
        final venvPip = Platform.isWindows
            ? p.join(localPath, '.venv', 'Scripts', 'pip.exe')
            : p.join(localPath, '.venv', 'bin', 'pip');
        if (reqTxt.existsSync()) {
          logHandler('Installing Python dependencies from requirements.txt...', false);
          await CommandRunner.run(venvPip, ['install', '-r', 'requirements.txt'], workingDirectory: localPath, onLine: logHandler);
        } else if (pyProj.existsSync()) {
          logHandler('Installing Python package dependencies...', false);
          await CommandRunner.run(venvPip, ['install', '.'], workingDirectory: localPath, onLine: logHandler);
        }
        logHandler('✓ Python environment configured.', false);
      }
    }

    // 3. PHP / Composer dependencies check
    final composerJson = File(p.join(localPath, 'composer.json'));
    if (composerJson.existsSync()) {
      final vendorDir = Directory(p.join(localPath, 'vendor'));
      if (force || !vendorDir.existsSync()) {
        logHandler('📦 Composer vendor folder not found. Running "composer install"...', false);
        await CommandRunner.run(
          'composer',
          ['install', '--no-interaction', '--prefer-dist'],
          workingDirectory: localPath,
          onLine: logHandler,
        );
        logHandler('✓ Composer dependencies installed.', false);
      }
    }

    return true;
  }

  Future<bool> reinstallDependencies(
    Project project, {
    void Function(String line, bool isError)? onLog,
  }) async {
    final localPath = project.localPath;
    final log = onLog ?? (line, isError) {};

    log('Starting clean dependency installation for ${project.name}...', false);

    final packageJson = File(p.join(localPath, 'package.json'));
    if (packageJson.existsSync()) {
      final pkgMgr = project.techStack.packageManager ?? 'npm';
      log('Executing: $pkgMgr install in $localPath', false);
      final res = await CommandRunner.run(
        pkgMgr,
        ['install'],
        workingDirectory: localPath,
        onLine: log,
      );
      if (res.isSuccess) {
        log('✓ Node dependencies installed successfully.', false);
      } else {
        log('✗ Dependency installation failed: ${res.stderr}', true);
      }
      return res.isSuccess;
    }

    final reqTxt = File(p.join(localPath, 'requirements.txt'));
    if (reqTxt.existsSync()) {
      final venvPip = Platform.isWindows
          ? p.join(localPath, '.venv', 'Scripts', 'pip.exe')
          : p.join(localPath, '.venv', 'bin', 'pip');
      log('Executing: $venvPip install -r requirements.txt', false);
      final res = await CommandRunner.run(
        venvPip,
        ['install', '-r', 'requirements.txt'],
        workingDirectory: localPath,
        onLine: log,
      );
      return res.isSuccess;
    }

    final composerJson = File(p.join(localPath, 'composer.json'));
    if (composerJson.existsSync()) {
      log('Executing: composer install in $localPath', false);
      final res = await CommandRunner.run(
        'composer',
        ['install', '--no-interaction', '--prefer-dist'],
        workingDirectory: localPath,
        onLine: log,
      );
      return res.isSuccess;
    }

    log('No package.json, requirements.txt, or composer.json found in project directory.', false);
    return true;
  }

  Future<bool> startProject(
    Project project, {
    void Function(String line, bool isError)? onLog,
    bool autoOpenBrowser = true,
  }) async {
    final projectId = project.id;
    if (_runningProcesses.containsKey(projectId)) {
      onLog?.call('Project is already running.', false);
      return true;
    }

    final plan = project.installationPlan;
    if (plan == null) {
      onLog?.call('Error: Project has no installation or start plan configured.', true);
      return false;
    }

    // Check if the assigned port is occupied by another process
    final inUse = await PortDetector.isPortInUse(project.port);
    if (inUse) {
      // Find a new available port
      final newPort = await PortDetector.findAvailablePort(startPort: project.port + 1);
      project.port = newPort;
      project.localUrl = 'http://localhost:$newPort';
      onLog?.call('Note: Original port was in use. Assigned new port: $newPort', false);
    }

    _logControllers.putIfAbsent(projectId, () => StreamController<LogEntry>.broadcast());

    void logHandler(String line, bool isError) {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        text: line,
        isError: isError,
      );
      _processInfos[projectId]?.logs.add(entry);
      _logControllers[projectId]?.add(entry);
      onLog?.call(line, isError);
    }

    // Verify dependencies before starting
    await _ensureDependenciesInstalled(project, logHandler);

    final isLaravel = File(p.join(project.localPath, 'artisan')).existsSync();

    // Auto-detect and fix Laravel configuration
    String startExecutable = plan.startCommand;
    List<String> startArgs = List<String>.from(plan.startArgs);

    if (isLaravel) {
      if (project.port == 5173 || plan.startCommand == 'npm') {
        final newPort = await PortDetector.findAvailablePort(startPort: 8000);
        project.port = newPort;
        project.localUrl = 'http://localhost:$newPort';
      }

      startExecutable = 'php';
      startArgs = ['artisan', 'serve', '--host=127.0.0.1', '--port=${project.port}'];

      // Guarantee .env and valid APP_KEY encryption key
      DependencyInstaller.ensureEnvAndKey(project.localPath, port: project.port, onLine: logHandler);
      await CommandRunner.run('php', ['artisan', 'config:clear'], workingDirectory: project.localPath, onLine: logHandler);
      await CommandRunner.run('php', ['artisan', 'key:generate', '--force'], workingDirectory: project.localPath, onLine: logHandler);

      // Verify database exists and run migrations if needed
      final envFile = File(p.join(project.localPath, '.env'));
      if (envFile.existsSync()) {
        try {
          final content = envFile.readAsStringSync();
          final dbConnMatch = RegExp(r'^DB_CONNECTION=(.*)$', multiLine: true).firstMatch(content);
          final dbConn = dbConnMatch?.group(1)?.trim();
          final dbNameMatch = RegExp(r'^DB_DATABASE=(.*)$', multiLine: true).firstMatch(content);
          final dbName = dbNameMatch?.group(1)?.trim();

          if (dbConn == 'mysql' && dbName != null && dbName.isNotEmpty) {
            var isMysqlRunning = await DatabaseManager.testConnection(type: DatabaseType.mysql, port: 3306);
            if (!isMysqlRunning) {
              logHandler('ℹ️ MySQL daemon is not running on 127.0.0.1:3306. Attempting automated startup...', false);
              isMysqlRunning = await DatabaseManager.startDatabaseService(DatabaseType.mysql, onLine: logHandler);
            }

            if (isMysqlRunning) {
              final dbReady = await DatabaseManager.ensureDatabaseExists(
                databaseName: dbName,
                onLine: logHandler,
              );
              if (dbReady) {
                await CommandRunner.run('php', ['artisan', 'migrate', '--force'], workingDirectory: project.localPath, onLine: logHandler);
                final seeder = File(p.join(project.localPath, 'database', 'seeders', 'DatabaseSeeder.php'));
                final legacySeeder = File(p.join(project.localPath, 'database', 'seeds', 'DatabaseSeeder.php'));
                if (seeder.existsSync() || legacySeeder.existsSync()) {
                  await CommandRunner.run('php', ['artisan', 'db:seed', '--force'], workingDirectory: project.localPath, onLine: logHandler);
                }
              }
            } else {
              logHandler('⚠️ MySQL daemon unavailable. Falling back to SQLite database...', false);
              final sqlitePath = p.join(project.localPath, 'database', 'database.sqlite');
              final sqliteFile = File(sqlitePath);
              if (!sqliteFile.existsSync()) {
                sqliteFile.parent.createSync(recursive: true);
                sqliteFile.createSync();
              }
              // Update .env with SQLite config
              var updatedContent = content
                  .replaceAll(RegExp(r'^DB_CONNECTION=.*$', multiLine: true), 'DB_CONNECTION=sqlite')
                  .replaceAll(RegExp(r'^DB_DATABASE=.*$', multiLine: true), 'DB_DATABASE=$sqlitePath');
              envFile.writeAsStringSync(updatedContent);
              await CommandRunner.run('php', ['artisan', 'config:clear'], workingDirectory: project.localPath, onLine: logHandler);
              await CommandRunner.run('php', ['artisan', 'migrate', '--force'], workingDirectory: project.localPath, onLine: logHandler);
              final seeder = File(p.join(project.localPath, 'database', 'seeders', 'DatabaseSeeder.php'));
              final legacySeeder = File(p.join(project.localPath, 'database', 'seeds', 'DatabaseSeeder.php'));
              if (seeder.existsSync() || legacySeeder.existsSync()) {
                await CommandRunner.run('php', ['artisan', 'db:seed', '--force'], workingDirectory: project.localPath, onLine: logHandler);
              }
            }
          } else if (dbConn == 'sqlite' || dbConn == null || dbConn.isEmpty) {
            final sqliteFile = File(p.join(project.localPath, 'database', 'database.sqlite'));
            if (sqliteFile.existsSync() && sqliteFile.lengthSync() == 0) {
              await CommandRunner.run('php', ['artisan', 'migrate', '--force'], workingDirectory: project.localPath, onLine: logHandler);
              final seeder = File(p.join(project.localPath, 'database', 'seeders', 'DatabaseSeeder.php'));
              final legacySeeder = File(p.join(project.localPath, 'database', 'seeds', 'DatabaseSeeder.php'));
              if (seeder.existsSync() || legacySeeder.existsSync()) {
                await CommandRunner.run('php', ['artisan', 'db:seed', '--force'], workingDirectory: project.localPath, onLine: logHandler);
              }
            }
          }
        } catch (_) {}
      }

      // Ensure SQLite DB file exists if database directory exists
      final sqliteFile = File(p.join(project.localPath, 'database', 'database.sqlite'));
      final dbDir = Directory(p.join(project.localPath, 'database'));
      if (dbDir.existsSync() && !sqliteFile.existsSync()) {
        try {
          sqliteFile.createSync(recursive: true);
        } catch (_) {}
      }

      // Ensure frontend assets are built so Laravel serves full UI
      final packageJson = File(p.join(project.localPath, 'package.json'));
      final publicBuild = Directory(p.join(project.localPath, 'public', 'build'));
      if (packageJson.existsSync() && !publicBuild.existsSync()) {
        logHandler('🔨 Compiling frontend assets (npm run build)...', false);
        await CommandRunner.run('npm', ['run', 'build'], workingDirectory: project.localPath, onLine: logHandler);
      }

      // Start Vite dev server as a companion process if dev script exists
      if (packageJson.existsSync() && !_companionProcesses.containsKey(projectId)) {
        try {
          final pkgContent = packageJson.readAsStringSync();
          final pkgJson = jsonDecode(pkgContent) as Map<String, dynamic>;
          final scripts = (pkgJson['scripts'] as Map?) ?? {};
          if (scripts.containsKey('dev')) {
            logHandler('⚡ Starting Vite companion dev server for live asset compilation...', false);
            final viteProc = await CommandRunner.startStreaming(
              'npm',
              ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '5173'],
              workingDirectory: project.localPath,
              onLine: (line, isErr) => logHandler('[Vite] $line', isErr),
            );
            _companionProcesses[projectId] = viteProc;
          }
        } catch (_) {}
      }
    } else if (project.techStack.framework == FrameworkType.vite && !startArgs.contains('--host')) {
      final dashDashIdx = startArgs.indexOf('--');
      if (dashDashIdx >= 0) {
        startArgs.insert(dashDashIdx + 1, '--host');
        startArgs.insert(dashDashIdx + 2, '127.0.0.1');
      } else {
        startArgs.addAll(['--', '--host', '127.0.0.1']);
      }
    }

    logHandler('Starting ${project.name} on port ${project.port}...', false);
    logHandler('Command: $startExecutable ${startArgs.join(" ")}', false);

    bool browserOpened = false;
    bool hasAutoRepaired = false;
    bool encounteredCommandNotFound = false;

    void processLineHandler(String line, bool isError) {
      logHandler(line, isError);

      // Check for missing command error patterns
      if (line.contains('command not found') ||
          line.contains('sh: vite:') ||
          line.contains('No such file or directory') ||
          line.contains('Cannot find module')) {
        encounteredCommandNotFound = true;
      }

      // Dynamically detect server bound port from terminal output
      // e.g. "Local: http://localhost:5173/" or "http://127.0.0.1:8000"
      if (autoOpenBrowser && !browserOpened) {
        final urlMatch = RegExp(r'https?:\/\/(?:localhost|127\.0\.0\.1):(\d+)').firstMatch(line);
        if (urlMatch != null) {
          final detectedPort = int.tryParse(urlMatch.group(1) ?? '');
          if (detectedPort != null) {
            // For Laravel, ignore port 5173 (that is just Vite asset compiler)
            if (isLaravel && detectedPort == 5173) {
              // Wait for Laravel server on port 8000
            } else {
              if (detectedPort != project.port) {
                project.port = detectedPort;
                project.localUrl = 'http://localhost:$detectedPort';
                logHandler('Detected server running on port $detectedPort. Updated project URL.', false);
              }
              browserOpened = true;
              _openBrowserForProject(project, logHandler);
            }
          }
        }
      }
    }

    try {
      final env = <String, String>{
        ...project.envVariables,
        'PORT': project.port.toString(),
      };

      if (isLaravel) {
        final envFile = File(p.join(project.localPath, '.env'));
        if (envFile.existsSync()) {
          final content = envFile.readAsStringSync();
          final keyMatch = RegExp(r'^APP_KEY=(.+)$', multiLine: true).firstMatch(content);
          final raw = keyMatch?.group(1);
          if (raw != null) {
            final key = raw.replaceAll('"', '').replaceAll("'", '').trim();
            if (key.isNotEmpty) {
              env['APP_KEY'] = key;
            }
          }
        }
      }

      final process = await CommandRunner.startStreaming(
        startExecutable,
        startArgs,
        workingDirectory: project.localPath,
        environment: env,
        onLine: (line, isError) => processLineHandler(line, isError),
      );

      _runningProcesses[projectId] = process;
      _processInfos[projectId] = ProjectProcessInfo(
        projectId: projectId,
        pid: process.pid,
        startedAt: DateTime.now(),
        port: project.port,
      );

      project.status = ProjectState.running;
      project.lastStartedAt = DateTime.now();

      // Listen for process exit or crash
      process.exitCode.then((code) async {
        logHandler('Process exited with code $code', code != 0);
        _runningProcesses.remove(projectId);
        _processInfos.remove(projectId);

        if (code != 0) {
          project.status = ProjectState.error;

          // AUTOMATIC SELF-HEALING REPAIR
          if (!hasAutoRepaired && (code == 127 || encounteredCommandNotFound)) {
            hasAutoRepaired = true;
            logHandler('⚠️ Self-Healing Triggered: Command execution error detected (Exit code $code).', true);
            logHandler('🔧 Applying automatic fix: Executing clean package installation...', false);
            final installSuccess = await reinstallDependencies(project, onLog: logHandler);
            if (installSuccess) {
              logHandler('✓ Fix applied successfully. Restarting ${project.name} now...', false);
              await startProject(project, onLog: onLog, autoOpenBrowser: autoOpenBrowser);
            } else {
              logHandler('❌ Automatic repair could not resolve dependencies. Please check package.json.', true);
            }
          }
        } else {
          project.status = ProjectState.ready;
        }
      });

      // Poll port & verify health
      final portBound = await PortDetector.waitForPort(project.port, timeout: const Duration(seconds: 12));
      if (portBound) {
        logHandler('✓ Application is healthy and listening on http://localhost:${project.port}', false);
        _processInfos[projectId]?.isHealthy = true;

        if (autoOpenBrowser && !browserOpened) {
          browserOpened = true;
          await _openBrowserForProject(project, logHandler);
        }
      } else {
        // Server did NOT respond within 12 seconds
        logHandler('⚠️ Server did not bind to port ${project.port} within 12 seconds.', true);
        if (!hasAutoRepaired && isRunning(projectId)) {
          hasAutoRepaired = true;
          logHandler('🔧 Checking if another port was chosen or port is busy...', false);
          final newPort = await PortDetector.findAvailablePort(startPort: project.port + 1);
          if (newPort != project.port) {
            logHandler('Switching to free port $newPort and restarting application...', false);
            project.port = newPort;
            project.localUrl = 'http://localhost:$newPort';
            await stopProject(projectId);
            await Future.delayed(const Duration(milliseconds: 500));
            await startProject(project, onLog: onLog, autoOpenBrowser: autoOpenBrowser);
          }
        }
      }

      return true;
    } catch (e) {
      logHandler('Failed to start application: $e', true);
      project.status = ProjectState.error;
      project.lastError = e.toString();
      return false;
    }
  }

  Future<bool> stopProject(String projectId) async {
    final companion = _companionProcesses.remove(projectId);
    if (companion != null) {
      try {
        companion.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }

    final process = _runningProcesses[projectId];
    if (process == null) return true;

    try {
      final killed = process.kill(ProcessSignal.sigterm);
      if (!killed) {
        process.kill(ProcessSignal.sigkill);
      }
      _runningProcesses.remove(projectId);
      _processInfos.remove(projectId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> restartProject(
    Project project, {
    void Function(String line, bool isError)? onLog,
  }) async {
    await stopProject(project.id);
    await Future.delayed(const Duration(milliseconds: 500));
    return await startProject(project, onLog: onLog);
  }

  void stopAll() {
    for (final companion in _companionProcesses.values) {
      try {
        companion.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
    _companionProcesses.clear();

    for (final pid in _runningProcesses.keys.toList()) {
      stopProject(pid);
    }
  }
}

