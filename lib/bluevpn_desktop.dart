import 'package:flutter/material.dart';

import 'main.dart' show BlueVPNApp;

void main() {
  runApp(const BlueVPNDesktopApp());
}

class BlueVPNDesktopApp extends StatelessWidget {
  const BlueVPNDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const BlueVPNApp();
  }
}
