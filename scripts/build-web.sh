#!/bin/sh
set -eu

if [ -z "${SUPABASE_URL:-}" ]; then
  echo "SUPABASE_URL is required for the Flutter Web build." >&2
  exit 1
fi
if [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  echo "SUPABASE_PUBLISHABLE_KEY is required for the Flutter Web build." >&2
  exit 1
fi

case "$SUPABASE_URL" in
  https://*.supabase.co) ;;
  *)
    echo "Invalid SUPABASE_URL format." >&2
    exit 1
    ;;
esac

case "$SUPABASE_PUBLISHABLE_KEY" in
  sb_publishable_????????????*|eyJ*.*.*) ;;
  *)
    echo "SUPABASE_PUBLISHABLE_KEY must be a public publishable key or legacy anon JWT; never use a secret key or project reference." >&2
    exit 1
    ;;
esac

build_mode=${FLUTTER_BUILD_MODE:-release}
case "$build_mode" in
  release|debug) ;;
  *)
    echo "FLUTTER_BUILD_MODE must be either release or debug." >&2
    exit 1
    ;;
esac

# Do not enable shell tracing here: the publishable key is public, but build
# arguments must never be copied verbatim into CI/BuildKit command logs.
exec flutter build web "--$build_mode" \
  "--dart-define=SUPABASE_URL=$SUPABASE_URL" \
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
