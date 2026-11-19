# syntax=docker/dockerfile:1
FROM debian:bookworm-slim AS build

ARG SUPABASE_URL
ARG SUPABASE_PUBLISHABLE_KEY
ENV SUPABASE_URL=${SUPABASE_URL}
ENV SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}
ENV CI=true
ENV PATH="/opt/flutter/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils zip libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    test -n "${SUPABASE_URL}"; \
    test -n "${SUPABASE_PUBLISHABLE_KEY}"; \
    case "${SUPABASE_URL}" in https://*.supabase.co) ;; *) echo "Invalid SUPABASE_URL" >&2; exit 1 ;; esac; \
    curl --fail --location --silent --show-error --retry 3 \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.2-stable.tar.xz" \
      -o /tmp/flutter.tar.xz; \
    echo "447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185  /tmp/flutter.tar.xz" | sha256sum --check --status; \
    mkdir -p /opt; tar -xJf /tmp/flutter.tar.xz -C /opt; rm /tmp/flutter.tar.xz

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --enable-web && flutter pub get --enforce-lockfile
COPY . .
RUN flutter build web --release \
    --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY}"

FROM nginx:stable-alpine AS runtime
ENV PORT=8080
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 8080
