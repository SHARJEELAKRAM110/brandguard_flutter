import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when no Flutter project can be found.
class ProjectNotFoundException implements Exception {
  /// Creates the exception.
  ProjectNotFoundException(this.message, {this.checked = const []});

  /// What went wrong and how to fix it.
  final String message;

  /// `pubspec.yaml` files that were inspected and rejected.
  final List<String> checked;

  @override
  String toString() => message;
}

/// A located Flutter project.
class FlutterProject {
  /// Creates a project reference.
  const FlutterProject({required this.root, required this.name});

  /// Absolute project root (the directory containing `pubspec.yaml`).
  final String root;

  /// `name` from `pubspec.yaml`.
  final String name;
}

/// Finds the Flutter project that contains a directory.
class ProjectLocator {
  /// Creates a locator.
  const ProjectLocator();

  /// Returns whether [pubspecText] declares a Flutter app or package: it
  /// depends on the `flutter` SDK or has a top-level `flutter:` section.
  static bool isFlutterPubspec(Object? pubspecYaml) {
    if (pubspecYaml is! Map) return false;
    final dependencies = pubspecYaml['dependencies'];
    if (dependencies is Map) {
      final flutter = dependencies['flutter'];
      if (flutter is Map && flutter['sdk'] == 'flutter') return true;
    }
    return pubspecYaml.containsKey('flutter');
  }

  /// Reads the project at exactly [directory] or throws
  /// [ProjectNotFoundException].
  FlutterProject readAt(String directory) {
    final root = p.normalize(p.absolute(directory));
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw ProjectNotFoundException(
        'No pubspec.yaml found in $root. Point --project at the root of a '
        'Flutter project.',
      );
    }
    final project = _tryRead(pubspec);
    if (project == null) {
      throw ProjectNotFoundException(
        '$root contains a pubspec.yaml that does not depend on the Flutter '
        'SDK. BrandGuard validates Flutter projects; check --project.',
        checked: [pubspec.path],
      );
    }
    return project;
  }

  /// Walks up from [start] to the nearest Flutter project.
  ///
  /// The walk stops at the first directory containing `.git` (the repository
  /// root) or at the file system root, so unrelated parent directories are
  /// never scanned.
  FlutterProject locate(String start) {
    var directory = p.normalize(p.absolute(start));
    final checked = <String>[];
    while (true) {
      final pubspec = File(p.join(directory, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final project = _tryRead(pubspec);
        if (project != null) return project;
        checked.add(pubspec.path);
      }
      final isRepositoryRoot =
          Directory(p.join(directory, '.git')).existsSync() ||
          File(p.join(directory, '.git')).existsSync();
      final parent = p.dirname(directory);
      if (isRepositoryRoot || parent == directory) break;
      directory = parent;
    }
    final detail = checked.isEmpty
        ? 'No pubspec.yaml was found'
        : 'Found pubspec.yaml without a Flutter dependency at '
              '${checked.join(', ')}';
    throw ProjectNotFoundException(
      'Could not find a Flutter project from ${p.absolute(start)}. $detail. '
      'Run BrandGuard inside a Flutter project or pass --project <path>.',
      checked: checked,
    );
  }

  FlutterProject? _tryRead(File pubspec) {
    final Object? yaml;
    try {
      yaml = loadYaml(pubspec.readAsStringSync());
    } on YamlException {
      return null;
    } on FileSystemException {
      return null;
    }
    if (!isFlutterPubspec(yaml)) return null;
    final name = (yaml as Map)['name'];
    return FlutterProject(
      root: pubspec.parent.path,
      name: name is String ? name : p.basename(pubspec.parent.path),
    );
  }
}
