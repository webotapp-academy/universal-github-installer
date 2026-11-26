import 'package:flutter/material.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/theme/app_theme.dart';
import 'tactile_press.dart';

class StatusBadge extends StatelessWidget {
  final ProjectState status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case ProjectState.running:
        bg = AppTheme.successGreen.withValues(alpha: 0.14);
        fg = AppTheme.successGreen;
        label = 'RUNNING';
        icon = Icons.play_circle_fill;
        break;
      case ProjectState.ready:
        bg = AppTheme.primaryBlue.withValues(alpha: 0.14);
        fg = const Color(0xFF818CF8);
        label = 'READY';
        icon = Icons.check_circle_rounded;
        break;
      case ProjectState.starting:
        bg = AppTheme.warningOrange.withValues(alpha: 0.14);
        fg = AppTheme.warningOrange;
        label = 'STARTING';
        icon = Icons.hourglass_top_rounded;
        break;
      case ProjectState.stopping:
        bg = AppTheme.warningOrange.withValues(alpha: 0.14);
        fg = AppTheme.warningOrange;
        label = 'STOPPING';
        icon = Icons.pause_circle_filled;
        break;
      case ProjectState.installing:
      case ProjectState.cloning:
      case ProjectState.analyzing:
        bg = AppTheme.accentCyan.withValues(alpha: 0.14);
        fg = AppTheme.accentCyan;
        label = status.name.toUpperCase();
        icon = Icons.sync_rounded;
        break;
      case ProjectState.error:
        bg = AppTheme.errorRed.withValues(alpha: 0.14);
        fg = AppTheme.errorRed;
        label = 'ERROR';
        icon = Icons.error_rounded;
        break;
      case ProjectState.notInstalled:
        bg = Colors.grey.withValues(alpha: 0.14);
        fg = Colors.grey;
        label = 'NOT INSTALLED';
        icon = Icons.download_rounded;
        break;
    }

    return AnimatedContainer(
      duration: AppMotion.uiDuration,
      curve: AppMotion.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ProjectState.running)
            PulsingLiveDot(color: fg, size: 7)
          else
            Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            softWrap: false,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
