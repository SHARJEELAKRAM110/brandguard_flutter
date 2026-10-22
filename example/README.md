# brandguard_flutter examples

## Sample white-label project

[`sample_white_label_project/`](sample_white_label_project/) is a real
`flutter create` project (Android and iOS) with two **fictional** brands that
share one codebase:

| | `acme` — Acme Retail | `nova` — Nova Store (**intentionally broken**) |
| --- | --- | --- |
| Android flavor | `com.example.acme`, "Acme Retail" | `com.example.nova`, but app name "Nova Shop" ✗ |
| iOS `Release-<brand>` | `com.example.acme`, "Acme Retail" | bundle ID copied from Acme ✗ |
| Assets | icon and logo | logo missing ✗, icon is a byte copy of Acme's ⚠ |
| Locales | en, es (complete) | en, fr: `checkoutConfirm` missing ✗, `{nom}` instead of `{name}` ✗ |
| Production config | `api.acme-retail.example` | `staging-api.novastore.example` ✗ |

The `staging.json` files contain staging URLs on purpose. They are not
scanned for production brands, which shows how BrandGuard avoids false
positives.

Run it from the package root:

```bash
dart run brandguard_flutter check --project example/sample_white_label_project
```

Or from inside the sample (it has `brandguard_flutter` as a path dev
dependency):

```bash
cd example/sample_white_label_project
flutter pub get
dart run brandguard_flutter check --brand acme   # exit code 0
dart run brandguard_flutter check --brand nova   # exit code 1
dart run brandguard_flutter check --format json
```

The full text output is shown in the package README under "Output formats".

## Programmatic use

```dart
import 'package:brandguard_flutter/brandguard_flutter.dart';

void main() {
  final guard = BrandGuard();
  final config = guard.loadConfig(
    projectDirectory: 'example/sample_white_label_project',
  );
  final result = guard.validate(config);
  print('${result.count(Severity.error)} errors; passed: ${result.passed}');
}
```
