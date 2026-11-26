import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/projects_provider.dart';
import 'tactile_press.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final projectsProvider = context.watch<ProjectsProvider>();
    final isDark = appState.isDarkMode;

    final bgColor = isDark ? AppTheme.darkSidebar : AppTheme.lightSidebar;

    Widget navItem({
      required NavigationTab tab,
      required IconData icon,
      required String label,
      int? badgeCount,
      bool isLiveBadge = false,
    }) {
      final isSelected = appState.currentTab == tab;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: TactilePress(
          pressedScale: 0.98,
          onTap: () => appState.setTab(tab),
          child: AnimatedContainer(
            duration: AppMotion.uiDuration,
            curve: AppMotion.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryBlue.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? const Color(0xFFA5B4FC) : Colors.white60,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLiveBadge
                          ? AppTheme.successGreen.withValues(alpha: 0.2)
                          : (isSelected
                              ? AppTheme.primaryBlue.withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(10),
                      border: isLiveBadge
                          ? Border.all(color: AppTheme.successGreen.withValues(alpha: 0.45))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLiveBadge) ...[
                          const PulsingLiveDot(color: AppTheme.successGreen, size: 6),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          '$badgeCount',
                          style: AppTheme.tabularNumberStyle.copyWith(
                            color: isLiveBadge ? AppTheme.successGreen : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 248,
      color: bgColor,
      child: Column(
        children: [
          // Brand Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primaryBlue, AppTheme.primaryViolet],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WebotApp',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'GitHub Installer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                navItem(
                  tab: NavigationTab.dashboard,
                  icon: Icons.grid_view_rounded,
                  label: 'Dashboard',
                ),
                navItem(
                  tab: NavigationTab.installNew,
                  icon: Icons.add_box_outlined,
                  label: 'Install New Project',
                ),
                navItem(
                  tab: NavigationTab.myProjects,
                  icon: Icons.folder_copy_outlined,
                  label: 'My Projects',
                  badgeCount: projectsProvider.projects.length,
                ),
                navItem(
                  tab: NavigationTab.runningProjects,
                  icon: Icons.play_circle_outline_rounded,
                  label: 'Running Projects',
                  badgeCount: projectsProvider.runningCount,
                  isLiveBadge: true,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Text(
                    'DEVELOPMENT',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                navItem(
                  tab: NavigationTab.databaseManager,
                  icon: Icons.storage_rounded,
                  label: 'Database Manager',
                ),
                navItem(
                  tab: NavigationTab.runtimeManager,
                  icon: Icons.layers_outlined,
                  label: 'Runtime Manager',
                ),
                navItem(
                  tab: NavigationTab.testingCenter,
                  icon: Icons.verified_outlined,
                  label: 'Testing Center',
                ),
                navItem(
                  tab: NavigationTab.tunnelManager,
                  icon: Icons.public_rounded,
                  label: 'Tunnel Manager',
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Text(
                    'SYSTEM',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                navItem(
                  tab: NavigationTab.settings,
                  icon: Icons.tune_rounded,
                  label: 'Settings',
                ),
                navItem(
                  tab: NavigationTab.about,
                  icon: Icons.info_outline_rounded,
                  label: 'About',
                ),
              ],
            ),
          ),

          // Footer info & Theme toggle
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                TactilePress(
                  onTap: () => appState.toggleTheme(),
                  child: Tooltip(
                    message: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? AppTheme.warningOrange : const Color(0xFFA5B4FC),
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isDark ? 'Light' : 'Dark',
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'v${AppConstants.appVersion}',
                  style: AppTheme.tabularNumberStyle.copyWith(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
