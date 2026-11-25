import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/utils/command_runner.dart';
import '../runtime/portable_runtime_manager.dart';

class RepoMetadata {
  final String owner;
  final String name;
  final String fullName;
  final String defaultBranch;
  final String? description;
  final int stars;
  final int forks;
  final bool isPrivate;

  RepoMetadata({
    required this.owner,
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    this.description,
    this.stars = 0,
    this.forks = 0,
    this.isPrivate = false,
  });
}

class GitHubService {
  static final RegExp _repoRegex = RegExp(
    r'github\.com[/:]([a-zA-Z0-9_\-\.]+)/([a-zA-Z0-9_\-\.]+)(?:\.git)?',
  );

  static bool isValidGitHubUrl(String url) {
    return _repoRegex.hasMatch(url.trim());
  }

  static ({String owner, String repo})? parseUrl(String url) {
    final match = _repoRegex.firstMatch(url.trim());
    if (match == null) return null;
    var repo = match.group(2)!;
    if (repo.endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }
    return (owner: match.group(1)!, repo: repo);
  }

  static Future<RepoMetadata?> fetchMetadata(String url) async {
    final parsed = parseUrl(url);
    if (parsed == null) return null;

    final token = await SecureStorageService().read('github_token');
    final apiUrl = 'https://api.github.com/repos/${parsed.owner}/${parsed.repo}';

    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'GitHub-Project-Installer-Desktop',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final bytes = await PortableRuntimeManager.downloadBytes(
        apiUrl,
        headers: headers,
      );
      final data = jsonDecode(utf8.decode(bytes));
      return RepoMetadata(
        owner: data['owner']['login'] ?? parsed.owner,
        name: data['name'] ?? parsed.repo,
        fullName: data['full_name'] ?? '${parsed.owner}/${parsed.repo}',
        defaultBranch: data['default_branch'] ?? 'main',
        description: data['description'],
        stars: data['stargazers_count'] ?? 0,
        forks: data['forks_count'] ?? 0,
        isPrivate: data['private'] ?? false,
      );
    } catch (_) {}

    // Fallback if API rate-limited or offline
    return RepoMetadata(
      owner: parsed.owner,
      name: parsed.repo,
      fullName: '${parsed.owner}/${parsed.repo}',
      defaultBranch: 'main',
    );
  }

  static Future<String> getProjectsDirectory() async {
    Directory home;
    try {
      final docs = await getApplicationDocumentsDirectory();
      // Avoid OneDrive Known-Folder-Move paths on Windows, which lock node_modules/vendor files during sync
      if (Platform.isWindows && docs.path.toLowerCase().contains(r'\onedrive\')) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        home = Directory(p.join(
          userProfile.isNotEmpty ? userProfile : docs.path,
          AppConstants.defaultProjectsFolderName,
        ));
      } else {
        home = Directory(p.join(docs.path, AppConstants.defaultProjectsFolderName));
      }
    } catch (_) {
      final homePath = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      home = Directory(p.join(homePath, AppConstants.defaultProjectsFolderName));
    }
    if (!await home.exists()) {
      await home.create(recursive: true);
    }
    return home.path;
  }

  static Future<String> cloneRepository(
    String url, {
    String? customPath,
    void Function(String output, bool isError)? onProgress,
  }) async {
    final parsed = parseUrl(url);
    if (parsed == null) {
      throw Exception('Invalid GitHub URL: $url');
    }

    final targetDir = customPath ?? p.join(await getProjectsDirectory(), parsed.repo);
    final directory = Directory(targetDir);

    if (await directory.exists()) {
      final gitDir = Directory(p.join(targetDir, '.git'));
      if (await gitDir.exists()) {
        final gitCheck = await CommandRunner.run('git', ['--version'], timeout: const Duration(seconds: 10));
        if (gitCheck.isSuccess) {
          onProgress?.call('Repository already cloned in $targetDir. Pulling latest...', false);
          await CommandRunner.run(
            'git',
            [
              if (Platform.isWindows) ...[
                '-c',
                'http.sslBackend=schannel',
                '-c',
                'http.schannelCheckRevoke=false',
              ],
              'pull',
            ],
            workingDirectory: targetDir,
            onLine: onProgress,
            timeout: const Duration(seconds: 60),
          );
          return targetDir;
        }
      }

      // If existing directory has project files (e.g. from previous ZIP download), use it;
      // if empty/partial from an aborted clone, delete it so fresh download succeeds.
      final entries = directory.listSync();
      if (entries.isNotEmpty) {
        onProgress?.call('Repository already present in $targetDir.', false);
        return targetDir;
      }
      await directory.delete(recursive: true);
    }

    final metadata = await fetchMetadata(url);
    final defaultBranch = metadata?.defaultBranch ?? 'main';

    final token = await SecureStorageService().read('github_token');
    String cloneUrl = url;
    if (token != null && token.isNotEmpty && cloneUrl.startsWith('https://')) {
      cloneUrl = cloneUrl.replaceFirst('https://', 'https://$token@');
    }

    final gitCheck = await CommandRunner.run('git', ['--version'], timeout: const Duration(seconds: 10));
    if (gitCheck.isSuccess) {
      onProgress?.call('Cloning ${parsed.owner}/${parsed.repo} into $targetDir...', false);
      final result = await CommandRunner.run(
        'git',
        [
          if (Platform.isWindows) ...[
            '-c',
            'http.sslBackend=schannel',
            '-c',
            'http.schannelCheckRevoke=false',
          ],
          if (token == null || token.isEmpty) ...['-c', 'credential.helper='],
          'clone',
          '--depth',
          '1',
          '--progress',
          cloneUrl,
          targetDir,
        ],
        onLine: onProgress,
        timeout: const Duration(seconds: 75),
      );

      if (result.isSuccess && await directory.exists()) {
        return targetDir;
      }

      // Clean up any partial directory left behind by a failed/timed-out clone before ZIP fallback
      if (await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
      onProgress?.call('⚠️ Git clone did not complete. Falling back to direct ZIP archive download...', false);
    }

    // Direct ZIP download path (fast, zero-dependency, uses OS curl TLS fallback)
    await _downloadAndExtractZip(
      parsed.owner,
      parsed.repo,
      targetDir,
      defaultBranch: defaultBranch,
      token: token,
      onProgress: onProgress,
    );

    return targetDir;
  }

  static Future<void> _downloadAndExtractZip(
    String owner,
    String repo,
    String targetDir, {
    String defaultBranch = 'main',
    String? token,
    void Function(String output, bool isError)? onProgress,
  }) async {
    onProgress?.call('📦 Downloading repository ZIP archive from GitHub...', false);

    final headers = <String, String>{
      'User-Agent': 'WebotApp-Universal-GitHub-Installer',
      if (token != null && token.isNotEmpty) 'Authorization': 'token $token',
    };

    final candidateUrls = <String>{
      if (token != null && token.isNotEmpty)
        'https://api.github.com/repos/$owner/$repo/zipball/$defaultBranch',
      'https://github.com/$owner/$repo/archive/refs/heads/$defaultBranch.zip',
      'https://github.com/$owner/$repo/archive/refs/heads/main.zip',
      'https://github.com/$owner/$repo/archive/refs/heads/master.zip',
      'https://api.github.com/repos/$owner/$repo/zipball',
    }.toList();

    final tempDir = await Directory.systemTemp.createTemp('webotapp_repo_');
    final zipFile = File(p.join(tempDir.path, '$repo.zip'));

    try {
      bool downloaded = false;
      final failureReasons = <String>[];

      for (final candidate in candidateUrls) {
        try {
          await PortableRuntimeManager.downloadToFile(
            candidate,
            zipFile.path,
            headers: headers,
            onProgress: onProgress,
          );
          if (zipFile.existsSync() && zipFile.lengthSync() > 0) {
            downloaded = true;
            break;
          }
        } catch (e) {
          failureReasons.add('$e ($candidate)');
        }
      }

      if (!downloaded) {
        final has404 = failureReasons.any((r) => r.contains('HTTP 404'));
        final hint = has404 && (token == null || token.isEmpty)
            ? ' If this is a private repository, add a GitHub Personal Access Token in Settings.'
            : '';
        throw Exception(
          'Could not download repository from GitHub (${failureReasons.join("; ")}).$hint',
        );
      }

      onProgress?.call('⚡ Extracting project files into $targetDir...', false);
      await PortableRuntimeManager.extractArchiveFile(
        zipFile.path,
        targetDir,
        isZip: true,
        stripTopLevelDir: true,
      );
      onProgress?.call('✓ Repository downloaded and unpacked successfully!', false);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

