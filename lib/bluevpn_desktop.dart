import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const BlueVPNDesktopApp());
}

class BlueVPNDesktopApp extends StatelessWidget {
  const BlueVPNDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
