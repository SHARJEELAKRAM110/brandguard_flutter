/// Builds a minimal but structurally faithful `project.pbxproj`.
///
/// [runnerConfigs] maps configuration names to build settings (raw pbxproj
/// syntax, one `KEY = value;` per entry). [xcconfigs] maps configuration
/// names to the xcconfig path used as `baseConfigurationReference`.
String pbxproj({
  required Map<String, Map<String, String>> runnerConfigs,
  Map<String, String> xcconfigs = const {},
  String target = 'Runner',
}) {
  var counter = 0;
  String id() => (counter++).toRadixString(16).toUpperCase().padLeft(24, 'A');

  final fileRefs = <String, String>{}; // path -> id
  for (final path in xcconfigs.values.toSet()) {
    fileRefs[path] = id();
  }
  final runnerIds = <String, String>{};
  final projectIds = <String, String>{};
  for (final name in runnerConfigs.keys) {
    runnerIds[name] = id();
    projectIds[name] = id();
  }
  final runnerList = id();
  final projectList = id();
  final targetId = id();
  final projectId = id();

  final buffer = StringBuffer()
    ..writeln('// !\$*UTF8*\$!')
    ..writeln('{')
    ..writeln('\tarchiveVersion = 1;')
    ..writeln('\tobjects = {')
    ..writeln('/* Begin PBXFileReference section */');
  for (final entry in fileRefs.entries) {
    final name = entry.key.split('/').last;
    buffer.writeln(
      '\t\t${entry.value} /* $name */ = {isa = PBXFileReference; '
      'lastKnownFileType = text.xcconfig; name = $name; '
      'path = ${entry.key}; sourceTree = "<group>"; };',
    );
  }
  buffer
    ..writeln('/* End PBXFileReference section */')
    ..writeln('\t\t$targetId /* $target */ = {')
    ..writeln('\t\t\tisa = PBXNativeTarget;')
    ..writeln(
      '\t\t\tbuildConfigurationList = $runnerList '
      '/* Build configuration list for PBXNativeTarget "$target" */;',
    )
    ..writeln('\t\t\tname = $target;')
    ..writeln('\t\t\tproductName = $target;')
    ..writeln('\t\t};')
    ..writeln('\t\t$projectId /* Project object */ = {')
    ..writeln('\t\t\tisa = PBXProject;')
    ..writeln('\t\t\tbuildConfigurationList = $projectList;')
    ..writeln('\t\t};');
  for (final entry in runnerConfigs.entries) {
    final name = entry.key;
    final quoted = RegExp(r'^\w+$').hasMatch(name) ? name : '"$name"';
    buffer
      ..writeln('\t\t${projectIds[name]} /* $name */ = {')
      ..writeln('\t\t\tisa = XCBuildConfiguration;')
      ..writeln('\t\t\tbuildSettings = {')
      ..writeln('\t\t\t\tSDKROOT = iphoneos;')
      ..writeln('\t\t\t};')
      ..writeln('\t\t\tname = $quoted;')
      ..writeln('\t\t};')
      ..writeln('\t\t${runnerIds[name]} /* $name */ = {')
      ..writeln('\t\t\tisa = XCBuildConfiguration;');
    final xcconfig = xcconfigs[name];
    if (xcconfig != null) {
      buffer.writeln(
        '\t\t\tbaseConfigurationReference = ${fileRefs[xcconfig]} '
        '/* ${xcconfig.split('/').last} */;',
      );
    }
    buffer.writeln('\t\t\tbuildSettings = {');
    buffer.writeln('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (');
    buffer.writeln('\t\t\t\t\t"\$(inherited)",');
    buffer.writeln('\t\t\t\t);');
    for (final setting in entry.value.entries) {
      buffer.writeln('\t\t\t\t${setting.key} = ${setting.value};');
    }
    buffer
      ..writeln('\t\t\t};')
      ..writeln('\t\t\tname = $quoted;')
      ..writeln('\t\t};');
  }
  buffer
    ..writeln('\t\t$runnerList /* Build configuration list */ = {')
    ..writeln('\t\t\tisa = XCConfigurationList;')
    ..writeln('\t\t\tbuildConfigurations = (')
    ..writeAll(
      runnerIds.entries.map((e) => '\t\t\t\t${e.value} /* ${e.key} */,\n'),
    )
    ..writeln('\t\t\t);')
    ..writeln('\t\t};')
    ..writeln('\t\t$projectList /* Build configuration list */ = {')
    ..writeln('\t\t\tisa = XCConfigurationList;')
    ..writeln('\t\t\tbuildConfigurations = (')
    ..writeAll(
      projectIds.entries.map((e) => '\t\t\t\t${e.value} /* ${e.key} */,\n'),
    )
    ..writeln('\t\t\t);')
    ..writeln('\t\t};')
    ..writeln('\t};')
    ..writeln('\trootObject = $projectId /* Project object */;')
    ..writeln('}');
  return buffer.toString();
}

/// An Info.plist with the given display name.
String infoPlist(String displayName) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>$displayName</string>
	<key>CFBundleName</key>
	<string>runner</string>
</dict>
</plist>
''';
