import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// App version footer widget that displays the current app version
/// and shows an about dialog when tapped.
///
/// Separating this into its own file makes version updates easier to manage.
class AppVersionFooter extends StatelessWidget {
  const AppVersionFooter({super.key});

  // Current app version - update this for new releases
  static const String appVersion = '1.0.4-3';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAboutDialog(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Text(
          'Rate Me! v$appVersion',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            decoration: TextDecoration.underline,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8) ?? Colors.grey,
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
              const Text('License: GPL-3.0'),
              const SizedBox(height: 12),
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
