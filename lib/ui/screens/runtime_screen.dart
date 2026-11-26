import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/process_status.dart';
import '../../core/models/runtime_info.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/command_runner.dart';
import '../../services/runtime/portable_runtime_manager.dart';
import '../../state/runtime_provider.dart';
import '../widgets/tactile_press.dart';
import '../widgets/terminal_view.dart';

class RuntimeScreen extends StatefulWidget {
  const RuntimeScreen({super.key});

  @override
  State<RuntimeScreen> createState() => _RuntimeScreenState();
}

class _RuntimeScreenState extends State<RuntimeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RuntimeProvider>().refresh();
    });
  }

  void _copyCommand(String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $cmd'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _directInstall(RuntimeInfo info, String commandStr) async {
    final logs = <LogEntry>[];
    bool isDone = false;
    String status = 'Installing ${info.type.displayName}...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.download, color: AppTheme.accentCyan),
                  const SizedBox(width: 10),
                  Text('Install ${info.type.displayName}'),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Running command: $commandStr',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TerminalView(
                        title: 'Live Installation Log',
                        logs: logs,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isDone)
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close & Refresh'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    final isPortable = PortableRuntimeManager.supportsPortableInstall(info.type);
    if (isPortable) {
      await PortableRuntimeManager.ensureRuntime(
        info.type,
        onProgress: (line, isError) {
          logs.add(LogEntry(
            timestamp: DateTime.now(),
            text: line,
            isError: isError,
          ));
        },
      );
    } else {
      final parts = commandStr.split(' ');
      final cmd = parts.first;
      final args = parts.sublist(1);

      await CommandRunner.run(
        cmd,
        args,
        onLine: (line, isError) {
          logs.add(LogEntry(
            timestamp: DateTime.now(),
            text: line,
            isError: isError,
          ));
        },
      );
    }

    status = 'Finished executing install script for ${info.type.displayName}';
    isDone = true;

    if (mounted) {
      await context.read<RuntimeProvider>().refresh();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RuntimeProvider>();
    final isWin = Platform.isWindows;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Runtime & Dependency Manager',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${provider.installedCount} installed • ${provider.missingCount} missing runtimes detected on this system',
                        style: AppTheme.tabularNumberStyle.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                TactilePress(
                  onTap: provider.isLoading ? null : () => provider.refresh(),
                  child: ElevatedButton.icon(
                    icon: provider.isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Rescan System'),
                    onPressed: provider.isLoading ? null : () => provider.refresh(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (provider.isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else
              ...provider.runtimes.map((r) {
                final installCmd = isWin ? r.installCommandWindows : r.installCommandMac;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          r.isInstalled ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: r.isInstalled ? AppTheme.successGreen : AppTheme.warningOrange,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.type.displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Tooltip(
                                message: r.isInstalled ? (r.binaryPath ?? '') : 'Not found in system PATH',
                                child: Text(
                                  r.isInstalled
                                      ? '${r.version ?? "Installed"} • Binary: ${r.binaryPath}'
                                      : 'Not found in system PATH',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: r.isInstalled
                                        ? Theme.of(context).textTheme.bodyMedium?.color
                                        : AppTheme.warningOrange,
                                    fontSize: 12,
                                    fontFamily: r.isInstalled ? 'monospace' : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (installCmd != null) ...[
                          const SizedBox(width: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TactilePress(
                                onTap: () => _directInstall(r, installCmd),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: r.isInstalled
                                        ? AppTheme.primaryBlue.withValues(alpha: 0.14)
                                        : AppTheme.primaryBlue,
                                    foregroundColor: r.isInstalled ? AppTheme.accentCyan : Colors.white,
                                  ),
                                  icon: const Icon(Icons.download, size: 14),
                                  label: Text(r.isInstalled ? 'Reinstall' : 'Install Now'),
                                  onPressed: () => _directInstall(r, installCmd),
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text('Copy Cmd', style: TextStyle(fontSize: 11)),
                                onPressed: () => _copyCommand(installCmd),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
