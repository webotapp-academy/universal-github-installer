import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../state/projects_provider.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/sidebar.dart';
import 'about_screen.dart';
import 'dashboard_screen.dart';
import 'database_screen.dart';
import 'install_screen.dart';
import 'projects_screen.dart';
import 'running_screen.dart';
import 'runtime_screen.dart';
import 'settings_screen.dart';
import 'testing_screen.dart';
import 'tunnel_screen.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final projectsProvider = context.watch<ProjectsProvider>();

    Widget getActiveScreen() {
      switch (appState.currentTab) {
        case NavigationTab.dashboard:
          return const DashboardScreen();
        case NavigationTab.installNew:
          return const InstallScreen();
        case NavigationTab.myProjects:
          return const ProjectsScreen();
        case NavigationTab.runningProjects:
          return const RunningScreen();
        case NavigationTab.databaseManager:
          return const DatabaseScreen();
        case NavigationTab.runtimeManager:
          return const RuntimeScreen();
        case NavigationTab.testingCenter:
          return const TestingScreen();
        case NavigationTab.tunnelManager:
          return const TunnelScreen();
        case NavigationTab.settings:
          return const SettingsScreen();
        case NavigationTab.about:
          return const AboutScreen();
      }
    }

    final showGlobalBanner =
        projectsProvider.isBusy && appState.currentTab != NavigationTab.installNew;

    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.white10),
          Expanded(
            child: Column(
              children: [
                if (showGlobalBanner)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: AppTheme.primaryBlue.withValues(alpha: 0.18),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            projectsProvider.installStageLabel.isNotEmpty
                                ? projectsProvider.installStageLabel
                                : 'Repository operation in progress...',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('View Progress'),
                          onPressed: () => appState.setTab(NavigationTab.installNew),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: getActiveScreen()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

