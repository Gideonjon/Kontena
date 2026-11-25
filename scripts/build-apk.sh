#!/usr/bin/env bash
# Builds the Android APK and puts it where the website's download button expects it.
# Usage (from the project root):  bash scripts/build-apk.sh      then:  firebase deploy --only hosting
set -euo pipefail
cd "$(dirname "$0")/.."
API_URL="${API_URL:-https://kontena-api.purpose-money-api.workers.dev}"
SITE_URL="${SITE_URL:-https://usekontena.web.app}"
APP_URL="${APP_URL:-https://usekontena.web.app/app}"
if [ ! -f app/android/key.properties ]; then
  echo "WARNING: app/android/key.properties not found. Building with the debug key. See docs/ANDROID.md to create a release key."
fi
(cd app && flutter pub get && flutter build apk --release \
  --dart-define=API_URL="$API_URL" --dart-define=SITE_URL="$SITE_URL" --dart-define=APP_URL="$APP_URL")
mkdir -p site/downloads
cp app/build/app/outputs/flutter-apk/app-release.apk site/downloads/kontena.apk
ls -lh site/downloads/kontena.apk
echo "Done. Deploy with:  firebase deploy --only hosting"
