import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:test/test.dart';

import '../support/project_builder.dart';

const _groovy = '''
android {
    namespace "com.example.shared"
    defaultConfig {
        // applicationId "com.commented.out"
        applicationId "com.example.base"
        manifestPlaceholders = [appName: "Base App", other: 'x']
    }
    flavorDimensions "brand"
    productFlavors {
        acme {
            dimension "brand"
            applicationId "com.example.acme"
            resValue "string", "app_name", "Acme Retail"
        }
        nova {
            dimension "brand"
            applicationIdSuffix ".nova"
            manifestPlaceholders = [appName: "Nova Store"]
        }
        dynamic {
            applicationId "com.example.\${brandSuffix}"
        }
        orbit {
            applicationId flavorIds.orbit
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
''';

const _kotlin = '''
android {
    defaultConfig {
        applicationId = "com.example.base"
        manifestPlaceholders["appName"] = "Base"
    }
    flavorDimensions += "brand"
    productFlavors {
        create("acme") {
            dimension = "brand"
            applicationId = "com.example.acme"
            resValue("string", "app_name", "Acme Retail")
            manifestPlaceholders += mapOf("appName" to "Acme Placeholder")
        }
        register("nova") {
            applicationId = "com.example.nova"
        }
    }
    buildTypes {
        getByName("release") {
            applicationIdSuffix = ".prod"
        }
    }
}
''';

AndroidProject _load(ProjectBuilder project) => AndroidProject.load(
  ProjectFiles(project.root),
  const AndroidPlatformConfig(),
)!;

void main() {
  group('Gradle parsing', () {
    test('parses Groovy flavors, placeholders and resValues', () {
      final model = AndroidGradleModel.parse({'build.gradle': _groovy});
      expect(
        model.defaultConfig!.properties['applicationId']!.literal,
        'com.example.base',
      );
      expect(model.defaultConfig!.properties['applicationId']!.line, 5);
      expect(model.defaultConfig!.placeholders['appName']!.literal, 'Base App');
      expect(model.flavors.keys, ['acme', 'nova', 'dynamic', 'orbit']);
      expect(
        model.flavors['acme']!.stringResources['app_name']!.literal,
        'Acme Retail',
      );
      expect(
        model.flavors['nova']!.properties['applicationIdSuffix']!.literal,
        '.nova',
      );
      expect(
        model.flavors['dynamic']!.properties['applicationId']!.literal,
        isNull,
      );
      expect(
        model.flavors['orbit']!.properties['applicationId']!.raw,
        'flavorIds.orbit',
      );
      expect(model.buildTypes.keys, ['release']);
    });

    test('parses Kotlin DSL create/register/getByName blocks', () {
      final model = AndroidGradleModel.parse({'build.gradle.kts': _kotlin});
      expect(model.flavors.keys, ['acme', 'nova']);
      expect(
        model.flavors['acme']!.placeholders['appName']!.literal,
        'Acme Placeholder',
      );
      expect(model.defaultConfig!.placeholders['appName']!.literal, 'Base');
      expect(
        model.buildTypes['release']!.properties['applicationIdSuffix']!.literal,
        '.prod',
      );
    });
  });

  group('AndroidProject resolution', () {
    test('resolves flavor IDs, suffixes and unresolvable expressions', () {
      final project = ProjectBuilder()
        ..file('android/app/build.gradle', _groovy);
      final android = _load(project);

      final acme = android.applicationIdFor('acme');
      expect(acme.value, 'com.example.acme');
      expect(acme.scope, ValueScope.flavor);
      expect(acme.file, 'android/app/build.gradle');

      expect(android.applicationIdFor('nova').value, 'com.example.base.nova');

      final dynamic = android.applicationIdFor('dynamic');
      expect(dynamic.value, isNull);
      expect(dynamic.unresolvedReason, contains('cannot be resolved'));

      final orbit = android.applicationIdFor('orbit');
      expect(orbit.value, isNull);
      expect(orbit.unresolvedReason, contains('flavorIds.orbit'));

      final missing = android.applicationIdFor('zenith');
      expect(missing.scope, ValueScope.flavorMissing);
      expect(missing.available, ['acme', 'dynamic', 'nova', 'orbit']);
    });

    test('applies the release build type suffix', () {
      final project = ProjectBuilder()
        ..file('android/app/build.gradle.kts', _kotlin);
      expect(
        _load(project).applicationIdFor('acme').value,
        'com.example.acme.prod',
      );
    });

    test('ignores namespace and commented-out applicationId', () {
      final model = AndroidGradleModel.parse({'b.gradle': _groovy});
      expect(
        model.defaultConfig!.properties['applicationId']!.literal,
        isNot('com.commented.out'),
      );
    });

    test('resolves app names from resValue, placeholders and strings.xml', () {
      final project = ProjectBuilder()
        ..file('android/app/build.gradle', _groovy)
        ..file(
          'android/app/src/main/AndroidManifest.xml',
          '<manifest><application android:label="@string/app_name" '
              'android:icon="@mipmap/ic_launcher"></application></manifest>',
        )
        ..file(
          'android/app/src/orbit/res/values/strings.xml',
          '<resources><string name="app_name">Orbit &amp; Co</string></resources>',
        );
      final android = _load(project);
      expect(android.appNameFor('acme').value, 'Acme Retail');
      expect(android.appNameFor('orbit').value, 'Orbit & Co');
      expect(
        android.appNameFor('orbit').file,
        'android/app/src/orbit/res/values/strings.xml',
      );
      final nova = android.appNameFor('nova');
      expect(nova.value, isNull);
      expect(nova.unresolvedReason, contains('app_name'));
    });

    test('resolves manifest placeholders', () {
      final project = ProjectBuilder()
        ..file('android/app/build.gradle', _groovy)
        ..file(
          'android/app/src/main/AndroidManifest.xml',
          '<manifest><application\n android:label="\${appName}"></application></manifest>',
        );
      final android = _load(project);
      expect(android.appNameFor('nova').value, 'Nova Store');
      // acme has no placeholder of its own and inherits defaultConfig's.
      final acme = android.appNameFor('acme');
      expect(acme.value, 'Base App');
      expect(acme.origin, 'defaultConfig.manifestPlaceholders[appName]');
      expect((acme.file, acme.line), ('android/app/build.gradle', 6));
    });

    test('returns null when there is no Android module', () {
      final project = ProjectBuilder();
      expect(
        AndroidProject.load(
          ProjectFiles(project.root),
          const AndroidPlatformConfig(),
        ),
        isNull,
      );
    });
  });
}
