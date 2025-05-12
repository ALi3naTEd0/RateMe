import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/utils/version_info.dart';
import '../../core/services/logging.dart';
import '../../database/database_helper.dart';

/// App version footer widget that displays the current app version
/// and shows an about dialog when tapped.
class Footer extends StatefulWidget {
  const Footer({super.key});

  @override
  State<Footer> createState() => _FooterState();
}

class _FooterState extends State<Footer> {
  String appVersion = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      // First try to get version from VersionInfo class with full version string including build number
      appVersion = VersionInfo.fullVersionString;
    } catch (e) {
      // Fallback to package_info if VersionInfo fails
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (e) {
        appVersion = '1.0.0'; // Default fallback
        Logging.severe('Error loading app version: $e');
      }
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showAboutDialog() async {
    // Replace SharedPreferences with DatabaseHelper to get the dark text setting
    final db = DatabaseHelper.instance;
    final darkButtonTextSetting = await db.getSetting('useDarkButtonText');
    final useDarkText = darkButtonTextSetting?.toLowerCase() == 'true';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Stack(
          children: [
            const Center(child: Text('About Rate Me!')),
            Positioned(
              right: -8,
              top: -8,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Version: $appVersion'),
            const SizedBox(height: 12),
            const Text('Author: Eduardo Antonio Fortuny Ruvalcaba'),
            const SizedBox(height: 12),
            const Text('License: MIT'),
            const SizedBox(height: 24),

            // Add sponsor button here inside the dialog - UPDATED WITH BETTER ALIGNMENT AND BOLD TEXT
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Sponsor button with adjusted text alignment
                ElevatedButton.icon(
                  icon:
                      const Icon(Icons.favorite, color: Colors.pink, size: 16),
                  label: const Padding(
                    padding: EdgeInsets.only(
                        left: 0,
                        bottom: 0), // Shift text slightly down and left
                    child: Text(
                      'Support',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        height: 1.1, // Adjusted for better vertical alignment
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink
                        .shade100, // Lighter background for better contrast
                    foregroundColor:
                        Colors.pink.shade700, // Darker text for contrast
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 14),
                    alignment: Alignment.center, // Center alignment
                  ),
                  onPressed: () async {
                    final url =
                        Uri.parse('https://github.com/sponsors/ALi3naTEd0');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } else {
                      Logging.severe('Could not launch $url');
                    }
                  },
                ),
                const SizedBox(width: 12),

                // Website button (keep this from the original)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: useDarkText ? Colors.black : Colors.white,
                  ),
                  onPressed: () async {
                    final uri =
                        Uri.parse('https://ali3nated0.github.io/RateMe/');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Website'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Only show "Rate Me! vX.X.X" in the footer and open the dialog on tap
    return GestureDetector(
      onTap: _showAboutDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Text(
          isLoading ? 'Rate Me!' : 'Rate Me! ${VersionInfo.fullVersionString}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            decoration: TextDecoration.underline,
            color: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.color
                ?.withAlpha(isDark ? 178 : 204),
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
