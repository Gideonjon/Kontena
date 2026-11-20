#!/usr/bin/env bash
# Run once from app/ after `flutter create --platforms=android,ios,web .`
# Copies the Kontena icon into the Android and iOS projects. (Alternative: `dart run flutter_launcher_icons`.)
set -e
cp -R platform_icons/android/res/. android/app/src/main/res/
rm -rf ios/Runner/Assets.xcassets/AppIcon.appiconset
cp -R platform_icons/ios/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon.appiconset
echo "Icons installed."
