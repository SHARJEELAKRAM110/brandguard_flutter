/// Where a statically resolved platform value applies.
enum ValueScope {
  /// The value comes from configuration specific to the brand's flavor or
  /// build configuration, so it is what that brand's build will use.
  flavor,

  /// The value comes from configuration shared by all brands (for example
  /// `defaultConfig` in a project without product flavors).
  shared,

  /// The project declares flavors or configurations, but none for this
  /// brand.
  flavorMissing,
}

/// A value read from platform project files.
class ResolvedValue {
  /// Creates a resolved value.
  const ResolvedValue({
    required this.scope,
    required this.origin,
    this.value,
    this.file,
    this.line,
    this.unresolvedReason,
    this.available = const [],
  });

  /// Creates a value for a brand whose flavor/configuration was not found.
  const ResolvedValue.flavorMissing({
    required this.origin,
    required this.available,
    this.file,
  }) : scope = ValueScope.flavorMissing,
       value = null,
       line = null,
       unresolvedReason = null;

  /// The resolved value, or `null` when it could not be resolved.
  final String? value;

  /// Applicability of [value].
  final ValueScope scope;

  /// Human-readable description of where the value came from, e.g.
  /// `productFlavors.acme.applicationId`.
  final String origin;

  /// File the value (or the unresolvable expression) was found in.
  final String? file;

  /// Line in [file].
  final int? line;

  /// Why [value] is `null`, when it was found but could not be resolved.
  final String? unresolvedReason;

  /// Flavors or configurations that do exist, for [ValueScope.flavorMissing].
  final List<String> available;

  /// Whether a concrete value was resolved.
  bool get isResolved => value != null;
}
