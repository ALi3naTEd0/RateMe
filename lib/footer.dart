import 'package:flutter/material.dart';

const String appVersion = '0.0.9g';

class Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      alignment: Alignment.center,
      child: Text('Version $appVersion', style: TextStyle(color: Colors.grey)),
    );
  }
}
