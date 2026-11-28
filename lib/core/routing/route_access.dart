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
      isCourierRoute(path) ||
      _matchesRoute(path, '/provider');
}

/// Only accepts an internal application location.
///
/// This value comes from a URL query parameter and must never become an
/// external redirect or a redirect loop back to the login/status pages.
bool _hasUnsafePathSegment(String value) {
  final rawPath = value.split(RegExp(r'[?#]')).first;
  for (final rawSegment in rawPath.split('/')) {
    var decoded = rawSegment;
    try {
      // Decode repeatedly so double-encoded dot segments and separators are
      // rejected before Uri normalizes away the original traversal.
      for (var attempt = 0; attempt < 3; attempt++) {
        final next = Uri.decodeComponent(decoded);
        if (next == decoded) break;
        decoded = next;
      }
    } on FormatException {
      return true;
    }

    if (decoded == '.' ||
        decoded == '..' ||
        decoded.contains('/') ||
        decoded.contains('\\')) {
      return true;
    }
  }
  return false;
}

String? sanitizeInternalLocation(String? value) {
  if (value == null || value.isEmpty || _hasUnsafePathSegment(value)) {
    return null;
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
