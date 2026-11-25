import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/runtime_info.dart';
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
    final apiUrl = Uri.parse('https://api.github.com/repos/${parsed.owner}/${parsed.repo}');

    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'GitHub-Project-Installer-Desktop',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await http.get(apiUrl, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
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
      }
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
      home = Directory(p.join(docs.path, AppConstants.defaultProjectsFolderName));
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
      // Check if it's already a git repo
      final gitDir = Directory(p.join(targetDir, '.git'));
      if (await gitDir.exists()) {
        if (onProgress != null) {
          onProgress('Repository already cloned in $targetDir. Pulling latest...', false);
        }
        await CommandRunner.run('git', ['pull'], workingDirectory: targetDir, onLine: onProgress);
        return targetDir;
      }
    }

    if (onProgress != null) {
      onProgress('Cloning ${parsed.owner}/${parsed.repo} into $targetDir...', false);
    }

    final token = await SecureStorageService().read('github_token');
    String cloneUrl = url;
    if (token != null && token.isNotEmpty && cloneUrl.startsWith('https://')) {
      cloneUrl = cloneUrl.replaceFirst('https://', 'https://$token@');
    }

    final gitCheck = await CommandRunner.run('git', ['--version']);
    if (!gitCheck.isSuccess && PortableRuntimeManager.supportsPortableInstall(RuntimeType.git)) {
      onProgress?.call('⚙️ Git not found on system. Bootstrapping portable Git into app environment...', false);
      await PortableRuntimeManager.ensureRuntime(RuntimeType.git, onProgress: onProgress);
    }

    final result = await CommandRunner.run(
      'git',
      [
        if (Platform.isWindows) ...['-c', 'http.sslBackend=schannel'],
        'clone',
        '--depth',
        '1',
        cloneUrl,
        targetDir,
      ],
      onLine: onProgress,
    );

    if (!result.isSuccess && !await directory.exists()) {
      // Automatic fallback: Download and extract GitHub repository ZIP directly without Git
      await _downloadAndExtractZip(
        parsed.owner,
        parsed.repo,
        targetDir,
        token: token,
        onProgress: onProgress,
      );
    }

    return targetDir;
  }

  static Future<void> _downloadAndExtractZip(
    String owner,
    String repo,
    String targetDir, {
    String? token,
    void Function(String output, bool isError)? onProgress,
  }) async {
    onProgress?.call('📦 Git command not available. Downloading repository ZIP archive from GitHub...', false);

    final headers = <String, String>{
      'User-Agent': 'WebotApp-Universal-GitHub-Installer',
      if (token != null && token.isNotEmpty) 'Authorization': 'token $token',
    };

    final candidateUrls = [
      'https://github.com/$owner/$repo/archive/refs/heads/main.zip',
      'https://github.com/$owner/$repo/archive/refs/heads/master.zip',
      'https://api.github.com/repos/$owner/$repo/zipball',
    ];

    List<int>? zipBytes;
    final failureReasons = <String>[];
    for (final candidate in candidateUrls) {
      try {
        final bytes = await PortableRuntimeManager.downloadBytes(
          candidate,
          headers: headers,
        );
        if (bytes.isNotEmpty) {
          zipBytes = bytes;
          break;
        }
      } catch (e) {
        failureReasons.add('$e ($candidate)');
      }
    }

    if (zipBytes == null) {
      final has404 = failureReasons.any((r) => r.contains('HTTP 404'));
      final hint = has404 && (token == null || token.isEmpty)
          ? ' If this is a private repository, add a GitHub Personal Access Token in Settings.'
          : '';
      throw Exception(
        'Could not clone via Git and could not download ZIP archive from GitHub (${failureReasons.join("; ")}).$hint',
      );
    }

    onProgress?.call('⚡ Extracting project files into $targetDir...', false);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final targetDirObj = Directory(targetDir);
    if (!await targetDirObj.exists()) {
      await targetDirObj.create(recursive: true);
    }

    String? rootPrefix;
    if (archive.isNotEmpty) {
      final first = archive.first.name;
      final slashIdx = first.indexOf('/');
      if (slashIdx != -1) {
        rootPrefix = first.substring(0, slashIdx + 1);
      }
    }

    for (final file in archive) {
      var relativePath = file.name;
      if (rootPrefix != null && relativePath.startsWith(rootPrefix)) {
        relativePath = relativePath.substring(rootPrefix.length);
      }
      if (relativePath.isEmpty) continue;

      final filePath = p.join(targetDir, relativePath);
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }

    onProgress?.call('✓ Repository downloaded and unpacked successfully without Git!', false);
  }
}

