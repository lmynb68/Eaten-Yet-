#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Run this script on a Mac with Flutter and Xcode installed.' >&2
  exit 1
fi
command -v flutter >/dev/null
xcode-select -p >/dev/null
if [[ ! -d ios ]]; then
  # Generate only the platform runner in an isolated temporary project.
  # Preserve the app's existing Dart files, assets and pubspec.
  staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/eat-what-ios.XXXXXX")
  flutter create --platforms=ios --project-name=eat_what --org=local.eatwhat --no-pub "$staging_dir"
  cp -R "$staging_dir/ios" ./ios
  echo "Template source retained at: $staging_dir"
fi
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 吃什么' ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c 'Add :NSPhotoLibraryUsageDescription string Select a photo for your personal dish.' ios/Runner/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :NSPhotoLibraryUsageDescription Select a photo for your personal dish.' ios/Runner/Info.plist
flutter pub get
flutter analyze lib test
flutter test
echo 'iOS project prepared. For a simulator build: flutter build ios --simulator'
echo 'For iPhone signing, open ios/Runner.xcworkspace in Xcode and select your team.'
