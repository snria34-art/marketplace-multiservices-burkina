#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_USER_HOME="${GRADLE_USER_HOME:-${HOME}/.gradle}"
INIT_DIRECTORY="${GRADLE_USER_HOME}/init.d"
INIT_FILE="${INIT_DIRECTORY}/marketplace-plugin-repositories.gradle"

mkdir -p "${INIT_DIRECTORY}"
install -m 0644 \
  "${REPOSITORY_ROOT}/android/gradle-plugin-repositories.init.gradle" \
  "${INIT_FILE}"

printf 'Gradle plugin repositories configured: %s\n' "${INIT_FILE}"
