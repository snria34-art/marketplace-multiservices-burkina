import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every GoRouter route is served by a Vercel SPA rewrite', () async {
    final routerSource =
        await File('lib/core/routing/app_router.dart').readAsString();
    final vercelConfig = jsonDecode(
      await File('vercel.json').readAsString(),
    ) as Map<String, dynamic>;
    final rewrites = (vercelConfig['rewrites'] as List)
        .cast<Map<String, dynamic>>();

    final routePaths = RegExp(r"path:\s*'([^']+)'")
        .allMatches(routerSource)
        .map((match) => match.group(1)!)
        .where((path) => path != '/')
        .toSet();

    expect(routePaths, isNotEmpty, reason: 'No GoRouter paths were found.');

    bool isCoveredByRewrite(String routePath) {
      for (final rewrite in rewrites) {
        if (rewrite['destination'] != '/index.html') continue;

        final source = rewrite['source'] as String;
        if (source == routePath) return true;

        const wildcardSuffix = '/:path*';
        if (source.endsWith(wildcardSuffix)) {
          final basePath =
              source.substring(0, source.length - wildcardSuffix.length);
          if (routePath.startsWith('$basePath/')) return true;
        }
      }
      return false;
    }

    for (final declaredPath in routePaths) {
      final browserPath = declaredPath.replaceAll(
        RegExp(r':[^/]+'),
        'route-test-value',
      );
      expect(
        isCoveredByRewrite(browserPath),
        isTrue,
        reason: 'Vercel has no SPA rewrite for GoRouter path $declaredPath '
            '(tested as $browserPath).',
      );
    }
  });
}
