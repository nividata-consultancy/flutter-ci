import 'package:flutter/material.dart';

/// Values injected by flutter-ci with --dart-define-from-file=`env/ENV.json`.
const envName = String.fromEnvironment('ENV_NAME', defaultValue: 'local');
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter-ci example',
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter-ci example')),
        body: const Center(child: Text('Environment: $envName\nAPI: $apiBaseUrl')),
      ),
    );
  }
}
