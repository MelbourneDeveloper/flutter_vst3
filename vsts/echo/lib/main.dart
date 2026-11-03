import 'package:flutter/material.dart';
import 'ui/echo_ui.dart';

/// Entry point for the Echo plugin Flutter GUI.
@pragma('vm:entry-point')
void echoMain() {
  debugPrint('=== [Echo VST3] echoMain launched ===');
  runApp(const EchoApp());
}

void main() => echoMain();


/// Root widget for the Echo plugin UI.
class EchoApp extends StatelessWidget {
  const EchoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Echo VST3',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const EchoUI(),
    );
  }
}
