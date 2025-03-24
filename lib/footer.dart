import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App version footer widget that displays the current app version
/// and shows an about dialog when tapped.
class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({super.key});

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String appVersion = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        appVersion = packageInfo.version;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAboutDialog(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Text(
          isLoading ? 'Rate Me!' : 'Rate Me! v$appVersion',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            decoration: TextDecoration.underline,
            // Replace deprecated withOpacity with withAlpha
            color: Colors.white
                .withAlpha(204), // 0.8 opacity = 204 alpha (255 * 0.8)
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
              const SizedBox(height: 24), // Increased from 12 to 24
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text(
                  'Website',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () async {
                  final uri = Uri.parse('https://ali3nated0.github.io/RateMe/');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
