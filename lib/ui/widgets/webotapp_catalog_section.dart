import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/theme/app_theme.dart';
import '../../services/catalog/webotapp_catalog_service.dart';
import '../../state/app_state.dart';
import '../../state/projects_provider.dart';

class WebotAppCatalogSection extends StatefulWidget {
  const WebotAppCatalogSection({super.key});

  @override
  State<WebotAppCatalogSection> createState() => _WebotAppCatalogSectionState();
}

class _WebotAppCatalogSectionState extends State<WebotAppCatalogSection> {
  List<CatalogSoftware> _catalog = WebotAppCatalogService.defaultCatalog;
  String _selectedFilter = 'All';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLiveCatalog();
  }

  Future<void> _loadLiveCatalog() async {
    setState(() => _isLoading = true);
    final list = await WebotAppCatalogService.fetchCatalog();
    if (mounted) {
      setState(() {
        _catalog = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final projectsProvider = context.watch<ProjectsProvider>();
    final isDark = appState.isDarkMode;

    final installedNames = projectsProvider.projects
        .where((p) => p.status != ProjectState.error && p.status != ProjectState.notInstalled)
        .map((p) => p.name.toLowerCase())
        .toSet();

    final filteredList = _catalog.where((item) {
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Laravel') {
        return item.techStack.contains('Laravel') || item.category.contains('Laravel');
      }
      if (_selectedFilter == 'Healthcare') {
        return item.category.contains('Healthcare') || item.category.contains('Rehabilitation') || item.category.contains('Special');
      }
      if (_selectedFilter == 'Education') {
        return item.category.contains('Education');
      }
      if (_selectedFilter == 'Retail / POS') {
        return item.category.contains('POS') || item.category.contains('Retail');
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.hub_outlined, color: AppTheme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'WebotApp Academy Software Catalog',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Explore, install, and run production-ready software solutions with automated 1-click deployment.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh software catalog from GitHub',
                onPressed: _loadLiveCatalog,
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Laravel', 'Healthcare', 'Education', 'Retail / POS'].map((filter) {
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.25),
                  checkmarkColor: AppTheme.primaryBlue,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  onSelected: (val) {
                    setState(() => _selectedFilter = filter);
                  },
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // Software Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                mainAxisExtent: 185,
              ),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final item = filteredList[index];
                final isInstalled = installedNames.contains(item.name.toLowerCase()) ||
                    installedNames.contains(item.id.toLowerCase());

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isInstalled
                          ? AppTheme.successGreen.withValues(alpha: 0.4)
                          : (isDark ? Colors.white10 : Colors.black12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(item.icon, color: AppTheme.primaryBlue, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.category,
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isInstalled)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.successGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 12, color: AppTheme.successGreen),
                                    const SizedBox(width: 4),
                                    Text('Installed', style: TextStyle(color: AppTheme.successGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.techStack,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isInstalled)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_forward, size: 14),
                                label: const Text('View Project', style: TextStyle(fontSize: 11.5)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                onPressed: () {
                                  final match = projectsProvider.projects.where(
                                    (p) => p.name.toLowerCase() == item.name.toLowerCase() ||
                                        p.name.toLowerCase() == item.id.toLowerCase(),
                                  ).firstOrNull;
                                  if (match != null) {
                                    appState.setTab(NavigationTab.myProjects, projectId: match.id);
                                  } else {
                                    appState.setTab(NavigationTab.myProjects);
                                  }
                                },
                              )
                            else
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download, size: 14),
                                label: const Text('1-Click Install', style: TextStyle(fontSize: 11.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                onPressed: () {
                                  appState.startInstall(item.githubUrl);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
