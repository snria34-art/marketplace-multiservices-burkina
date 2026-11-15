bool _matchesRoute(String path, String base) {
  return path == base || path.startsWith('$base/');
}

bool isAdminRoute(String path) => _matchesRoute(path, '/admin');

bool isModerationRoute(String path) {
  return path == '/admin/catalog-moderation' ||
      path == '/admin/reviews';
}

bool isSellerRoute(String path) => _matchesRoute(path, '/seller');

bool isCourierRoute(String path) => path == '/courier';

bool routeRequiresAuthentication(String path) {
  return _matchesRoute(path, '/cart') ||
      _matchesRoute(path, '/checkout') ||
      _matchesRoute(path, '/orders') ||
      _matchesRoute(path, '/delivery') ||
      _matchesRoute(path, '/follows') ||
      _matchesRoute(path, '/group-buy') ||
      _matchesRoute(path, '/messages') ||
      _matchesRoute(path, '/notifications') ||
      isAdminRoute(path) ||
      isSellerRoute(path) ||
      isCourierRoute(path);
}

/// Only accepts an internal application location.
///
/// This value comes from a URL query parameter and must never become an
/// external redirect or a redirect loop back to the login/status pages.
String? sanitizeInternalLocation(String? value) {
  if (value == null || value.isEmpty) return null;

  // Validate the raw path before Uri.tryParse: Dart normalizes literal dot
  // segments, so checking only uri.pathSegments misses "/a/../admin".
  final rawPath = value.split(RegExp(r'[?#]')).first;
  final backslash = String.fromCharCode(92);
  if (!rawPath.startsWith('/') ||
      rawPath.startsWith('//') ||
      rawPath.contains(backslash)) {
    return null;
  }

  for (final rawSegment in rawPath.split('/')) {
    var segment = rawSegment;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (segment == '.' || segment == '..') return null;

      String decoded;
      try {
        decoded = Uri.decodeComponent(segment);
      } on FormatException {
        return null;
      }

      if (decoded == segment) break;
      if (decoded.contains('/') || decoded.contains(backslash)) return null;
      segment = decoded;
    }
    if (segment == '.' || segment == '..') return null;
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path == '/auth' ||
      uri.path == '/access-status' ||
      uri.pathSegments.any((segment) => segment == '..')) {
    return null;
  }

  return uri.toString();
}
