#!/usr/bin/env bash
# Builds the Flutter web app into site/app so the whole website (landing, login, signup, app) is one folder.
# Usage: scripts/build-site.sh            then:  npx wrangler pages deploy site --project-name kontena
set -euo pipefail
cd "$(dirname "$0")/.."
(cd app && flutter pub get && flutter build web --release --base-href /app/ \
  --dart-define=API_URL="${API_URL:-https://api.kontena.app}" \
  --dart-define=SITE_URL="${SITE_URL:-https://kontena.app}" \
  --dart-define=APP_URL="${APP_URL:-https://kontena.app/app}" \\
  --dart-define=FCM_VAPID_KEY=BHp-G-kHPIBZoS7j_vOlMAd3inc7s6p-8lG4D34CkVFBG33YgWUT6RSV_5C7QfjQPVe2PUIB9WFdueryzCjvkf4)
rm -rf site/app
cp -R app/build/web site/app
echo "Built. Check site/assets/config.js has your Firebase web config, then deploy:"
echo "  npx wrangler pages deploy site --project-name kontena"
