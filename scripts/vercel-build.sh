#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL doit être configurée dans Vercel}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY doit être configurée dans Vercel}"

case "$SUPABASE_URL" in
  https://*.supabase.co) ;;
  *) echo "SUPABASE_URL doit être une URL HTTPS Supabase." >&2; exit 1 ;;
esac

FLUTTER_VERSION="3.47.2"
FLUTTER_SHA256="447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185"
SDK_ROOT="${HOME}/.cache/marketplace-flutter-${FLUTTER_VERSION}"

if [[ ! -x "${SDK_ROOT}/bin/flutter" ]]; then
  mkdir -p "$(dirname "${SDK_ROOT}")"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT
  ARCHIVE="${TMP_DIR}/flutter.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  echo "Téléchargement du SDK Flutter ${FLUTTER_VERSION}…"
  curl --fail --location --silent --show-error --retry 3 "${URL}" -o "${ARCHIVE}"
  echo "${FLUTTER_SHA256}  ${ARCHIVE}" | sha256sum --check --status
  mkdir -p "${TMP_DIR}/unpack"
  tar -xJf "${ARCHIVE}" -C "${TMP_DIR}/unpack"
  mv "${TMP_DIR}/unpack/flutter" "${SDK_ROOT}"
fi

export PATH="${SDK_ROOT}/bin:${PATH}"
export CI=true
flutter config --enable-web
flutter --version
flutter pub get --enforce-lockfile
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY}"
