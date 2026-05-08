import 'package:flutter/material.dart';

@Deprecated('Use BlueVPNApp from lib/main.dart as the primary entrypoint.')
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Legacy HomeScreen entrypoint is deprecated.\nRun lib/main.dart for the current BlueVPN app shell.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
