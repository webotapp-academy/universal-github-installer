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
      ...?extra,
      'PATH': finalPath, // Guaranteed to have our enhanced searchDirs at the very front
    };

    return merged;
  }

  static Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    void Function(String output, bool isError)? onLine,
  }) async {
    try {
      final resolvedExecutable = resolveExecutable(executable, workingDirectory: workingDirectory);
      final env = getEnhancedEnvironment(environment, workingDirectory);

      final process = await Process.start(
        resolvedExecutable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        runInShell: true,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      process.stdout.transform(utf8.decoder).listen((data) {
        stdoutBuffer.write(data);
        if (onLine != null) {
          for (final line in data.split('\n')) {
            if (line.isNotEmpty) onLine(line, false);
          }
        }
      }, onDone: () => stdoutDone.complete());

      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);
        if (onLine != null) {
          for (final line in data.split('\n')) {
            if (line.isNotEmpty) onLine(line, true);
          }
        }
      }, onDone: () => stderrDone.complete());

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone.future, stderrDone.future]);

      return CommandResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } catch (e) {
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
    final resolvedExecutable = resolveExecutable(executable, workingDirectory: workingDirectory);
    final env = getEnhancedEnvironment(environment, workingDirectory);

    final process = await Process.start(
      resolvedExecutable,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      runInShell: true,
    );

    process.stdout.transform(utf8.decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) {
          onLine(line, false);
        }
      }
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) {
          onLine(line, true);
        }
      }
    });

    return process;
  }
}
