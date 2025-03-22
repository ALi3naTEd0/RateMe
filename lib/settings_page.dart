import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
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

  Future<void> _saveTextColorSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useDarkButtonText', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                    '#${pickerColor.value.toRadixString(16).toUpperCase().substring(2)}',
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
                  onTap: () => _showAdvancedColorPicker(context),
                ),
                ListTile(
                  title: const Text('Button Text Color'),
                  trailing: Switch(
                    value: useDarkText,
                    thumbIcon: MaterialStateProperty.resolveWith<Icon?>((states) {
                      return Icon(
                        useDarkText ? Icons.format_color_text : Icons.format_color_reset,
                        size: 16,
                        color: useDarkText ? Colors.black : Colors.white,
                      );
                    }),
                    inactiveTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    activeColor: Colors.black, // When active, always black
                    inactiveThumbColor: Colors.white, // When inactive, always white
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
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: () {},
                              style: FilledButton.styleFrom(
                                backgroundColor: pickerColor,
                                foregroundColor: useDarkText ? Colors.black : Colors.white,
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
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                                    color: Theme.of(context).colorScheme.primary,
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
                              : const Icon(Icons.check_circle, color: Colors.green);
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
                  onTap: () async => await UserData.exportData(context),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download),
                  title: const Text('Import Backup'),
                  subtitle: const Text('Restore data from a backup file'),
                  onTap: () async => await UserData.importData(context),
                ),
                
                const Divider(),
                
                // Data Conversion
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Convert to Unified Format'),
                  subtitle: const Text('Convert all albums to the unified data model'),
                  onTap: () => _showUnifiedFormatDialog(context),
                ),
                ListTile(
                  leading: const Icon(Icons.sync_alt),
                  title: const Text('Convert Old Backup'),
                  subtitle: const Text('Create new format backup from old one'),
                  onTap: () => BackupConverter.convertBackupFile(context),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('Import & Convert Old Backup'),
                  subtitle: const Text('Convert and import old backup directly'),
                  onTap: () => BackupConverter.importConvertedBackup(context),
                ),
                
                const Divider(),
                
                // Migration Options
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('Migrate Data'),
                  subtitle: const Text('Convert your data to the latest format'),
                  onTap: () => _showMigrationDialog(context),
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Rollback Migration'),
                  subtitle: const Text('Revert to previous data format'),
                  onTap: () => _rollbackMigration(context),
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
                  onTap: () => _showRepairDialog(context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Clear Database'),
                  subtitle: const Text('Delete all saved data (cannot be undone)'),
                  onTap: () => _showClearDatabaseDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAdvancedColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Color Picker'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              setState(() {
                pickerColor = color;
                // Automatically calculate if text should be black or white
                textColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
              });
              widget.onPrimaryColorChanged(color);
            },
            portraitOnly: true,
            colorPickerWidth: 300,
            enableAlpha: false,
            hexInputBar: true,
            displayThumbColor: true,
            showLabel: true,
            paletteType: PaletteType.hsvWithHue,
            pickerAreaHeightPercent: 0.7,
            labelTypes: const [
              ColorLabelType.hex,
              ColorLabelType.rgb,
              ColorLabelType.hsv,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showMigrationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate Data'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will convert your saved data to the latest format. '
              'Your data will be backed up first for safety.',
            ),
            SizedBox(height: 16),
            Text(
              'Note: This process might take a moment depending on '
              'how many albums you have saved.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performMigration(context);
            },
            child: const Text('Migrate'),
          ),
        ],
      ),
    );
  }

  Future<void> _performMigration(BuildContext context) async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Migrating Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Please wait while your data is being updated...'),
          ],
        ),
      ),
    );

    try {
      // Perform migration
      final migratedCount = await DataMigrationService.migrateAllAlbums();
      
      // Dismiss progress dialog
      if (mounted) Navigator.pop(context);
      
      if (migratedCount > 0) {
        // Ask for confirmation to activate
        if (mounted) {
          final shouldActivate = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Migration Complete'),
              content: Text(
                'Successfully migrated $migratedCount albums. '
                'Do you want to activate the new data format now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not Now'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Activate'),
                ),
              ],
            ),
          );

          if (shouldActivate == true) {
            final success = await DataMigrationService.activateMigratedData();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'New data format activated successfully!'
                        : 'Failed to activate new data format',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        // Show error or no data message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data was migrated. You might not have any saved albums.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Dismiss progress dialog
      if (mounted) Navigator.pop(context);
      
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during migration: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _rollbackMigration(BuildContext context) async {
    // Show confirm dialog
    final shouldRollback = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rollback Migration'),
        content: const Text(
          'This will revert to your previous data format.\n\n'
          'This is helpful if you experienced issues after migration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );
    
    if (shouldRollback != true) return;
    
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Rolling Back Migration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Please wait while your data is being restored...'),
          ],
        ),
      ),
    );
    
    try {
      // Attempt rollback
      final success = await DataMigrationService.rollbackMigration();
      
      // Dismiss progress dialog
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? 'Migration successfully rolled back' 
              : 'Rollback failed - no backup data found'
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Dismiss progress dialog
      if (mounted) Navigator.pop(context);
      
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during rollback: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showClearDatabaseDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Database'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will delete:'),
            SizedBox(height: 8),
            Text('• All saved albums'),
            Text('• All ratings'),
            Text('• All custom lists'),
            Text('• All settings'),
            SizedBox(height: 16),
            Text('This action cannot be undone!', 
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        await UserData.clearAllData();
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database cleared successfully')),
          );
        }
      } catch (e) {
        Logging.severe('Error clearing database', e);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error clearing database: $e')),
          );
        }
      }
    }
  }

  Future<void> _showUnifiedFormatDialog(BuildContext context) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Unified Format'),
        content: const Text(
          'This will convert all your albums to the new unified data model. '
          'This improves compatibility between different music platforms. '
          '\n\nYour data will be backed up first for safety.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Converting Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Converting albums to unified format...'),
          ],
        ),
      ),
    );
    
    try {
      final count = await UserData.convertAllAlbumsToUnifiedFormat();
      
      if (mounted) {
        Navigator.pop(context); // Dismiss progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully converted $count albums to unified format'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during conversion: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showRepairDialog(BuildContext context) async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Repairing Data...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Please wait while your data is being repaired...'),
          ],
        ),
      ),
    );
    
    try {
      final repairResult = await UserData.repairSavedAlbums();
      final removedRatings = await UserData.cleanupOrphanedRatings();
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${repairResult ? "Albums repaired successfully!" : "No album repairs needed"}\n'
              'Removed $removedRatings orphaned ratings.'
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error repairing data: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}