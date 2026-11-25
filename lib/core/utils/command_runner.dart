import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../services/runtime/portable_runtime_manager.dart';

class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get isSuccess => exitCode == 0;
}

class CommandRunner {
  static List<String> getSearchDirectories([String? workingDirectory]) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final searchDirs = <String>[];

    // Project-local binaries first (e.g., node_modules/.bin, vendor/bin, .venv)
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      searchDirs.add(p.join(workingDirectory, 'node_modules', '.bin'));
      searchDirs.add(p.join(workingDirectory, 'vendor', 'bin'));
      if (Platform.isWindows) {
        searchDirs.add(p.join(workingDirectory, '.venv', 'Scripts'));
      } else {
        searchDirs.add(p.join(workingDirectory, '.venv', 'bin'));
      }
    }

    // App-managed isolated portable runtimes (Windows & macOS)
    searchDirs.addAll(PortableRuntimeManager.getManagedBinDirectories());

    searchDirs.addAll([
      p.join(home, '.local', 'bin'),
      p.join(home, '.local', 'node', 'bin'),
      p.join(home, '.nvm', 'current', 'bin'),
      p.join(home, '.fnm', 'current', 'bin'),
      p.join(home, '.volta', 'bin'),
      p.join(home, '.cargo', 'bin'),
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ]);

    if (Platform.isMacOS) {
      searchDirs.addAll([
        '/Applications/XAMPP/xamppfiles/bin',
        '/usr/local/mysql/bin',
        '/opt/homebrew/opt/mysql/bin',
        '/opt/homebrew/opt/mariadb/bin',
      ]);
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final userProfile = Platform.environment['USERPROFILE'] ?? home;

      searchDirs.addAll([
        p.join(programFiles, 'nodejs'),
        p.join(programFilesX86, 'nodejs'),
        p.join(localAppData, 'Programs', 'nodejs'),
        p.join(userProfile, 'AppData', 'Roaming', 'npm'),
        p.join(programFiles, 'Git', 'cmd'),
        p.join(programFiles, 'Git', 'bin'),
        p.join(programFilesX86, 'Git', 'cmd'),
        p.join(programFilesX86, 'Git', 'bin'),
        p.join(localAppData, 'Programs', 'Git', 'cmd'),
        p.join(localAppData, 'Programs', 'Git', 'bin'),
        p.join(userProfile, 'scoop', 'shims'),
        r'C:\ProgramData\chocolatey\bin',
        p.join(userProfile, 'AppData', 'Local', 'GitHubDesktop', 'bin'),
        r'C:\PortableGit\cmd',
        r'C:\PortableGit\bin',
        r'C:\Git\cmd',
        r'C:\Git\bin',
        r'C:\xampp\mysql\bin',
        r'C:\Program Files\MySQL\MySQL Server 8.0\bin',
        r'C:\Program Files\MariaDB 10.5\bin',
      ]);
    }

    // Check nvm versions dynamically
    final nvmDir = Directory(p.join(home, '.nvm', 'versions', 'node'));
    if (nvmDir.existsSync()) {
      try {
        for (final entity in nvmDir.listSync()) {
          if (entity is Directory) {
            searchDirs.add(p.join(entity.path, 'bin'));
          }
        }
      } catch (_) {}
    }

    return searchDirs;
  }

  static String resolveExecutable(String executable, {String? workingDirectory}) {
    if (executable.contains(Platform.pathSeparator)) {
      return executable;
    }

    final searchDirs = getSearchDirectories(workingDirectory);

    for (final dir in searchDirs) {
      final candidate = p.join(dir, executable);
      if (File(candidate).existsSync()) {
        return candidate;
      }
      if (Platform.isWindows) {
        if (File('$candidate.exe').existsSync()) return '$candidate.exe';
        if (File('$candidate.cmd').existsSync()) return '$candidate.cmd';
        if (File('$candidate.bat').existsSync()) return '$candidate.bat';
      }
    }

    return executable;
  }

  static Map<String, String> getEnhancedEnvironment([
    Map<String, String>? extra,
    String? workingDirectory,
  ]) {
    final separator = Platform.isWindows ? ';' : ':';
    final searchDirs = getSearchDirectories(workingDirectory);

    final validPaths = searchDirs.where((path) => Directory(path).existsSync()).toList();

    // Auto-detect node directory and place at front of PATH
    final nodeBin = resolveExecutable('node', workingDirectory: workingDirectory);
    if (nodeBin.contains(Platform.pathSeparator)) {
      final nodeDir = p.dirname(nodeBin);
      if (!validPaths.contains(nodeDir)) {
        validPaths.insert(0, nodeDir);
      }
    }

    // Include existing system PATH and any extra PATH
    final currentPath = Platform.environment['PATH'] ?? '';
    final extraPath = extra?['PATH'] ?? '';

    final combined = <String>[
      ...validPaths,
      if (extraPath.isNotEmpty) ...extraPath.split(separator),
      if (currentPath.isNotEmpty) ...currentPath.split(separator),
    ];

    final deduped = <String>[];
    for (final dir in combined) {
      final trimmed = dir.trim();
      if (trimmed.isNotEmpty && !deduped.contains(trimmed)) {
        deduped.add(trimmed);
      }
    }

    final finalPath = deduped.join(separator);

    final merged = <String, String>{
      ...Platform.environment,
      'CI': 'true',
      'GIT_TERMINAL_PROMPT': '0',
      'COMPOSER_NO_INTERACTION': '1',
      'PIP_NO_INPUT': '1',
      'npm_config_yes': 'true',
      'npm_config_audit': 'false',
      'npm_config_fund': 'false',
      ...?extra,
      'PATH': finalPath, // Guaranteed to have our enhanced searchDirs at the very front
    };

    // Enable system CA store when running our managed Node runtime (v22.15+)
    final managedNodeDir = p.join(PortableRuntimeManager.getRuntimesRootDir(), 'node');
    if (nodeBin.startsWith(managedNodeDir) &&
        File(p.join(managedNodeDir, '.use_system_ca')).existsSync()) {
      final currentNodeOpts = merged['NODE_OPTIONS'] ?? '';
      if (!currentNodeOpts.contains('--use-system-ca')) {
        merged['NODE_OPTIONS'] = currentNodeOpts.isEmpty
            ? '--use-system-ca'
            : '$currentNodeOpts --use-system-ca';
      }
    }

    return merged;
  }

  static Future<Process> _spawnProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final resolvedExecutable = resolveExecutable(executable, workingDirectory: workingDirectory);
    final env = getEnhancedEnvironment(environment, workingDirectory);

    if (Platform.isWindows) {
      final lower = resolvedExecutable.toLowerCase();
      // Direct .exe execution avoids cmd.exe space-quoting bugs and preserves real child PID
      if (lower.endsWith('.exe')) {
        return Process.start(
          resolvedExecutable,
          arguments,
          workingDirectory: workingDirectory,
          environment: env,
          runInShell: false,
        );
      }
      // .cmd/.bat wrappers or unresolved shell commands run via cmd.exe /d /c
      if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
        return Process.start(
          Platform.environment['ComSpec'] ?? 'cmd.exe',
          ['/d', '/c', resolvedExecutable, ...arguments],
          workingDirectory: workingDirectory,
          environment: env,
          runInShell: false,
        );
      }
      return Process.start(
        resolvedExecutable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        runInShell: true,
      );
    }

    // On macOS/Linux, run resolved absolute binaries directly without a shell wrapper
    final isResolvedPath = resolvedExecutable.contains(Platform.pathSeparator);
    return Process.start(
      resolvedExecutable,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      runInShell: !isResolvedPath,
    );
  }

  /// Terminates a process and its descendants (important on Windows for cmd/npm trees).
  static Future<void> killProcessTree(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
      } else {
        final killed = process.kill(ProcessSignal.sigterm);
        if (!killed) {
          process.kill(ProcessSignal.sigkill);
        }
      }
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  static Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    void Function(String output, bool isError)? onLine,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    Process? process;
    try {
      process = await _spawnProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );

      // Immediately close stdin so CLI tools never hang waiting for interactive input
      try {
        await process.stdin.close();
      } catch (_) {}

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        stdoutBuffer.write(data);
        if (onLine != null) {
          for (final line in data.split(RegExp(r'\r\n|\n|\r'))) {
            if (line.trim().isNotEmpty) onLine(line, false);
          }
        }
      }, onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      });

      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        stderrBuffer.write(data);
        if (onLine != null) {
          for (final line in data.split(RegExp(r'\r\n|\n|\r'))) {
            if (line.trim().isNotEmpty) onLine(line, true);
          }
        }
      }, onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      });

      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () async {
          onLine?.call('✗ Command timed out after ${timeout.inSeconds}s: $executable ${arguments.join(" ")}', true);
          if (process != null) {
            await killProcessTree(process);
          }
          return -2;
        },
      );

      await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
        const Duration(seconds: 2),
        onTimeout: () => <void>[],
      );

      return CommandResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } catch (e) {
      if (process != null) {
        await killProcessTree(process);
      }
      if (onLine != null) {
        onLine('Command execution error: $e', true);
      }
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  static Future<Process> startStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required void Function(String line, bool isError) onLine,
  }) async {
    final process = await _spawnProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) {
          onLine(line, false);
        }
      }
    });

    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) {
          onLine(line, true);
        }
      }
    });

    return process;
  }
}
