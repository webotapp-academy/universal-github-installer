import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../../core/constants/supported_technologies.dart';
import '../../core/models/installation_plan.dart';
import '../../core/models/project.dart';
import '../../core/models/runtime_info.dart';
import '../../core/utils/command_runner.dart';
import '../database/database_manager.dart';
import 'portable_runtime_manager.dart';

class DependencyInstaller {
  static void ensureEnvAndKey(String projectPath, {int port = 8000, void Function(String, bool)? onLine}) {
    final envFile = File(p.join(projectPath, '.env'));
    final envExample = File(p.join(projectPath, '.env.example'));

    if (!envFile.existsSync()) {
      if (envExample.existsSync()) {
        try {
          envExample.copySync(envFile.path);
          onLine?.call('✓ Created .env configuration from .env.example', false);
        } catch (e) {
          onLine?.call('Warning copying .env: $e', true);
        }
      } else {
        envFile.writeAsStringSync('APP_NAME="Laravel Application"\nAPP_ENV=local\nAPP_KEY=\nAPP_DEBUG=true\nAPP_URL=http://localhost:$port\n');
      }
    }

    if (envFile.existsSync()) {
      var content = envFile.readAsStringSync();

      // Ensure APP_URL has correct port
      if (content.contains('APP_URL=')) {
        content = content.replaceFirst(RegExp(r'APP_URL=.*'), 'APP_URL=http://localhost:$port');
      }

      // Check if APP_KEY is empty, missing, or invalid placeholder (e.g. '', "", or < 32 chars)
      final keyMatch = RegExp(r'^APP_KEY=(.*)$', multiLine: true).firstMatch(content);
      final rawKey = keyMatch?.group(1)?.trim() ?? '';
      final cleanedKey = rawKey.replaceAll('"', '').replaceAll("'", '').trim();

      if (cleanedKey.isEmpty || (!cleanedKey.startsWith('base64:') && cleanedKey.length < 32)) {
        final rand = Random.secure();
        final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
        final generatedKey = 'base64:${base64Encode(bytes)}';

        if (content.contains('APP_KEY=')) {
          content = content.replaceFirst(RegExp(r'APP_KEY=.*'), 'APP_KEY=$generatedKey');
        } else {
          content = 'APP_KEY=$generatedKey\n$content';
        }
        onLine?.call('✓ Injected valid 32-byte encryption APP_KEY into .env', false);
      }

      // Ensure SQLite DB file exists if DB_CONNECTION is sqlite or default
      if (content.contains('DB_CONNECTION=sqlite') || !content.contains('DB_CONNECTION=')) {
        final sqliteFile = File(p.join(projectPath, 'database', 'database.sqlite'));
        if (!sqliteFile.existsSync()) {
          try {
            sqliteFile.createSync(recursive: true);
            onLine?.call('✓ Created database/database.sqlite', false);
          } catch (_) {}
        }
      }

      envFile.writeAsStringSync(content);

      // Clear any stale Laravel config cache so new APP_KEY takes effect immediately
      final configCache = File(p.join(projectPath, 'bootstrap', 'cache', 'config.php'));
      if (configCache.existsSync()) {
        try {
          configCache.deleteSync();
          onLine?.call('✓ Cleared stale Laravel bootstrap/cache/config.php', false);
        } catch (_) {}
      }
    }
  }

  static InstallationPlan generatePlan(Project project) {
    final steps = <InstallationStep>[];
    final tech = project.techStack;
    final path = project.localPath;
    final port = project.port;

    String startCmd = 'node';
    List<String> startArgs = ['index.js'];
    final envVars = <String, String>{
      'PORT': port.toString(),
      ...project.envVariables,
    };

    switch (tech.language) {
      case ProgrammingLanguage.php:
        if (tech.framework == FrameworkType.laravel) {
          steps.add(InstallationStep(
            id: 'composer_install',
            title: 'Install Composer Dependencies',
            description: 'Run composer install --no-interaction',
            command: 'composer',
            args: ['install', '--no-interaction', '--prefer-dist'],
            workingDirectory: path,
          ));
          steps.add(InstallationStep(
            id: 'artisan_key',
            title: 'Generate Application Encryption Key',
            description: 'Run php artisan key:generate',
            command: 'php',
            args: ['artisan', 'key:generate', '--force'],
            workingDirectory: path,
          ));
          steps.add(InstallationStep(
            id: 'config_clear',
            title: 'Clear Configuration Cache',
            description: 'Run php artisan config:clear',
            command: 'php',
            args: ['artisan', 'config:clear'],
            workingDirectory: path,
          ));
          final packageJsonFile = File(p.join(path, 'package.json'));
          if (packageJsonFile.existsSync()) {
            steps.add(InstallationStep(
              id: 'npm_install',
              title: 'Install Frontend Dependencies',
              description: 'Install npm packages for frontend assets',
              command: 'npm',
              args: ['install'],
              workingDirectory: path,
            ));
            bool hasBuildScript = false;
            try {
              final pkgJson = jsonDecode(packageJsonFile.readAsStringSync());
              final scripts = pkgJson['scripts'];
              if (scripts is Map && scripts.containsKey('build')) {
                hasBuildScript = true;
              }
            } catch (_) {}
            if (hasBuildScript) {
              steps.add(InstallationStep(
                id: 'npm_build',
                title: 'Build Production Frontend Assets',
                description: 'Run npm run build to compile Vite / Tailwind assets',
                command: 'npm',
                args: ['run', 'build'],
                workingDirectory: path,
              ));
            }
          }
          steps.add(InstallationStep(
            id: 'artisan_migrate',
            title: 'Run Database Migrations',
            description: 'Run php artisan migrate --force',
            command: 'php',
            args: ['artisan', 'migrate', '--force'],
            workingDirectory: path,
            isDestructive: true,
            requiresUserApproval: true,
          ));
          final seederFile = File(p.join(path, 'database', 'seeders', 'DatabaseSeeder.php'));
          final legacySeeder = File(p.join(path, 'database', 'seeds', 'DatabaseSeeder.php'));
          if (seederFile.existsSync() || legacySeeder.existsSync()) {
            steps.add(InstallationStep(
              id: 'artisan_seed',
              title: 'Seed Database with Initial Users & Demo Data',
              description: 'Run php artisan db:seed --force to populate default accounts',
              command: 'php',
              args: ['artisan', 'db:seed', '--force'],
              workingDirectory: path,
            ));
          }
          startCmd = 'php';
          startArgs = ['artisan', 'serve', '--host=127.0.0.1', '--port=$port'];
        } else {
          if (tech.packageManager == 'composer') {
            steps.add(InstallationStep(
              id: 'composer_install',
              title: 'Install Composer Packages',
              description: 'Run composer install',
              command: 'composer',
              args: ['install'],
              workingDirectory: path,
            ));
          }
          startCmd = 'php';
          startArgs = ['-S', '127.0.0.1:$port'];
        }
        break;

      case ProgrammingLanguage.nodeJs:
        final pkgMgr = tech.packageManager ?? 'npm';
        steps.add(InstallationStep(
          id: 'node_install_deps',
          title: 'Install Node Dependencies',
          description: 'Run $pkgMgr install',
          command: pkgMgr,
          args: ['install'],
          workingDirectory: path,
        ));

        // Check for Prisma migrations
        if (Directory(p.join(path, 'prisma')).existsSync()) {
          steps.add(InstallationStep(
            id: 'prisma_generate',
            title: 'Generate Prisma Client & DB Push',
            description: 'Run npx prisma generate',
            command: 'npx',
            args: ['prisma', 'generate'],
            workingDirectory: path,
          ));
        }

        // Determine start command
        if (tech.detectedScripts.contains('dev')) {
          startCmd = pkgMgr;
          if (tech.framework == FrameworkType.vite) {
            startArgs = ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '$port'];
          } else {
            startArgs = ['run', 'dev', '--', '--port', '$port'];
          }
        } else if (tech.detectedScripts.contains('start')) {
          startCmd = pkgMgr;
          startArgs = ['start'];
        } else {
          startCmd = 'node';
          startArgs = ['index.js'];
        }
        break;

      case ProgrammingLanguage.python:
        final isWin = Platform.isWindows;
        final venvPython = isWin ? p.join(path, '.venv', 'Scripts', 'python.exe') : p.join(path, '.venv', 'bin', 'python');
        final venvPip = isWin ? p.join(path, '.venv', 'Scripts', 'pip.exe') : p.join(path, '.venv', 'bin', 'pip');

        // Step 1: Create venv
        steps.add(InstallationStep(
          id: 'py_venv',
          title: 'Create Isolated Python Virtual Environment',
          description: 'Run python -m venv .venv',
          command: isWin ? 'python' : 'python3',
          args: ['-m', 'venv', '.venv'],
          workingDirectory: path,
        ));

        // Step 2: Install requirements
        if (File(p.join(path, 'requirements.txt')).existsSync()) {
          steps.add(InstallationStep(
            id: 'py_requirements',
            title: 'Install Python Requirements',
            description: 'Run pip install -r requirements.txt',
            command: venvPip,
            args: ['install', '-r', 'requirements.txt'],
            workingDirectory: path,
          ));
        } else if (File(p.join(path, 'pyproject.toml')).existsSync()) {
          steps.add(InstallationStep(
            id: 'py_install_project',
            title: 'Install Python Package',
            description: 'Run pip install .',
            command: venvPip,
            args: ['install', '.'],
            workingDirectory: path,
          ));
        }

        if (tech.framework == FrameworkType.django) {
          steps.add(InstallationStep(
            id: 'django_migrate',
            title: 'Run Django Migrations',
            description: 'Run python manage.py migrate',
            command: venvPython,
            args: ['manage.py', 'migrate'],
            workingDirectory: path,
            isDestructive: true,
            requiresUserApproval: true,
          ));
          startCmd = venvPython;
          startArgs = ['manage.py', 'runserver', '127.0.0.1:$port'];
        } else if (tech.framework == FrameworkType.fastApi) {
          startCmd = venvPython;
          startArgs = ['-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', '$port'];
        } else if (tech.framework == FrameworkType.streamlit) {
          startCmd = venvPython;
          startArgs = ['-m', 'streamlit', 'run', 'app.py', '--server.port', '$port'];
        } else if (tech.framework == FrameworkType.flask) {
          startCmd = venvPython;
          startArgs = ['-m', 'flask', 'run', '--host=127.0.0.1', '--port=$port'];
        } else {
          startCmd = venvPython;
          startArgs = ['main.py'];
        }
        break;

      case ProgrammingLanguage.dockerCompose:
        steps.add(InstallationStep(
          id: 'docker_up',
          title: 'Start Docker Compose Stack',
          description: 'Run docker compose up -d',
          command: 'docker',
          args: ['compose', 'up', '-d'],
          workingDirectory: path,
        ));
        startCmd = 'docker';
        startArgs = ['compose', 'logs', '-f'];
        break;

      case ProgrammingLanguage.staticWeb:
        startCmd = Platform.isWindows ? 'python' : 'python3';
        startArgs = ['-m', 'http.server', '$port'];
        break;

      default:
        startCmd = 'echo';
        startArgs = ['No start command configured for this project'];
        break;
    }

    return InstallationPlan(
      projectId: project.id,
      steps: steps,
      startCommand: startCmd,
      startArgs: startArgs,
      assignedPort: port,
      requiredEnvVars: envVars,
    );
  }

  static Future<bool> executeStep(
    InstallationStep step, {
    Map<String, String>? env,
    required void Function(String output, bool isError) onLine,
  }) async {
    step.isRunning = true;
    step.errorMessage = null;

    onLine('>>> Executing: ${step.command} ${step.args.join(" ")}', false);

    final res = await CommandRunner.run(
      step.command,
      step.args,
      workingDirectory: step.workingDirectory,
      environment: env,
      onLine: onLine,
    );

    step.isRunning = false;
    if (res.isSuccess) {
      step.completed = true;
      onLine('✓ Step completed: ${step.title}\n', false);
      return true;
    } else {
      step.completed = false;
      step.errorMessage = res.stderr.isNotEmpty ? res.stderr : 'Step failed with code ${res.exitCode}';
      onLine('✗ Step failed: ${step.errorMessage}\n', true);
      return false;
    }
  }

  static Future<bool> executeAllSteps(
    InstallationPlan plan, {
    required Project project,
    required void Function(String output, bool isError) onLine,
    required Future<bool> Function(InstallationStep step) requestApproval,
    void Function(String stageLabel)? onStageUpdate,
  }) async {
    onStageUpdate?.call('Checking & provisioning required runtimes...');
    // Bootstrap any missing portable runtimes needed by this plan
    final runtimesOk = await _ensurePlanRuntimes(plan, onLine: onLine);
    if (!runtimesOk) {
      return false;
    }

    onStageUpdate?.call('Configuring .env and provisioning database...');
    // Pre-execution environment setup (guarantee .env and APP_KEY for Laravel/PHP)
    if (File(p.join(project.localPath, 'artisan')).existsSync() || File(p.join(project.localPath, '.env.example')).existsSync()) {
      ensureEnvAndKey(project.localPath, port: project.port, onLine: onLine);
    }

    // Also provision database if required
    await DatabaseManager.provisionDatabaseForProject(project, onLine: onLine);

    // Sync environment variables with plan so steps (like migrate) have correct DB credentials
    plan.requiredEnvVars.addAll(project.envVariables);

    final totalSteps = plan.steps.length;
    for (int i = 0; i < totalSteps; i++) {
      final step = plan.steps[i];
      if (step.requiresUserApproval) {
        onStageUpdate?.call('Waiting for approval: ${step.title}');
        final approved = await requestApproval(step);
        if (!approved) {
          onLine('User skipped or declined step: ${step.title}', false);
          continue;
        }
      }

      onStageUpdate?.call('Step ${i + 1}/$totalSteps: ${step.title}...');
      final success = await executeStep(
        step,
        env: plan.requiredEnvVars,
        onLine: onLine,
      );

      if (!success && !step.isDestructive) {
        // Stop on critical failure
        return false;
      }
    }
    return true;
  }

  static Future<bool> _ensurePlanRuntimes(
    InstallationPlan plan, {
    required void Function(String output, bool isError)? onLine,
  }) async {
    final commands = <String>{
      plan.startCommand,
      ...plan.steps.map((s) => s.command),
    };

    final needed = <RuntimeType>{};
    for (final raw in commands) {
      final cmd = p.basenameWithoutExtension(raw).toLowerCase();
      if (cmd == 'node' || cmd == 'npm' || cmd == 'npx' || cmd == 'pnpm' || cmd == 'yarn') {
        needed.add(RuntimeType.node);
      } else if (cmd == 'php') {
        needed.add(RuntimeType.php);
      } else if (cmd == 'composer') {
        needed.add(RuntimeType.php);
        needed.add(RuntimeType.composer);
      } else if (cmd == 'uv') {
        needed.add(RuntimeType.uv);
      }
    }

    for (final runtime in needed) {
      if (PortableRuntimeManager.supportsPortableInstall(runtime)) {
        final ok = await PortableRuntimeManager.ensureRuntime(runtime, onProgress: onLine);
        if (!ok) {
          onLine?.call(
            '✗ Required runtime "${runtime.displayName}" is not available and could not be bootstrapped.',
            true,
          );
          return false;
        }
      }
    }
    return true;
  }
}
