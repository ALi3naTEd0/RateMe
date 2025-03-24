import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_data.dart';
import 'data_migration_service.dart';
import 'logging.dart';
import 'backup_converter.dart';
import 'debug_util.dart';

class SettingsPage extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Function(Color) onPrimaryColorChanged;
  final ThemeMode currentTheme;
  final Color currentPrimaryColor;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.onPrimaryColorChanged,
    required this.currentTheme,
    required this.currentPrimaryColor,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  late Color pickerColor;
  late Color textColor;
  final defaultColor = const Color(0xFF864AF9);
  final defaultTextColor = Colors.white;
  bool useDarkText = false;

  @override
  void initState() {
    super.initState();
    pickerColor = widget.currentPrimaryColor;
    textColor = defaultTextColor;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      useDarkText = prefs.getBool('useDarkButtonText') ?? false;
    });
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAdvancedColorPicker() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Color Picker',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ColorPicker(
                    pickerColor: pickerColor,
                    onColorChanged: (color) {
                      setState(() {
                        pickerColor = color;
                        textColor = color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white;
                      });
                      widget.onPrimaryColorChanged(color);
                    },
                    portraitOnly: true,
                    colorPickerWidth: 300,
                    enableAlpha: false,
                    hexInputBar: true,
                    displayThumbColor: true,
                  ),
                  TextButton(
                    onPressed: () => navigator.pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showUnifiedFormatDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Convert to Unified Format',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text(
                    'This will convert all your albums to the new unified data model. '
                    'This improves compatibility between different music platforms. '
                    '\n\nYour data will be backed up first for safety.',
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          navigator.pop(true);
                          await _performConversion();
                        },
                        child: const Text('Convert'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performConversion() async {
    _showProgressDialog(
        'Converting Data', 'Converting albums to unified format...');

    try {
      final count = await UserData.convertAllAlbumsToUnifiedFormat();
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Successfully converted $count albums to unified format');
    } catch (e) {
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Error during conversion: $e');
    }
  }

  void _showProgressDialog(String title, String message) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMigrationDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Migrate Data',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text(
                    'This will convert your saved data to the latest format. '
                    'Your data will be backed up first for safety.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Note: This process might take a moment depending on '
                    'how many albums you have saved.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          navigator.pop(true);
                          await _performMigration();
                        },
                        child: const Text('Migrate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performMigration() async {
    _showProgressDialog(
        'Migrating Data', 'Please wait while your data is being updated...');

    try {
      final migratedCount = await DataMigrationService.migrateAllAlbums();
      navigatorKey.currentState?.pop(); // Dismiss progress

      if (migratedCount > 0) {
        final shouldActivate = await navigatorKey.currentState?.push<bool>(
          PageRouteBuilder(
            barrierColor: Colors.black54,
            opaque: false,
            pageBuilder: (_, __, ___) => Material(
              type: MaterialType.transparency,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Migration Complete',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Text(
                        'Successfully migrated $migratedCount albums. '
                        'Do you want to activate the new data format now?',
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                navigatorKey.currentState?.pop(false),
                            child: const Text('Not Now'),
                          ),
                          TextButton(
                            onPressed: () =>
                                navigatorKey.currentState?.pop(true),
                            child: const Text('Activate'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        if (shouldActivate == true) {
          final success = await DataMigrationService.activateMigratedData();
          _showSnackBar(
            success
                ? 'New data format activated successfully!'
                : 'Failed to activate new data format',
          );
        }
      } else {
        _showSnackBar(
          'No data was migrated. You might not have any saved albums.',
        );
      }
    } catch (e) {
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Error during migration: $e');
    }
  }

  Future<void> _rollbackMigration() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final shouldRollback = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Rollback Migration',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text(
                    'This will revert to your previous data format.\n\n'
                    'This is helpful if you experienced issues after migration.',
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => navigator.pop(true),
                        child: const Text('Rollback'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (shouldRollback != true) return;

    _showProgressDialog('Rolling Back Migration',
        'Please wait while your data is being restored...');

    try {
      final success = await DataMigrationService.rollbackMigration();
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar(
        success
            ? 'Migration successfully rolled back'
            : 'Rollback failed - no backup data found',
      );
    } catch (e) {
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Error during rollback: $e');
    }
  }

  Future<void> _showClearDatabaseDialog() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final result = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Clear Database',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('This will delete:'),
                  const SizedBox(height: 8),
                  const Text('• All saved albums'),
                  const Text('• All ratings'),
                  const Text('• All custom lists'),
                  const Text('• All settings'),
                  const SizedBox(height: 16),
                  const Text(
                    'This action cannot be undone!',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => navigator.pop(true),
                        child: const Text('Clear Everything'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      try {
        await UserData.clearAllData();
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        _showSnackBar('Database cleared successfully');
      } catch (e) {
        Logging.severe('Error clearing database', e);
        _showSnackBar('Error clearing database: $e');
      }
    }
  }

  Future<void> _showRepairDialog() async {
    _showProgressDialog('Repairing Data...',
        'Please wait while your data is being repaired...');

    try {
      final repairResult = await UserData.repairSavedAlbums();
      final removedRatings = await UserData.cleanupOrphanedRatings();
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar(
        '${repairResult ? "Albums repaired successfully!" : "No album repairs needed"}\n'
        'Removed $removedRatings orphaned ratings.',
      );
    } catch (e) {
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Error repairing data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false, // Remove debug banner
      theme: Theme.of(context), // Inherit theme from parent
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          children: [
            // Theme Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Theme',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    value: ThemeMode.light,
                    groupValue: widget.currentTheme,
                    onChanged: (ThemeMode? mode) {
                      if (mode != null) widget.onThemeChanged(mode);
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    value: ThemeMode.dark,
                    groupValue: widget.currentTheme,
                    onChanged: (ThemeMode? mode) {
                      if (mode != null) widget.onThemeChanged(mode);
                    },
                  ),
                ],
              ),
            ),

            // Color Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'App Colors',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: 'Restore default colors',
                          onPressed: () {
                            setState(() {
                              pickerColor = defaultColor;
                              textColor = defaultTextColor;
                            });
                            widget.onPrimaryColorChanged(defaultColor);
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: const Text('Primary Color'),
                    subtitle: Text(
                      // Change ColorToHex to colorToHex to follow Dart naming conventions
                      colorToHex(pickerColor).toString().toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: pickerColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    onTap: () => _showAdvancedColorPicker(),
                  ),
                  ListTile(
                    title: const Text('Button Text Color'),
                    trailing: Switch(
                      value: useDarkText,
                      thumbIcon:
                          WidgetStateProperty.resolveWith<Icon?>((states) {
                        return Icon(
                          useDarkText
                              ? Icons.format_color_text
                              : Icons.format_color_reset,
                          size: 16,
                          color: useDarkText ? Colors.black : Colors.white,
                        );
                      }),
                      inactiveTrackColor: HSLColor.fromColor(
                              Theme.of(context).colorScheme.primary)
                          .withAlpha(0.5)
                          .toColor(),
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      activeColor: Colors.black, // When active, always black
                      inactiveThumbColor:
                          Colors.white, // When inactive, always white
                      onChanged: (bool value) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('useDarkButtonText', value);
                        setState(() {
                          useDarkText = value;
                        });
                      },
                    ),
                    subtitle: Text(useDarkText ? 'Dark text' : 'Light text'),
                  ),
                  // Color Preview Section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Preview:'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.palette, color: pickerColor),
                              const SizedBox(width: 8),
                              Text(
                                'Sample Text',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                                ),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: () {},
                                style: FilledButton.styleFrom(
                                  backgroundColor: pickerColor,
                                  foregroundColor:
                                      useDarkText ? Colors.black : Colors.white,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: const Text('Button'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Data Management Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Data Management',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        FutureBuilder<bool>(
                          future: DataMigrationService.isMigrationNeeded(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              );
                            }

                            final needsMigration = snapshot.data ?? false;

                            return needsMigration
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Update Available',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check_circle,
                                    color: Colors.green);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Standard Backup Options
                  ListTile(
                    leading: const Icon(Icons.file_upload),
                    title: const Text('Export Backup'),
                    subtitle: const Text('Save all your data as a backup file'),
                    onTap: () async =>
                        await UserData.exportData(), // Remove context parameter
                  ),
                  ListTile(
                    leading: const Icon(Icons.file_download),
                    title: const Text('Import Backup'),
                    subtitle: const Text('Restore data from a backup file'),
                    onTap: () async =>
                        await UserData.importData(), // Remove context parameter
                  ),

                  const Divider(),

                  // Data Conversion
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Convert to Unified Format'),
                    subtitle: const Text(
                        'Convert all albums to the unified data model'),
                    onTap: () => _showUnifiedFormatDialog(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync_alt),
                    title: const Text('Convert Old Backup'),
                    subtitle:
                        const Text('Create new format backup from old one'),
                    onTap: () => BackupConverter
                        .convertBackupFile(), // Remove context parameter
                  ),
                  ListTile(
                    leading: const Icon(Icons.system_update_alt),
                    title: const Text('Import & Convert Old Backup'),
                    subtitle:
                        const Text('Convert and import old backup directly'),
                    onTap: () => BackupConverter
                        .importConvertedBackup(), // Remove context parameter
                  ),

                  const Divider(),

                  // Migration Options
                  ListTile(
                    leading: const Icon(Icons.update),
                    title: const Text('Migrate Data'),
                    subtitle:
                        const Text('Convert your data to the latest format'),
                    onTap: () => _showMigrationDialog(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Rollback Migration'),
                    subtitle: const Text('Revert to previous data format'),
                    onTap: () => _rollbackMigration(),
                  ),
                ],
              ),
            ),

            // Debug & Development Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Debug & Development',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: const Text('Show Debug Info'),
                    subtitle: const Text('View technical information'),
                    onTap: () => DebugUtil.showDebugReport(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.healing),
                    title: const Text('Repair Album Data'),
                    subtitle: const Text('Fix problems with album display'),
                    onTap: () => _showRepairDialog(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever),
                    title: const Text('Clear Database'),
                    subtitle:
                        const Text('Delete all saved data (cannot be undone)'),
                    onTap: () => _showClearDatabaseDialog(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Rename method from ColorToHex to colorToHex
  String colorToHex(Color color) {
    int rgb = ((color.a * 255).round() << 24) | (color.toARGB32() & 0x00FFFFFF);
    String value = '#${rgb.toRadixString(16).padLeft(6, '0').substring(2)}';
    return value;
  }
}
