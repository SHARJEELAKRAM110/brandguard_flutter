import 'dart:io';

import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/pbxproj.dart';
import '../support/project_builder.dart';

IosProject _load(ProjectBuilder project) =>
    IosProject.load(ProjectFiles(project.root), const IosPlatformConfig())!;

void main() {
  group('XcodeProjectModel', () {
    test('parses targets, configurations and settings', () {
      final model = XcodeProjectModel.parse(
        pbxproj(
          runnerConfigs: {
            'Release-acme': {
              'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.acme',
              'APP_DISPLAY_NAME': '"Acme Retail"',
            },
          },
        ),
      );
      final configs = model.configurationsFor('Runner')!;
      expect(configs.single.name, 'Release-acme');
      expect(
        configs.single.settings['PRODUCT_BUNDLE_IDENTIFIER'],
        'com.example.acme',
      );
      expect(configs.single.settings['APP_DISPLAY_NAME'], 'Acme Retail');
      expect(
        configs.single.settings.containsKey('LD_RUNPATH_SEARCH_PATHS'),
        isFalse,
      );
      expect(model.projectConfiguration('Release-acme'), isNotNull);
    });

    test('parses the real Flutter template in the example project', () {
      final file = File(
        p.join(
          'example',
          'sample_white_label_project',
          'ios',
          'Runner.xcodeproj',
          'project.pbxproj',
        ),
      );
      final model = XcodeProjectModel.parse(file.readAsStringSync());
      final names = model.configurationsFor('Runner')!.map((c) => c.name);
      expect(
        names,
        containsAll([
          'Debug',
          'Release',
          'Profile',
          'Release-acme',
          'Release-nova',
        ]),
      );
      expect(model.configurationsFor('RunnerTests'), isNotEmpty);
    });
  });

  group('IosProject', () {
    test('matches Release-<flavor> configurations and expands variables', () {
      final project = ProjectBuilder()
        ..file(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(
            runnerConfigs: {
              'Debug': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.base'},
              'Release-acme': {
                'PRODUCT_BUNDLE_IDENTIFIER': '"\$(BASE_ID).acme"',
                'APP_DISPLAY_NAME': '"Acme Retail"',
              },
              'Release-nova': {'PRODUCT_BUNDLE_IDENTIFIER': '"\$(APP_ID)"'},
            },
            xcconfigs: {
              'Release-nova': 'Flutter/nova.xcconfig',
              'Release-acme': 'Flutter/acme.xcconfig',
            },
          ),
        )
        ..file('ios/Flutter/acme.xcconfig', 'BASE_ID = com.example\n')
        ..file(
          'ios/Flutter/nova.xcconfig',
          '#include? "Generated.xcconfig"\n#include "shared.xcconfig"\n'
              'APP_ID = com.example.nova // comment\n'
              'APP_DISPLAY_NAME = Nova Store\n',
        )
        ..file('ios/Flutter/shared.xcconfig', 'APP_ID = com.example.wrong\n')
        ..file('ios/Runner/Info.plist', infoPlist(r'$(APP_DISPLAY_NAME)'));
      final ios = _load(project);
      const acme = BrandConfig(id: 'acme');
      const nova = BrandConfig(id: 'nova');

      final acmeId = ios.bundleIdFor(acme);
      expect(acmeId.value, 'com.example.acme');
      expect(acmeId.scope, ValueScope.flavor);
      expect(acmeId.line, isNotNull);
      expect(ios.bundleIdFor(nova).value, 'com.example.nova');
      expect(ios.displayNameFor(acme).value, 'Acme Retail');
      expect(ios.displayNameFor(nova).value, 'Nova Store');
      expect(ios.displayNameFor(nova).file, 'ios/Runner/Info.plist');
    });

    test('reports unresolvable variables, modifiers and inherited values', () {
      final project = ProjectBuilder()
        ..file(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(
            runnerConfigs: {
              'Release-a': {'PRODUCT_BUNDLE_IDENTIFIER': '"\$(FLAVOR_ID)"'},
              'Release-b': {
                'PRODUCT_BUNDLE_IDENTIFIER':
                    '"com.example.\$(PRODUCT_NAME:rfc1034identifier)"',
              },
              'Release-c': {'PRODUCT_BUNDLE_IDENTIFIER': '"\$(inherited)"'},
            },
          ),
        );
      final ios = _load(project);
      expect(
        ios.bundleIdFor(const BrandConfig(id: 'a')).unresolvedReason,
        contains('FLAVOR_ID'),
      );
      expect(
        ios.bundleIdFor(const BrandConfig(id: 'b')).unresolvedReason,
        contains('rfc1034identifier'),
      );
      expect(
        ios.bundleIdFor(const BrandConfig(id: 'c')).unresolvedReason,
        contains('inherited'),
      );
    });

    test('reports flavors without a configuration', () {
      final project = ProjectBuilder()
        ..file(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(
            runnerConfigs: {
              'Release-acme': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.acme'},
            },
          ),
        );
      final value = _load(project).bundleIdFor(const BrandConfig(id: 'nova'));
      expect(value.scope, ValueScope.flavorMissing);
      expect(value.available, ['Release-acme']);
    });

    test('uses Release as a shared configuration without flavors', () {
      final project = ProjectBuilder()
        ..file(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(
            runnerConfigs: {
              'Debug': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.debug'},
              'Release': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.app'},
            },
          ),
        );
      final value = _load(project).bundleIdFor(const BrandConfig(id: 'any'));
      expect(value.value, 'com.example.app');
      expect(value.scope, ValueScope.shared);
    });

    test('honours an explicit ios_configuration', () {
      final project = ProjectBuilder()
        ..file(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(
            runnerConfigs: {
              'Store AcmeRelease': {
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.acme',
              },
            },
          ),
        );
      final value = _load(project).bundleIdFor(
        const BrandConfig(id: 'acme', iosConfiguration: 'Store AcmeRelease'),
      );
      expect(value.value, 'com.example.acme');
    });
  });
}
