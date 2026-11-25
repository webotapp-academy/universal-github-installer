import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'state/app_state.dart';
import 'state/process_provider.dart';
import 'state/projects_provider.dart';
import 'state/runtime_provider.dart';
import 'state/tunnel_provider.dart';
import 'ui/screens/main_layout.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final projectsProvider = ProjectsProvider();
  final runtimeProvider = RuntimeProvider();

  // Pre-load projects and detected runtimes in background
  await projectsProvider.loadProjects();
  runtimeProvider.refresh();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider.value(value: projectsProvider),
        ChangeNotifierProvider(create: (_) => ProcessProvider()),
        ChangeNotifierProvider.value(value: runtimeProvider),
        ChangeNotifierProvider(create: (_) => TunnelProvider()),
      ],
      child: const GitHubInstallerApp(),
    ),
  );
}

class GitHubInstallerApp extends StatelessWidget {
  const GitHubInstallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const MainLayout(),
    );
  }
}
