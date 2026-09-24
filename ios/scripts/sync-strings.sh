#!/bin/zsh
# Syncs LocalTrivia/Localizable.xcstrings with the strings the compiler
# extracts — what Xcode's IDE does on build, and command-line builds don't.
#
# Both the app and the DesignSystem package are extracted: the package is
# linked statically and looks its strings up in the app's bundle. Release, so
# debug-only prototypes and previews stay out. New strings are added, strings
# no longer in the code are removed (or marked stale if they're translated).
#
#   ios/scripts/sync-strings.sh
set -euo pipefail

ios=${0:A:h:h}
derived=$(mktemp -d -t sync-strings)
trap 'rm -rf "$derived"' EXIT

cd "$ios"
if ! xcodebuild build -project LocalTrivia.xcodeproj -scheme LocalTrivia -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
  SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO >"$derived/build.log" 2>&1; then
  tail -40 "$derived/build.log"
  exit 1
fi

strings=(${(f)"$(find "$derived/Build/Intermediates.noindex" -name '*.stringsdata' \
  \( -path '*/LocalTrivia.build/Objects-normal/*' -o -path '*/DesignSystem.build/*' \) \
  -not -name 'ExtractedAppShortcutsMetadata.stringsdata')"})
xcrun xcstringstool sync LocalTrivia/Localizable.xcstrings --stringsdata $strings
echo "Synced Localizable.xcstrings from ${#strings} source files."
