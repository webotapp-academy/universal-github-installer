import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_installer/core/models/runtime_info.dart';
import 'package:github_installer/services/runtime/portable_runtime_manager.dart';

void main() {
  group('PortableRuntimeManager', () {
    test('returns a non-empty runtimes root directory', () {
      final root = PortableRuntimeManager.getRuntimesRootDir();
      expect(root, isNotEmpty);
      expect(root.endsWith('runtimes'), isTrue);
    });

    test('supports portable install for core cross-platform runtimes', () {
      if (Platform.isWindows) {
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.git), isTrue);
      }
      if (Platform.isWindows || Platform.isMacOS) {
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.node), isTrue);
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.npm), isTrue);
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.uv), isTrue);
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.php), isTrue);
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.composer), isTrue);
        expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.cloudflared), isTrue);
      }
      expect(PortableRuntimeManager.supportsPortableInstall(RuntimeType.docker), isFalse);
    });

    test('getManagedBinDirectories returns only existing directories', () {
      final dirs = PortableRuntimeManager.getManagedBinDirectories();
      for (final dir in dirs) {
        expect(Directory(dir).existsSync(), isTrue);
      }
    });
  });
}
