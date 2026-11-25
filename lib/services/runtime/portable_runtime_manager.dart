import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../core/models/runtime_info.dart';
import '../../core/utils/command_runner.dart';

/// Manages self-contained, on-demand portable runtimes inside the app's
/// isolated `runtimes/` directory on Windows and macOS without requiring
/// administrator privileges or global system installers.
class PortableRuntimeManager {
  static const String _userAgent = 'WebotApp-Universal-GitHub-Installer';
  static final Map<RuntimeType, Future<bool>> _inFlight = {};

  /// Returns the root directory where app-managed portable runtimes are stored.
  static String getRuntimesRootDir() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'WebotApp', 'GitHubInstaller', 'runtimes');
      }
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      return p.join(userProfile, '.webotapp-installer', 'runtimes');
    }

    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isMacOS) {
      return p.join(
        home,
        'Library',
        'Application Support',
        'WebotApp',
        'GitHubInstaller',
        'runtimes',
      );
    }
    return p.join(home, '.webotapp-installer', 'runtimes');
  }

  /// Synchronously returns all existing managed runtime `bin` directories
  /// so [CommandRunner] can prepend them to `PATH`.
  static List<String> getManagedBinDirectories() {
    final root = getRuntimesRootDir();
    final candidates = <String>[
      p.join(root, 'git', 'cmd'),
      p.join(root, 'git', 'mingw64', 'bin'),
      p.join(root, 'git', 'usr', 'bin'),
      p.join(root, 'node'),
      p.join(root, 'node', 'bin'),
      p.join(root, 'uv'),
      p.join(root, 'php'),
      p.join(root, 'composer'),
      p.join(root, 'cloudflared'),
    ];

    return candidates.where((dir) => Directory(dir).existsSync()).toList();
  }

  /// Returns whether [type] can be automatically bootstrapped as a portable
  /// runtime on the current platform.
  static bool supportsPortableInstall(RuntimeType type) {
    switch (type) {
      case RuntimeType.git:
        return Platform.isWindows;
      case RuntimeType.node:
      case RuntimeType.npm:
      case RuntimeType.uv:
      case RuntimeType.php:
      case RuntimeType.composer:
      case RuntimeType.cloudflared:
        return Platform.isWindows || Platform.isMacOS;
      default:
        return false;
    }
  }

  /// Ensures [type] is available, either already on the system/managed PATH
  /// or by downloading and extracting its portable binary into [getRuntimesRootDir].
  static Future<bool> ensureRuntime(
    RuntimeType type, {
    void Function(String output, bool isError)? onProgress,
  }) async {
    if (await _isRuntimeAvailable(type)) {
      return true;
    }

    if (!supportsPortableInstall(type)) {
      return false;
    }

    final normalizedType = type == RuntimeType.npm ? RuntimeType.node : type;
    if (_inFlight.containsKey(normalizedType)) {
      return _inFlight[normalizedType]!;
    }

    final future = _installPortable(normalizedType, onProgress: onProgress)
        .whenComplete(() => _inFlight.remove(normalizedType));
    _inFlight[normalizedType] = future;
    return future;
  }

  static Future<bool> _isRuntimeAvailable(RuntimeType type) async {
    final cmd = switch (type) {
      RuntimeType.git => 'git',
      RuntimeType.node => 'node',
      RuntimeType.npm => 'npm',
      RuntimeType.uv => 'uv',
      RuntimeType.php => 'php',
      RuntimeType.composer => 'composer',
      RuntimeType.cloudflared => 'cloudflared',
      _ => '',
    };
    if (cmd.isEmpty) return false;

    try {
      final res = await CommandRunner.run(cmd, ['--version']);
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _installPortable(
    RuntimeType type, {
    void Function(String output, bool isError)? onProgress,
  }) async {
    try {
      switch (type) {
        case RuntimeType.git:
          return await _installMinGit(onProgress: onProgress);
        case RuntimeType.node:
          return await _installNode(onProgress: onProgress);
        case RuntimeType.uv:
          return await _installUv(onProgress: onProgress);
        case RuntimeType.php:
          return await _installPhp(onProgress: onProgress);
        case RuntimeType.composer:
          return await _installComposer(onProgress: onProgress);
        case RuntimeType.cloudflared:
          return await _installCloudflared(onProgress: onProgress);
        default:
          return false;
      }
    } catch (e) {
      onProgress?.call('✗ Failed to bootstrap portable ${type.displayName}: $e', true);
      return false;
    }
  }

  static Future<bool> _installMinGit({
    void Function(String output, bool isError)? onProgress,
  }) async {
    onProgress?.call('📦 Fetching latest portable MinGit release info...', false);
    final body = await _fetchText(
      'https://api.github.com/repos/git-for-windows/git/releases/latest',
    );

    final data = jsonDecode(body) as Map<String, dynamic>;
    final assets = (data['assets'] as List<dynamic>? ?? []);
    String? downloadUrl;
    String? assetName;

    for (final rawAsset in assets) {
      final asset = rawAsset as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      if (name.startsWith('MinGit-') &&
          name.endsWith('-64-bit.zip') &&
          !name.contains('busybox')) {
        downloadUrl = asset['browser_download_url'] as String?;
        assetName = name;
        break;
      }
    }

    if (downloadUrl == null) {
      onProgress?.call('✗ Could not find a 64-bit MinGit archive in latest release.', true);
      return false;
    }

    onProgress?.call('⬇️ Downloading $assetName into app environment...', false);
    final bytes = await downloadBytes(downloadUrl);
    final targetDir = p.join(getRuntimesRootDir(), 'git');
    await _extractZip(bytes, targetDir);
    onProgress?.call('✓ Portable Git installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.git);
  }

  static Future<bool> _installNode({
    void Function(String output, bool isError)? onProgress,
  }) async {
    onProgress?.call('📦 Resolving latest Node.js LTS portable build...', false);
    final sumsBody = await _fetchText(
      'https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt',
    );

    final arch = await _getMacArch();
    final pattern = Platform.isWindows
        ? RegExp(r'(node-v22\.\d+\.\d+-win-x64\.zip)')
        : RegExp('node-v22\\.\\d+\\.\\d+-darwin-$arch\\.tar\\.gz');

    final match = pattern.firstMatch(sumsBody);
    if (match == null) {
      onProgress?.call('✗ Could not locate Node.js v22 archive for this platform.', true);
      return false;
    }

    final fileName = match.group(0)!;
    final url = 'https://nodejs.org/dist/latest-v22.x/$fileName';
    onProgress?.call('⬇️ Downloading $fileName into app environment...', false);
    final bytes = await downloadBytes(url);
    final targetDir = p.join(getRuntimesRootDir(), 'node');

    if (Platform.isWindows) {
      await _extractZip(bytes, targetDir, stripTopLevelDir: true);
    } else {
      await _extractTarGz(bytes, targetDir, stripTopLevelDir: true);
      await _makeBinariesExecutable(p.join(targetDir, 'bin'));
    }

    onProgress?.call('✓ Portable Node.js & npm installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.node);
  }

  static Future<bool> _installUv({
    void Function(String output, bool isError)? onProgress,
  }) async {
    final arch = await _getMacArch();
    final asset = Platform.isWindows
        ? 'uv-x86_64-pc-windows-msvc.zip'
        : 'uv-${arch == 'arm64' ? 'aarch64' : 'x86_64'}-apple-darwin.tar.gz';
    final url = 'https://github.com/astral-sh/uv/releases/latest/download/$asset';

    onProgress?.call('⬇️ Downloading $asset into app environment...', false);
    final bytes = await downloadBytes(url);
    final targetDir = p.join(getRuntimesRootDir(), 'uv');

    if (Platform.isWindows) {
      await _extractZip(bytes, targetDir);
    } else {
      await _extractTarGz(bytes, targetDir, stripTopLevelDir: true);
      await _makeBinariesExecutable(targetDir);
    }

    onProgress?.call('✓ Portable uv (Python manager) installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.uv);
  }

  static Future<bool> _installPhp({
    void Function(String output, bool isError)? onProgress,
  }) async {
    final targetDir = p.join(getRuntimesRootDir(), 'php');

    if (Platform.isWindows) {
      onProgress?.call('📦 Fetching latest PHP Windows portable build...', false);
      final body = await _fetchText(
        'https://windows.php.net/downloads/releases/releases.json',
      );

      final releases = jsonDecode(body) as Map<String, dynamic>;
      String? zipName;
      for (final versionKey in ['8.3', '8.4', '8.2']) {
        final entry = releases[versionKey] as Map<String, dynamic>?;
        if (entry == null) continue;
        for (final key in entry.keys) {
          if (key.startsWith('nts-') && key.endsWith('-x64')) {
            final build = entry[key] as Map<String, dynamic>?;
            final zipMap = build?['zip'] as Map<String, dynamic>?;
            if (zipMap != null && zipMap['path'] is String) {
              zipName = zipMap['path'] as String;
              break;
            }
          }
        }
        if (zipName != null) break;
      }

      if (zipName == null) {
        onProgress?.call('✗ Could not locate PHP Windows x64 NTS archive.', true);
        return false;
      }

      final url = 'https://windows.php.net/downloads/releases/$zipName';
      onProgress?.call('⬇️ Downloading $zipName into app environment...', false);
      final bytes = await downloadBytes(url);
      await _extractZip(bytes, targetDir);
      await _configureWindowsPhpIni(targetDir, onProgress: onProgress);

      // Verify PHP actually launches (checks missing Visual C++ Redistributable DLLs)
      final check = await CommandRunner.run('php', ['--version']);
      if (!check.isSuccess) {
        if (check.exitCode == -1073741515 || check.exitCode == 3221225781) {
          onProgress?.call(
            '✗ Portable PHP failed to start (missing VCRUNTIME140.dll). Please install Microsoft Visual C++ Redistributable (x64): https://aka.ms/vs/17/release/vc_redist.x64.exe',
            true,
          );
        } else {
          onProgress?.call(
            '✗ Portable PHP health check failed (exit ${check.exitCode}): ${check.stderr}',
            true,
          );
        }
        return false;
      }
    } else if (Platform.isMacOS) {
      final arch = await _getMacArch();
      final spcArch = arch == 'arm64' ? 'aarch64' : 'x86_64';
      final url =
          'https://dl.static-php.dev/static-php-cli/common/php-8.3.14-cli-macos-$spcArch.tar.gz';
      onProgress?.call('⬇️ Downloading static PHP 8.3 for macOS ($spcArch)...', false);
      final bytes = await downloadBytes(url);
      await _extractTarGz(bytes, targetDir);
      await _makeBinariesExecutable(targetDir);
    }

    onProgress?.call('✓ Portable PHP installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.php);
  }

  static Future<void> _configureWindowsPhpIni(
    String phpDir, {
    void Function(String output, bool isError)? onProgress,
  }) async {
    final iniFile = File(p.join(phpDir, 'php.ini'));
    final prodIni = File(p.join(phpDir, 'php.ini-production'));
    if (!iniFile.existsSync() && !prodIni.existsSync()) return;

    var content = iniFile.existsSync()
        ? await iniFile.readAsString()
        : await prodIni.readAsString();

    content = content.replaceFirst(';extension_dir = "ext"', 'extension_dir = "ext"');
    for (final ext in [
      'curl',
      'fileinfo',
      'mbstring',
      'openssl',
      'pdo_mysql',
      'pdo_sqlite',
      'sqlite3',
      'zip',
    ]) {
      content = content.replaceFirst(';extension=$ext', 'extension=$ext');
    }

    // Bundle Mozilla CA bundle so Composer & PHP HTTPS requests succeed on Windows
    try {
      final sslDir = Directory(p.join(phpDir, 'extras', 'ssl'));
      if (!sslDir.existsSync()) {
        await sslDir.create(recursive: true);
      }
      final caFile = File(p.join(sslDir.path, 'cacert.pem'));
      if (!caFile.existsSync()) {
        onProgress?.call('🔒 Installing TLS root CA bundle for PHP & Composer...', false);
        final caBytes = await downloadBytes('https://curl.se/ca/cacert.pem');
        await caFile.writeAsBytes(caBytes);
      }
      final caPath = caFile.path.replaceAll('\\', '/');
      if (content.contains(';curl.cainfo =')) {
        content = content.replaceFirst(';curl.cainfo =', 'curl.cainfo = "$caPath"');
      } else if (!content.contains('curl.cainfo =')) {
        content += '\ncurl.cainfo = "$caPath"\n';
      }
      if (content.contains(';openssl.cafile=')) {
        content = content.replaceFirst(';openssl.cafile=', 'openssl.cafile = "$caPath"');
      } else if (!content.contains('openssl.cafile')) {
        content += '\nopenssl.cafile = "$caPath"\n';
      }
    } catch (_) {}

    await iniFile.writeAsString(content);
  }

  static Future<bool> _installComposer({
    void Function(String output, bool isError)? onProgress,
  }) async {
    if (!await _isRuntimeAvailable(RuntimeType.php)) {
      final phpOk = await ensureRuntime(RuntimeType.php, onProgress: onProgress);
      if (!phpOk) {
        onProgress?.call('✗ PHP is required before installing Composer.', true);
        return false;
      }
    }

    onProgress?.call('⬇️ Downloading composer.phar into app environment...', false);
    final bytes = await downloadBytes('https://getcomposer.org/download/latest-stable/composer.phar');
    final targetDir = Directory(p.join(getRuntimesRootDir(), 'composer'));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }

    final pharFile = File(p.join(targetDir.path, 'composer.phar'));
    await pharFile.writeAsBytes(bytes);

    if (Platform.isWindows) {
      final batFile = File(p.join(targetDir.path, 'composer.bat'));
      await batFile.writeAsString('@echo off\r\nphp "%~dp0composer.phar" %*\r\n');
    } else {
      final shFile = File(p.join(targetDir.path, 'composer'));
      await shFile.writeAsString('#!/bin/sh\nexec php "\$(dirname "\$0")/composer.phar" "\$@"\n');
      await Process.run('chmod', ['+x', shFile.path]);
    }

    onProgress?.call('✓ Portable Composer installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.composer);
  }

  static Future<bool> _installCloudflared({
    void Function(String output, bool isError)? onProgress,
  }) async {
    final targetDir = Directory(p.join(getRuntimesRootDir(), 'cloudflared'));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }

    if (Platform.isWindows) {
      onProgress?.call('⬇️ Downloading cloudflared.exe into app environment...', false);
      final bytes = await downloadBytes(
        'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe',
      );
      await File(p.join(targetDir.path, 'cloudflared.exe')).writeAsBytes(bytes);
    } else if (Platform.isMacOS) {
      final arch = await _getMacArch();
      final asset = arch == 'arm64' ? 'cloudflared-darwin-arm64.tgz' : 'cloudflared-darwin-amd64.tgz';
      onProgress?.call('⬇️ Downloading $asset into app environment...', false);
      final bytes = await downloadBytes(
        'https://github.com/cloudflare/cloudflared/releases/latest/download/$asset',
      );
      await _extractTarGz(bytes, targetDir.path);
      await _makeBinariesExecutable(targetDir.path);
    }

    onProgress?.call('✓ Portable cloudflared installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.cloudflared);
  }

  static Future<String> _fetchText(String url) async {
    final bytes = await downloadBytes(url);
    return utf8.decode(bytes);
  }

  static Future<Uint8List> downloadBytes(
    String url, {
    Map<String, String>? headers,
  }) async {
    final mergedHeaders = <String, String>{
      'User-Agent': _userAgent,
      ...?headers,
    };
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: mergedHeaders,
      );
      if (res.statusCode != 200) {
        throw Exception('Download failed ($url): HTTP ${res.statusCode}');
      }
      return res.bodyBytes;
    } on HandshakeException {
      return await _downloadBytesViaSystemCurl(url, headers: headers);
    } on TlsException {
      return await _downloadBytesViaSystemCurl(url, headers: headers);
    }
  }

  /// Falls back to the OS native `curl` (Schannel on Windows, SecureTransport on macOS)
  /// when Dart's bundled BoringSSL cannot verify a corporate/antivirus root CA.
  static Future<Uint8List> _downloadBytesViaSystemCurl(
    String url, {
    Map<String, String>? headers,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('webotapp_dl_');
    final outFile = File(p.join(tempDir.path, 'payload.bin'));
    try {
      final curlExe = Platform.isWindows ? 'curl.exe' : '/usr/bin/curl';
      final args = <String>[
        '-fsSL',
        if (Platform.isWindows) '--ssl-no-revoke',
        '-A',
        _userAgent,
        if (headers != null)
          for (final entry in headers.entries) ...['-H', '${entry.key}: ${entry.value}'],
        '-o',
        outFile.path,
        url,
      ];
      final res = await Process.run(curlExe, args);
      if (res.exitCode != 0 || !outFile.existsSync()) {
        throw Exception(
          'System curl failed for $url (exit ${res.exitCode}): ${res.stderr}',
        );
      }
      return await outFile.readAsBytes();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _extractZip(
    List<int> bytes,
    String targetDir, {
    bool stripTopLevelDir = false,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    await _writeArchive(archive, targetDir, stripTopLevelDir: stripTopLevelDir);
  }

  static Future<void> _extractTarGz(
    List<int> bytes,
    String targetDir, {
    bool stripTopLevelDir = false,
  }) async {
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);
    await _writeArchive(archive, targetDir, stripTopLevelDir: stripTopLevelDir);
  }

  static Future<void> _writeArchive(
    Archive archive,
    String targetDir, {
    bool stripTopLevelDir = false,
  }) async {
    final outRoot = Directory(targetDir);
    if (!outRoot.existsSync()) {
      await outRoot.create(recursive: true);
    }

    String? topPrefix;
    if (stripTopLevelDir && archive.isNotEmpty) {
      final first = archive.first.name;
      final slashIdx = first.indexOf('/');
      if (slashIdx != -1) {
        topPrefix = first.substring(0, slashIdx + 1);
      }
    }

    for (final entry in archive) {
      var relPath = entry.name;
      if (topPrefix != null && relPath.startsWith(topPrefix)) {
        relPath = relPath.substring(topPrefix.length);
      }
      if (relPath.isEmpty) continue;

      final destPath = p.join(targetDir, relPath);
      if (entry.isFile) {
        final outFile = File(destPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(destPath).create(recursive: true);
      }
    }
  }

  static Future<void> _makeBinariesExecutable(String dirPath) async {
    if (Platform.isWindows) return;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync()) {
      if (entity is File) {
        await Process.run('chmod', ['+x', entity.path]);
      }
    }
  }

  static Future<String> _getMacArch() async {
    if (!Platform.isMacOS) return 'x64';
    try {
      final res = await Process.run('uname', ['-m']);
      final arch = res.stdout.toString().trim();
      return arch == 'arm64' ? 'arm64' : 'x64';
    } catch (_) {
      return 'arm64';
    }
  }
}
