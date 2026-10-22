import 'dart:io';

import 'package:brandguard_flutter/brandguard_flutter.dart';

/// Entry point for `brandguard` (after `dart pub global activate`) and
/// `dart run brandguard_flutter:brandguard`.
Future<void> main(List<String> arguments) async {
  final code = await BrandGuardCli().run(arguments);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
