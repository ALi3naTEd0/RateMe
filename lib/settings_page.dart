import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

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
                      // Show text icon in switch thumb
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
}
