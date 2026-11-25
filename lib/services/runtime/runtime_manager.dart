import 'dart:io';
import '../../core/models/runtime_info.dart';
import '../../core/utils/command_runner.dart';

class RuntimeManager {
  static Future<List<RuntimeInfo>> detectAllRuntimes() async {
    final list = <RuntimeInfo>[];
    for (final type in RuntimeType.values) {
      list.add(await checkRuntime(type));
    }
    return list;
  }

  static Future<RuntimeInfo> checkRuntime(RuntimeType type) async {
    String cmd;
    List<String> args;
    String winInstall;
    String macInstall;

    switch (type) {
      case RuntimeType.node:
        cmd = 'node';
        args = ['--version'];
        winInstall = 'winget install OpenJS.NodeJS';
        macInstall = 'brew install node';
        break;
      case RuntimeType.npm:
        cmd = 'npm';
        args = ['--version'];
        winInstall = 'npm comes with Node.js';
        macInstall = 'npm comes with Node.js';
        break;
      case RuntimeType.pnpm:
        cmd = 'pnpm';
        args = ['--version'];
        winInstall = 'npm install -g pnpm';
        macInstall = 'npm install -g pnpm';
        break;
      case RuntimeType.yarn:
        cmd = 'yarn';
        args = ['--version'];
        winInstall = 'npm install -g yarn';
        macInstall = 'npm install -g yarn';
        break;
      case RuntimeType.python:
        cmd = Platform.isWindows ? 'python' : 'python3';
        args = ['--version'];
        winInstall = 'winget install Python.Python.3.11';
        macInstall = 'brew install python';
        break;
      case RuntimeType.pip:
        cmd = Platform.isWindows ? 'pip' : 'pip3';
        args = ['--version'];
        winInstall = 'python -m ensurepip';
        macInstall = 'python3 -m ensurepip';
        break;
      case RuntimeType.poetry:
        cmd = 'poetry';
        args = ['--version'];
        winInstall = 'pip install poetry';
        macInstall = 'brew install poetry';
        break;
      case RuntimeType.uv:
        cmd = 'uv';
        args = ['--version'];
        winInstall = 'pip install uv';
        macInstall = 'brew install uv';
        break;
      case RuntimeType.php:
        cmd = 'php';
        args = ['--version'];
        winInstall = 'winget install PHP.PHP';
        macInstall = 'brew install php';
        break;
      case RuntimeType.composer:
        cmd = 'composer';
        args = ['--version'];
        winInstall = 'winget install Composer.Composer';
        macInstall = 'brew install composer';
        break;
      case RuntimeType.git:
        cmd = 'git';
        args = ['--version'];
        winInstall = 'winget install Git.Git';
        macInstall = 'xcode-select --install';
        break;
      case RuntimeType.docker:
        cmd = 'docker';
        args = ['--version'];
        winInstall = 'winget install Docker.DockerDesktop';
        macInstall = 'brew install --cask docker';
        break;
      case RuntimeType.sqlite3:
        cmd = 'sqlite3';
        args = ['--version'];
        winInstall = 'winget install SQLite.SQLite';
        macInstall = 'Built-in on macOS';
        break;
      case RuntimeType.mysql:
        cmd = 'mysql';
        args = ['--version'];
        winInstall = 'winget install Oracle.MySQL';
        macInstall = 'brew install mysql';
        break;
      case RuntimeType.postgres:
        cmd = 'psql';
        args = ['--version'];
        winInstall = 'winget install PostgreSQL.PostgreSQL';
        macInstall = 'brew install postgresql@16';
        break;
      case RuntimeType.cloudflared:
        cmd = 'cloudflared';
        args = ['--version'];
        winInstall = 'winget install Cloudflare.cloudflared';
        macInstall = 'brew install cloudflared';
        break;
    }

    try {
      final resolvedPath = CommandRunner.resolveExecutable(cmd);
      // Skip Windows Store app execution alias stubs unless they execute cleanly
      if (Platform.isWindows &&
          resolvedPath.toLowerCase().contains(r'\microsoft\windowsapps\')) {
        return RuntimeInfo(
          type: type,
          isInstalled: false,
          installCommandWindows: winInstall,
          installCommandMac: macInstall,
        );
      }

      final res = await CommandRunner.run(
        cmd,
        args,
        timeout: const Duration(seconds: 15),
      );
      final combinedOutput = (res.stdout.isNotEmpty ? res.stdout : res.stderr).trim();
      final versionLine = combinedOutput.isEmpty ? '' : combinedOutput.split('\n').first.trim();
      if (res.isSuccess && versionLine.isNotEmpty) {
        return RuntimeInfo(
          type: type,
          isInstalled: true,
          version: versionLine,
          binaryPath: resolvedPath,
          installCommandWindows: winInstall,
          installCommandMac: macInstall,
        );
      }
    } catch (_) {}

    return RuntimeInfo(
      type: type,
      isInstalled: false,
      installCommandWindows: winInstall,
      installCommandMac: macInstall,
    );
  }
}

