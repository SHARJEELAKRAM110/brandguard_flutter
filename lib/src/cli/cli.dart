import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../brandguard.dart';
import '../config/config_loader.dart';
import '../config/config_model.dart';
import '../discovery/project_files.dart';
import '../discovery/project_locator.dart';
import '../reporting/json_reporter.dart';
import '../reporting/text_reporter.dart';
import '../version.dart';
import 'init_template.dart';

/// Process exit codes.
abstract final class ExitCodes {
  /// Validation passed.
  static const passed = 0;

  /// Validation found problems that fail the policy.
  static const failed = 1;

  /// Invalid arguments, configuration errors, or execution failures.
  static const error = 2;
}

/// Terminal I/O used by the CLI; injectable for tests.
class CliIO {
  /// Creates an I/O bundle.
  CliIO({
    required this.out,
    required this.err,
    required this.workingDirectory,
    this.readLine,
    this.interactive = false,
    this.supportsAnsi = false,
    this.environment = const {},
  });

  /// I/O bound to the real process.
  factory CliIO.system() => CliIO(
    out: stdout,
    err: stderr,
    workingDirectory: Directory.current.path,
    readLine: stdin.readLineSync,
    interactive: stdin.hasTerminal && stdout.hasTerminal,
    supportsAnsi: stdout.hasTerminal && stdout.supportsAnsiEscapes,
    environment: Platform.environment,
  );

  /// Standard output (reports, JSON).
  final StringSink out;

  /// Standard error (diagnostics).
  final StringSink err;

  /// Directory the command runs from.
  final String workingDirectory;

  /// Reads one line from the user, or `null` when input is unavailable.
  final String? Function()? readLine;

  /// Whether the user can answer prompts.
  final bool interactive;

  /// Whether stdout understands ANSI escape codes.
  final bool supportsAnsi;

  /// Environment variables (`NO_COLOR`, `CI`).
  final Map<String, String> environment;
}

/// The `brandguard` command-line interface.
class BrandGuardCli {
  /// Creates the CLI. [guard] supplies the rules (defaults to built-ins).
  BrandGuardCli({CliIO? io, BrandGuard? guard})
    : io = io ?? CliIO.system(),
      guard = guard ?? BrandGuard();

  /// Terminal I/O.
  final CliIO io;

  /// Validation engine.
  final BrandGuard guard;

  /// Runs the CLI with [arguments] and returns the exit code.
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(io)
      ..addCommand(_CheckCommand(io, guard))
      ..addCommand(_InitCommand(io, guard))
      ..addCommand(_RulesCommand(io, guard));
    try {
      final ArgResults results = runner.parse(arguments);
      if (results['version'] == true) {
        io.out.writeln('brandguard $brandGuardVersion');
        return ExitCodes.passed;
      }
      final code = await runner.runCommand(results);
      return code ?? ExitCodes.passed;
    } on UsageException catch (e) {
      io.err
        ..writeln('Error: ${e.message}')
        ..writeln()
        ..writeln(e.usage);
      return ExitCodes.error;
    }
  }
}

class _Runner extends CommandRunner<int> {
  _Runner(this.io)
    : super(
        'brandguard',
        'Catch white-label mistakes before release.\n\n'
            'Validates every brand of a white-label Flutter app: assets, '
            'application IDs,\napp names, ARB translations and environment '
            'URLs. Read-only.\n\n'
            'Exit codes: 0 passed, 1 validation failed, 2 usage/config/'
            'execution error.',
      ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the BrandGuard version.',
    );
  }

  final CliIO io;

  @override
  String get invocation => 'brandguard <command> [arguments]';

  @override
  void printUsage() => io.out.writeln(usage);
}

abstract class _Command extends Command<int> {
  _Command(this.io, this.guard);

  final CliIO io;
  final BrandGuard guard;

  @override
  void printUsage() => io.out.writeln(usage);

  void addProjectOptions() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        valueHelp: 'path',
        help:
            'Flutter project root (or a directory inside it). Defaults to '
            'searching upward from the current directory.',
      )
      ..addOption(
        'config',
        abbr: 'c',
        valueHelp: 'path',
        help:
            'Configuration file. Defaults to <project>/$defaultConfigFileName '
            '(or $alternateConfigFileName if only that exists).',
      );
  }

  String? resolvePath(String? value) =>
      value == null ? null : p.normalize(p.join(io.workingDirectory, value));
}

class _CheckCommand extends _Command {
  _CheckCommand(super.io, super.guard) {
    addProjectOptions();
    argParser
      ..addMultiOption(
        'brand',
        abbr: 'b',
        valueHelp: 'id',
        help: 'Validate only this brand (repeatable or comma-separated).',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Validate every configured brand (the default).',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
        help: 'Output format. JSON is written to stdout only.',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Warnings also fail validation (exit code 1).',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help: 'Text format: print only failing findings and the summary.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Text format: include explanations and certainty.',
      )
      ..addFlag(
        'color',
        defaultsTo: null,
        help:
            'Force ANSI colors on or off. Default: on for terminals that '
            'support it, off when NO_COLOR is set.',
      );
  }

  @override
  String get name => 'check';

  @override
  String get description => 'Validate brands and report findings.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final brands = args.multiOption('brand');
    final json = args.option('format') == 'json';
    if (args.flag('all') && brands.isNotEmpty) {
      usageException('Use either --brand or --all, not both.');
    }
    if (args.flag('quiet') && args.flag('verbose')) {
      usageException('Use either --quiet or --verbose, not both.');
    }
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    try {
      final config = guard.loadConfig(
        configPath: resolvePath(args.option('config')),
        projectDirectory: resolvePath(args.option('project')),
        workingDirectory: io.workingDirectory,
      );
      final result = guard.validate(
        config,
        brandIds: brands.isEmpty ? null : brands,
        strict: args.flag('strict'),
      );
      if (json) {
        io.out.writeln(const JsonReporter().render(result));
      } else {
        final colorFlag = args['color'] as bool?;
        final color =
            colorFlag ??
            (io.supportsAnsi && !io.environment.containsKey('NO_COLOR'));
        io.out.write(
          TextReporter(
            color: color,
            verbosity: args.flag('quiet')
                ? Verbosity.quiet
                : args.flag('verbose')
                ? Verbosity.verbose
                : Verbosity.normal,
          ).render(result),
        );
      }
      return result.exitCode;
    } on ProjectNotFoundException catch (e) {
      return _fail(json, e.message);
    } on ConfigException catch (e) {
      return _fail(
        json,
        'Invalid configuration in ${e.configPath}',
        details: e.issues,
      );
    } on UnknownBrandException catch (e) {
      return _fail(json, e.toString());
    } on RuleExecutionException catch (e) {
      if (args.flag('verbose')) io.err.writeln(e.stackTrace);
      return _fail(json, '$e');
    }
  }

  int _fail(bool json, String message, {List<ConfigIssue> details = const []}) {
    if (json) {
      io.out.writeln(
        const JsonReporter().renderError(
          message,
          details: [
            for (final issue in details)
              {
                'message': issue.message,
                'field': issue.field,
                'line': issue.line,
              },
          ],
        ),
      );
    }
    io.err.writeln('Error: $message');
    for (final issue in details) {
      io.err.writeln('  - $issue');
    }
    return ExitCodes.error;
  }
}

class _InitCommand extends _Command {
  _InitCommand(super.io, super.guard) {
    addProjectOptions();
    argParser
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing configuration without asking.',
      )
      ..addFlag(
        'no-input',
        negatable: false,
        help:
            'Never prompt (for CI). Fails if the configuration already '
            'exists, unless --force is given.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Create a commented $defaultConfigFileName for this Flutter project.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Unexpected arguments: ${args.rest.join(' ')}');
    }
    final FlutterProject project;
    try {
      project = const ProjectLocator().locate(
        resolvePath(args.option('project')) ?? io.workingDirectory,
      );
    } on ProjectNotFoundException catch (e) {
      io.err
        ..writeln('Error: ${e.message}')
        ..writeln(
          '`brandguard init` must run inside a Flutter project (a directory '
          'whose pubspec.yaml depends on the Flutter SDK).',
        );
      return ExitCodes.error;
    }
    // An existing brandguard.yaml is the project's config: target it so the
    // overwrite protection applies instead of creating a conflicting file.
    final alternate = p.join(project.root, alternateConfigFileName);
    final target =
        resolvePath(args.option('config')) ??
        (File(alternate).existsSync()
            ? alternate
            : p.join(project.root, defaultConfigFileName));

    final detection = InitDetection.detect(
      ProjectFiles(project.root),
      project.name,
    );
    io.out
      ..writeln('Flutter project: ${project.name} (${project.root})')
      ..writeln('Will create: $target')
      ..writeln(
        'Contents: a commented BrandGuard configuration with '
        '${detection.brands.isEmpty ? 'one example brand' : '${detection.brands.length} detected brand(s)'}.',
      );
    for (final note in detection.notes) {
      io.out.writeln('  detected: $note');
    }

    final file = File(target);
    if (file.existsSync() && !args.flag('force')) {
      final canPrompt =
          io.interactive && !args.flag('no-input') && io.readLine != null;
      if (!canPrompt) {
        io.err.writeln(
          'Error: $target already exists. Re-run with --force to overwrite it.',
        );
        return ExitCodes.error;
      }
      io.out.write('$target already exists. Overwrite? [y/N] ');
      final answer = io.readLine!()?.trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        io.out.writeln('Left the existing configuration unchanged.');
        return ExitCodes.passed;
      }
    }

    final content = renderInitConfig(detection);
    // Refuse to write something BrandGuard itself cannot load.
    try {
      ConfigLoader(
        knownRuleIds: guard.rules.map((r) => r.id),
      ).parse(content, configPath: target, projectRootOverride: project.root);
    } on ConfigException catch (e) {
      io.err.writeln('Internal error: generated configuration is invalid:\n$e');
      return ExitCodes.error;
    }
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    } on FileSystemException catch (e) {
      io.err.writeln('Error: could not write $target: ${e.message}');
      return ExitCodes.error;
    }
    io.out
      ..writeln('Created $target')
      ..writeln('Next: review the file, then run `brandguard check`.');
    return ExitCodes.passed;
  }
}

class _RulesCommand extends _Command {
  _RulesCommand(super.io, super.guard);

  @override
  String get name => 'rules';

  @override
  String get description => 'List validation rules and default severities.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final width = guard.rules
        .map((r) => r.id.length)
        .reduce((a, b) => a > b ? a : b);
    for (final rule in guard.rules) {
      io.out.writeln(
        '${rule.id.padRight(width)}  '
        '${rule.defaultSeverity.name.padRight(7)}  ${rule.description}',
      );
    }
    return ExitCodes.passed;
  }
}
