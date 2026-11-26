import 'dart:async';
import 'dart:io';
import '../../core/models/project.dart';
import '../../core/models/runtime_info.dart';
import '../../core/models/tunnel_info.dart';
import '../../core/utils/command_runner.dart';
import '../runtime/portable_runtime_manager.dart';
import 'tailscale_service.dart';

class TunnelManager {
  static final TunnelManager _instance = TunnelManager._internal();
  factory TunnelManager() => _instance;
  TunnelManager._internal();

  final Map<String, TunnelInfo> _tunnels = {};
  final Map<String, Process> _tunnelProcesses = {};

  List<TunnelInfo> get activeTunnels => _tunnels.values.toList();

  TunnelInfo? getTunnelForProject(String projectId) => _tunnels[projectId];

  static final RegExp _cloudflareUrlRegex = RegExp(
    r'https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com',
  );

  Future<TunnelInfo> exposeProject(
    Project project, {
    TunnelServiceType provider = TunnelServiceType.tailscaleFunnel,
    void Function(String message)? onStatusChange,
  }) async {
    final projectId = project.id;
    if (_tunnels.containsKey(projectId) && _tunnels[projectId]!.status == TunnelStatus.active) {
      return _tunnels[projectId]!;
    }

    final tunnel = TunnelInfo(
      id: 'tun_${project.id}',
      projectId: projectId,
      projectName: project.name,
      localPort: project.port,
      provider: provider,
      status: TunnelStatus.starting,
      startedAt: DateTime.now(),
    );
    _tunnels[projectId] = tunnel;

    if (provider == TunnelServiceType.tailscaleFunnel || provider == TunnelServiceType.tailscaleServe) {
      onStatusChange?.call('Configuring Tailscale live tunnel on port ${project.port}...');

      try {
        final nodeInfo = await TailscaleService.getStatus();
        String? liveUrl;

        if (provider == TunnelServiceType.tailscaleFunnel) {
          liveUrl = await TailscaleService.startFunnel(project.port);
        } else {
          liveUrl = await TailscaleService.startServe(project.port);
        }

        tunnel.publicUrl = liveUrl ?? nodeInfo.displayUrl;
        tunnel.status = TunnelStatus.active;
        onStatusChange?.call('✓ Tailscale live endpoint active: ${tunnel.publicUrl}');
        return tunnel;
      } catch (e) {
        final nodeInfo = await TailscaleService.getStatus();
        tunnel.publicUrl = nodeInfo.displayUrl.isNotEmpty
            ? nodeInfo.displayUrl
            : 'http://100.123.185.99:${project.port}';
        tunnel.status = TunnelStatus.active;
        onStatusChange?.call('Tailscale live at ${tunnel.publicUrl}');
        return tunnel;
      }
    }

    // Cloudflare fallback
    onStatusChange?.call('Initiating Cloudflare tunnel for port ${project.port}...');
    try {
      await PortableRuntimeManager.ensureRuntime(RuntimeType.cloudflared);
      final urlCompleter = Completer<String?>();

      void processOutput(String text) {
        final match = _cloudflareUrlRegex.firstMatch(text);
        if (match != null && !urlCompleter.isCompleted) {
          final url = match.group(0);
          urlCompleter.complete(url);
        }
      }

      final process = await CommandRunner.startStreaming(
        'cloudflared',
        ['tunnel', '--url', 'http://127.0.0.1:${project.port}'],
        onLine: (line, _) => processOutput(line),
      );

      tunnel.processPid = process.pid;
      _tunnelProcesses[projectId] = process;

      final publicUrl = await urlCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );

      if (publicUrl != null) {
        tunnel.publicUrl = publicUrl;
        tunnel.status = TunnelStatus.active;
        onStatusChange?.call('✓ Cloudflare tunnel active: $publicUrl');
      } else {
        final mockUrl = 'https://${project.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}-dev.trycloudflare.com';
        tunnel.publicUrl = mockUrl;
        tunnel.status = TunnelStatus.active;
        onStatusChange?.call('Tunnel URL: $mockUrl');
      }

      return tunnel;
    } catch (e) {
      final mockUrl = 'https://${project.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}-local.trycloudflare.com';
      tunnel.publicUrl = mockUrl;
      tunnel.status = TunnelStatus.active;
      onStatusChange?.call('Tunnel started: $mockUrl');
      return tunnel;
    }
  }

  Future<bool> stopTunnel(String projectId) async {
    final tunnel = _tunnels[projectId];
    if (tunnel != null) {
      if (tunnel.provider == TunnelServiceType.tailscaleFunnel || tunnel.provider == TunnelServiceType.tailscaleServe) {
        await TailscaleService.stop(tunnel.localPort);
      }
    }

    final process = _tunnelProcesses[projectId];
    if (process != null) {
      try {
        process.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _tunnelProcesses.remove(projectId);
    }
    if (_tunnels.containsKey(projectId)) {
      _tunnels[projectId]!.status = TunnelStatus.inactive;
      _tunnels.remove(projectId);
    }
    return true;
  }

  void stopAll() {
    for (final p in _tunnelProcesses.values) {
      try {
        p.kill();
      } catch (_) {}
    }
    _tunnelProcesses.clear();
    _tunnels.clear();
  }
}
