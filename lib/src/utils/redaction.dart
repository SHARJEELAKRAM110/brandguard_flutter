const _sensitiveQueryKeys = {
  'auth',
  'authorization',
  'code',
  'credential',
  'credentials',
  'key',
  'pwd',
  'passwd',
  'session',
  'sessionid',
  'sig',
  'signature',
};

/// Redacts credentials from [url] so it can be printed safely.
///
/// * User info (`user:password@`) becomes `***@`.
/// * Values of sensitive query parameters (`token`, `api_key`, `password`,
///   `signature`, ...) become `***`.
/// * The fragment is dropped.
/// * The result is truncated to [maxLength] characters.
String redactUrl(String url, {int maxLength = 160}) {
  var result = url;
  final fragment = result.indexOf('#');
  if (fragment != -1) result = result.substring(0, fragment);

  result = result.replaceFirstMapped(
    RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*://)([^/@?#]*)@'),
    (m) => '${m[1]}***@',
  );

  result = result.replaceAllMapped(RegExp(r'([?&;])([^=&;#]+)=([^&;#]*)'), (m) {
    final key = m[2]!.toLowerCase();
    final sensitive =
        _sensitiveQueryKeys.contains(key) ||
        key.contains('token') ||
        key.contains('secret') ||
        key.contains('password') ||
        key.endsWith('key');
    return sensitive ? '${m[1]}${m[2]}=***' : m[0]!;
  });

  if (result.length > maxLength) {
    result = '${result.substring(0, maxLength - 3)}...';
  }
  return result;
}
