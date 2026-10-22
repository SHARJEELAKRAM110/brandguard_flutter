import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The active brand is chosen at build time:
///
///   flutter run --flavor acme --dart-define=BRAND=acme
const brand = String.fromEnvironment('BRAND', defaultValue: 'acme');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config =
      jsonDecode(await rootBundle.loadString('config/$brand/production.json'))
          as Map<String, dynamic>;
  runApp(BrandApp(config: config));
}

class BrandApp extends StatelessWidget {
  const BrandApp({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config['display_name'] as String,
      home: Scaffold(
        appBar: AppBar(title: Text(config['display_name'] as String)),
        body: Center(child: Image.asset('assets/brands/$brand/logo.png')),
      ),
    );
  }
}
