#!/usr/bin/env bash
# Builds the Flutter web app on Vercel, which has no Flutter preinstalled.
# Needs Vercel env vars SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (both public).
set -euo pipefail
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  echo "Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Vercel → Settings → Environment Variables." >&2
  exit 1
fi
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
flutter config --no-analytics >/dev/null
flutter pub get
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
