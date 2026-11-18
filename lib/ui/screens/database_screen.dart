import 'package:flutter/material.dart';
import '../../core/constants/supported_technologies.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database/database_manager.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  List<DatabaseInstance> _instances = [];
  List<String> _mysqlDatabases = [];
  bool _isLoading = true;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final list = await DatabaseManager.getKnownDatabases();
    // Test real live connection status for each database service
    for (final inst in list) {
      inst.isRunning = await DatabaseManager.testConnection(type: inst.type, port: inst.port);
    }
    final dbs = await DatabaseManager.listDatabases();
    setState(() {
      _instances = list;
      _mysqlDatabases = dbs;
      _isLoading = false;
    });
  }

  Future<void> _startService(DatabaseInstance instance) async {
    setState(() => _testResult = 'Starting ${instance.name} on port ${instance.port}...');
    final ok = await DatabaseManager.startDatabaseService(instance.type);
    await _refresh();
    setState(() {
      _testResult = ok
          ? '✓ ${instance.name} is started and running on port ${instance.port}'
          : '✗ Failed to start ${instance.name}. Check logs.';
    });
  }

  Future<void> _stopService(DatabaseInstance instance) async {
    setState(() => _testResult = 'Stopping ${instance.name}...');
    final ok = await DatabaseManager.stopDatabaseService(instance.type);
    await _refresh();
    setState(() {
      _testResult = ok
          ? '✓ ${instance.name} has been stopped.'
          : '✗ Failed to stop ${instance.name}.';
    });
  }

  Future<void> _testDb(DatabaseInstance instance) async {
    setState(() => _testResult = 'Testing connection to ${instance.name}...');
    final ok = await DatabaseManager.testConnection(type: instance.type, port: instance.port);
    setState(() {
      _testResult = ok
          ? '✓ Successfully connected to ${instance.name} on port ${instance.port}'
          : '✗ Connection to ${instance.name} on port ${instance.port} failed. Server is not reachable.';
    });
  }

  Future<void> _promptCreateDatabase() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create MySQL Database'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Database Name',
            hintText: 'e.g. clinic_db, erp_store',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      final ok = await DatabaseManager.ensureDatabaseExists(databaseName: name);
      await _refresh();
      setState(() {
        _testResult = ok
            ? '✓ MySQL database "$name" created successfully!'
            : '✗ Failed to create database "$name". Ensure MySQL service is running.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Database Manager',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage MySQL & SQLite database engines, start/stop services, and provision databases',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('New Database'),
                      onPressed: _promptCreateDatabase,
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Status'),
                      onPressed: _refresh,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (_testResult != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _testResult!.startsWith('✓')
                      ? AppTheme.successGreen.withValues(alpha: 0.1)
                      : AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testResult!.startsWith('✓') ? AppTheme.successGreen : AppTheme.errorRed,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.startsWith('✓') ? Icons.check_circle : Icons.error,
                      color: _testResult!.startsWith('✓') ? AppTheme.successGreen : AppTheme.errorRed,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_testResult!)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Dual Highlight Cards: SQLite + MySQL
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.file_present, color: AppTheme.accentCyan, size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SQLite Engine',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Zero-config embedded DB inside each project',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'READY',
                              style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storage, color: Colors.orange, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MySQL / MariaDB',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _instances.any((i) => i.type == DatabaseType.mysql && i.isRunning)
                                      ? 'Service active on 127.0.0.1:3306'
                                      : 'Service stopped (click Start below)',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _instances.any((i) => i.type == DatabaseType.mysql && i.isRunning)
                                  ? AppTheme.successGreen.withValues(alpha: 0.15)
                                  : Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _instances.any((i) => i.type == DatabaseType.mysql && i.isRunning) ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                color: _instances.any((i) => i.type == DatabaseType.mysql && i.isRunning)
                                    ? AppTheme.successGreen
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              'Database Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
            else
              ..._instances.map(
                (inst) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.dns,
                          color: inst.isRunning ? AppTheme.successGreen : Colors.grey,
                          size: 26,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inst.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${inst.type.displayName} • ${inst.host}:${inst.port}',
                                style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: inst.isRunning
                                ? AppTheme.successGreen.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            inst.isRunning ? 'RUNNING' : 'STOPPED',
                            style: TextStyle(
                              color: inst.isRunning ? AppTheme.successGreen : Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (inst.isRunning)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                            icon: const Icon(Icons.stop, size: 14),
                            label: const Text('Stop'),
                            onPressed: () => _stopService(inst),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                            icon: const Icon(Icons.play_arrow, size: 14),
                            label: const Text('Start'),
                            onPressed: () => _startService(inst),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _testDb(inst),
                          child: const Text('Test'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // MySQL Provisioned Databases List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Provisioned MySQL Databases (${_mysqlDatabases.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh DBs'),
                  onPressed: _refresh,
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_mysqlDatabases.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      _instances.any((i) => i.type == DatabaseType.mysql && i.isRunning)
                          ? 'No project databases created yet. Click "New Database" above to create one.'
                          : 'Start MySQL service above to view databases.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _mysqlDatabases.map((dbName) {
                  return Chip(
                    avatar: const CircleAvatar(
                      backgroundColor: Colors.transparent,
                      child: Icon(Icons.storage, size: 16, color: Colors.blueAccent),
                    ),
                    label: Text(
                      dbName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
