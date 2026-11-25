#!/usr/bin/env bash
# Builds the Android APK and puts it where the website's download button expects it.
# Usage (from the project root):  bash scripts/build-apk.sh      then:  firebase deploy --only hosting
set -euo pipefail
cd "$(dirname "$0")/.."
API_URL="${API_URL:-https://kontena-api.purpose-money-api.workers.dev}"
SITE_URL="${SITE_URL:-https://kontena.store}"
APP_URL="${APP_URL:-https://kontena.store/app}"
if [ ! -f app/android/key.properties ]; then
  echo "WARNING: app/android/key.properties not found. Building with the debug key. See docs/ANDROID.md to create a release key."
fi
(cd app && flutter pub get && flutter build apk --release \
  --dart-define=API_URL="$API_URL" --dart-define=SITE_URL="$SITE_URL" --dart-define=APP_URL="$APP_URL")
# Firebase's free plan refuses .apk files, so the APK is stored in Cloudflare R2 and served by the Worker
# at /download/kontena.apk (deploy the Worker once: cd backend && npx wrangler deploy).
APK=app/build/app/outputs/flutter-apk/app-release.apk
ls -lh "$APK"
(cd backend && npx wrangler r2 object put kontena-media/downloads/kontena.apk --file "../$APK" --content-type application/vnd.android.package-archive --remote)
echo "Done. Download link: $API_URL/download/kontena.apk"
