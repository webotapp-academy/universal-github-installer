import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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
      if ((type == RuntimeType.node || type == RuntimeType.npm)) {
        final managedNodeDir = p.join(getRuntimesRootDir(), 'node');
        final marker = File(p.join(managedNodeDir, '.use_system_ca'));
        if (Directory(managedNodeDir).existsSync() && !marker.existsSync()) {
          try {
            final caCheck = await CommandRunner.run('node', ['--use-system-ca', '--version']);
            if (caCheck.isSuccess) await marker.writeAsString('1');
          } catch (_) {}
        }
      }
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
      final res = await CommandRunner.run(
        cmd,
        ['--version'],
        timeout: const Duration(seconds: 15),
      );
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Upgrades the app-managed PHP runtime to the latest 8.4+ build when an older
  /// cached PHP version (e.g. 8.3) does not satisfy a project's composer.lock.
  static Future<bool> upgradePortablePhp({
    void Function(String output, bool isError)? onProgress,
  }) async {
    onProgress?.call('⬆️ Upgrading app-managed PHP to 8.4+...', false);
    return await _installPhp(onProgress: onProgress);
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
    final targetDir = p.join(getRuntimesRootDir(), 'git');
    await _downloadAndExtract(
      downloadUrl,
      targetDir,
      isZip: true,
      onProgress: onProgress,
    );
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
    final targetDir = p.join(getRuntimesRootDir(), 'node');

    await _downloadAndExtract(
      url,
      targetDir,
      isZip: Platform.isWindows,
      stripTopLevelDir: true,
      onProgress: onProgress,
    );

    if (!Platform.isWindows) {
      await _makeBinariesExecutable(p.join(targetDir, 'bin'));
    }

    // Enable system CA store for Node v22.15+ so npm works behind corporate/antivirus CAs
    try {
      final caCheck = await CommandRunner.run('node', ['--use-system-ca', '--version']);
      if (caCheck.isSuccess) {
        await File(p.join(targetDir, '.use_system_ca')).writeAsString('1');
      }
    } catch (_) {}

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
    final targetDir = p.join(getRuntimesRootDir(), 'uv');

    await _downloadAndExtract(
      url,
      targetDir,
      isZip: Platform.isWindows,
      stripTopLevelDir: !Platform.isWindows,
      onProgress: onProgress,
    );
    if (!Platform.isWindows) {
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
      for (final versionKey in ['8.4', '8.5', '8.3', '8.2']) {
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
      await _downloadAndExtract(
        url,
        targetDir,
        isZip: true,
        onProgress: onProgress,
      );
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
          'https://dl.static-php.dev/static-php-cli/common/php-8.4.23-cli-macos-$spcArch.tar.gz';
      onProgress?.call('⬇️ Downloading static PHP 8.4 for macOS ($spcArch)...', false);
      await _downloadAndExtract(
        url,
        targetDir,
        isZip: false,
        onProgress: onProgress,
      );
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
    final bytes = await downloadBytes(
      'https://getcomposer.org/download/latest-stable/composer.phar',
      onProgress: onProgress,
    );
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
      await _downloadAndExtract(
        'https://github.com/cloudflare/cloudflared/releases/latest/download/$asset',
        targetDir.path,
        isZip: false,
        onProgress: onProgress,
      );
      await _makeBinariesExecutable(targetDir.path);
    }

    onProgress?.call('✓ Portable cloudflared installed in app environment.', false);
    return await _isRuntimeAvailable(RuntimeType.cloudflared);
  }

  static Future<String> _fetchText(String url) async {
    final bytes = await downloadBytes(url);
    return utf8.decode(bytes);
  }

  static Future<void> _downloadAndExtract(
    String url,
    String targetDir, {
    required bool isZip,
    bool stripTopLevelDir = false,
    void Function(String output, bool isError)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('webotapp_pkg_');
    final archiveFile = File(p.join(tempDir.path, isZip ? 'pkg.zip' : 'pkg.tar.gz'));
    try {
      await downloadToFile(url, archiveFile.path, onProgress: onProgress);
      onProgress?.call('📦 Extracting package into app environment...', false);
      await _extractArchiveFile(
        archiveFile.path,
        targetDir,
        isZip: isZip,
        stripTopLevelDir: stripTopLevelDir,
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<Uint8List> downloadBytes(
    String url, {
    Map<String, String>? headers,
    void Function(String output, bool isError)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('webotapp_bytes_');
    final outFile = File(p.join(tempDir.path, 'payload.bin'));
    try {
      await downloadToFile(url, outFile.path, headers: headers, onProgress: onProgress);
      return await outFile.readAsBytes();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> downloadToFile(
    String url,
    String destPath, {
    Map<String, String>? headers,
    void Function(String output, bool isError)? onProgress,
  }) async {
    final mergedHeaders = <String, String>{
      'User-Agent': _userAgent,
      ...?headers,
    };
    final outFile = File(destPath);
    await outFile.parent.create(recursive: true);

    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))..headers.addAll(mergedHeaders);
      final streamed = await client.send(request).timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) {
        throw Exception('Download failed ($url): HTTP ${streamed.statusCode}');
      }

      sink = outFile.openWrite();
      final total = streamed.contentLength ?? 0;
      int downloaded = 0;
      int nextPercentLog = 25;

      await for (final chunk in streamed.stream.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (onProgress != null && total > 0) {
          final pct = ((downloaded * 100) ~/ total);
          if (pct >= nextPercentLog) {
            final mbDone = (downloaded / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
            onProgress('   ↳ $pct% ($mbDone / $mbTotal MB)', false);
            while (nextPercentLog <= pct) {
              nextPercentLog += 25;
            }
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on HandshakeException {
      await sink?.close();
      await _downloadFileViaSystemCurl(url, destPath, headers: headers, onProgress: onProgress);
    } on TlsException {
      await sink?.close();
      await _downloadFileViaSystemCurl(url, destPath, headers: headers, onProgress: onProgress);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
    }
  }

  /// Falls back to the OS native `curl` (Schannel on Windows, SecureTransport on macOS)
  /// when Dart's bundled BoringSSL cannot verify a corporate/antivirus root CA.
  static Future<void> _downloadFileViaSystemCurl(
    String url,
    String destPath, {
    Map<String, String>? headers,
    void Function(String output, bool isError)? onProgress,
  }) async {
    final outFile = File(destPath);
    final curlExe = Platform.isWindows ? 'curl.exe' : '/usr/bin/curl';
    final args = <String>[
      '-fsSL',
      '--connect-timeout',
      '15',
      '--max-time',
      '240',
      if (Platform.isWindows) '--ssl-no-revoke',
      '-A',
      _userAgent,
      if (headers != null)
        for (final entry in headers.entries) ...['-H', '${entry.key}: ${entry.value}'],
      '-o',
      destPath,
      url,
    ];

    final process = await Process.start(curlExe, args, runInShell: false);
    final stderrBuf = StringBuffer();
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(stderrBuf.write);

    int lastLoggedMb = -1;
    Timer? progressTimer;
    if (onProgress != null) {
      progressTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        try {
          if (outFile.existsSync()) {
            final bytes = outFile.lengthSync();
            final mb = bytes ~/ (1024 * 1024);
            if (mb > lastLoggedMb && bytes > 0) {
              lastLoggedMb = mb;
              final mbStr = (bytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress('   ↳ Downloaded $mbStr MB...', false);
            }
          }
        } catch (_) {}
      });
    }

    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 250),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -2;
        },
      );
      if (exitCode != 0 || !outFile.existsSync()) {
        throw Exception(
          'System curl failed for $url (exit $exitCode): $stderrBuf',
        );
      }
    } finally {
      progressTimer?.cancel();
    }
  }

  static Future<void> _extractArchiveFile(
    String archivePath,
    String targetDir, {
    required bool isZip,
    bool stripTopLevelDir = false,
  }) async {
    final dir = Directory(targetDir);
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    await dir.create(recursive: true);

    // Prefer fast native OS archive tools (Windows bsdtar / macOS tar+unzip)
    if (Platform.isWindows) {
      final args = <String>[
        '-xf',
        archivePath,
        '-C',
        targetDir,
        if (stripTopLevelDir) '--strip-components=1',
      ];
      final res = await Process.run('tar.exe', args).timeout(const Duration(minutes: 2));
      if (res.exitCode == 0) {
        return;
      }
    } else if (!isZip) {
      final args = <String>[
        '-xzf',
        archivePath,
        '-C',
        targetDir,
        if (stripTopLevelDir) '--strip-components=1',
      ];
      final res = await Process.run('/usr/bin/tar', args).timeout(const Duration(minutes: 2));
      if (res.exitCode == 0) {
        return;
      }
    }

    // Fallback: extract in background isolate via Dart archive package
    await Isolate.run(() {
      final bytes = File(archivePath).readAsBytesSync();
      final Archive archive = isZip
          ? ZipDecoder().decodeBytes(bytes)
          : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      _writeArchiveSync(archive, targetDir, stripTopLevelDir: stripTopLevelDir);
    });
  }

  static void _writeArchiveSync(
    Archive archive,
    String targetDir, {
    bool stripTopLevelDir = false,
  }) {
    final outRoot = Directory(targetDir);
    if (!outRoot.existsSync()) {
      outRoot.createSync(recursive: true);
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
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(destPath).createSync(recursive: true);
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
