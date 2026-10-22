import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../utils/glob.dart';
import '../utils/paths.dart';

/// Directory names that are never scanned.
const defaultExcludedDirectories = {
  '.dart_tool',
  '.git',
  '.gradle',
  '.idea',
  '.fvm',
  '.pub-cache',
  '.symlinks',
  '.vscode',
  '.cxx',
  'build',
  'ephemeral',
  'node_modules',
  'Pods',
  'DerivedData',
};

/// Files larger than this are not loaded for text scans.
const maxScannedFileBytes = 2 * 1024 * 1024;

/// Read-only, cached access to files inside the project root.
///
/// The directory walk happens at most once, never follows symbolic links,
/// skips [defaultExcludedDirectories] and the configured exclusions, and
/// never leaves the project root.
class ProjectFiles {
  /// Creates an index for [root].
  ProjectFiles(String root, {List<String> excludes = const []})
    : root = p.normalize(p.absolute(root)),
      _excludes = excludes.map((e) => Glob(normalizeRelative(e))).toList();

  /// Absolute project root.
  final String root;
  final List<Glob> _excludes;
  List<String>? _all;
  final Map<String, String?> _textCache = {};

  /// Relative paths (with `/`) of entries skipped during the walk because
  /// they were symbolic links or unreadable.
  final List<String> skipped = [];

  /// Whether [relativePath] matches a configured exclusion.
  bool isExcluded(String relativePath) {
    final path = normalizeRelative(relativePath);
    for (final glob in _excludes) {
      if (glob.matches(path)) return true;
      // A directory exclusion also excludes everything beneath it.
      if (!glob.hasWildcards && isSameOrWithin(glob.pattern, path)) {
        return true;
      }
    }
    return false;
  }

  /// All indexed files, sorted, as `/`-separated relative paths.
  List<String> get all => _all ??= _walk();

  /// Indexed files matching [glob].
  List<String> matching(String glob) {
    final matcher = Glob(normalizeRelative(glob));
    if (!matcher.hasWildcards) {
      final path = normalizeRelative(glob);
      return all.contains(path) ? [path] : const [];
    }
    return all.where(matcher.matches).toList();
  }

  /// Absolute path for [relativePath], or `null` if it escapes the root.
  String? absolute(String relativePath) => resolveWithin(root, relativePath);

  /// Classifies [relativePath] without following links.
  FileSystemEntityType typeOf(String relativePath) {
    final path = absolute(relativePath);
    if (path == null) return FileSystemEntityType.notFound;
    return FileSystemEntity.typeSync(path, followLinks: false);
  }

  /// Whether [relativePath] is an existing regular file inside the root.
  bool fileExists(String relativePath) =>
      typeOf(relativePath) == FileSystemEntityType.file;

  /// Whether [relativePath] is an existing directory inside the root.
  bool directoryExists(String relativePath) =>
      typeOf(relativePath) == FileSystemEntityType.directory;

  /// Reads [relativePath] as UTF-8 text. Returns `null` when the file is
  /// missing, unreadable, larger than [maxScannedFileBytes], or binary.
  String? readText(String relativePath) {
    final key = normalizeRelative(relativePath);
    return _textCache.putIfAbsent(key, () {
      final path = absolute(key);
      if (path == null || !fileExists(key)) return null;
      final file = File(path);
      try {
        if (file.lengthSync() > maxScannedFileBytes) return null;
        final bytes = file.readAsBytesSync();
        if (bytes.contains(0)) return null;
        return utf8.decode(bytes, allowMalformed: true);
      } on FileSystemException {
        return null;
      }
    });
  }

  /// Reads raw bytes of [relativePath] when it is a regular file no larger
  /// than [maxBytes].
  Uint8List? readBytes(String relativePath, {int maxBytes = 10 * 1024 * 1024}) {
    final path = absolute(relativePath);
    if (path == null || !fileExists(relativePath)) return null;
    try {
      final file = File(path);
      if (file.lengthSync() > maxBytes) return null;
      return file.readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  /// File size in bytes, or `null`.
  int? sizeOf(String relativePath) {
    final path = absolute(relativePath);
    if (path == null || !fileExists(relativePath)) return null;
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  List<String> _walk() {
    final result = <String>[];
    void visit(Directory directory) {
      final List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(followLinks: false);
      } on FileSystemException {
        skipped.add(relativeTo(root, directory.path));
        return;
      }
      for (final entry in entries) {
        final relative = relativeTo(root, entry.path);
        if (entry is Link) {
          skipped.add(relative);
          continue;
        }
        if (isExcluded(relative)) continue;
        if (entry is Directory) {
          if (defaultExcludedDirectories.contains(p.basename(entry.path))) {
            continue;
          }
          visit(entry);
        } else if (entry is File) {
          result.add(relative);
        }
      }
    }

    visit(Directory(root));
    result.sort();
    return result;
  }
}
