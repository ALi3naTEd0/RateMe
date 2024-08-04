import 'package:flutter/material.dart';

const String appVersion = '0.0.9-5';

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      alignment: Alignment.center,
      child: const Text('Version $appVersion', style: TextStyle(color: Colors.grey)),
    );
  }
}
