#!/bin/zsh
# Syncs LocalTrivia/Localizable.xcstrings with the strings the compiler
# extracts — what Xcode's IDE does on build, and command-line builds don't.
#
# Both the app and the DesignSystem package are extracted: the package is
# linked statically and looks its strings up in the app's bundle. Release, so
# debug-only prototypes and previews stay out. New strings are added, strings
# no longer in the code are removed (or marked stale if they're translated).
#
# Xcode's own sync, on every build in the IDE, sees only the app target, so it
# would delete the package's strings. They're marked "manual", which Xcode
# leaves alone; this script keeps that set in step with the package, adding
# new ones and dropping ones it no longer uses. Nothing else is manual.
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
package=(${(M)strings:#*/DesignSystem.build/*})
catalog=LocalTrivia/Localizable.xcstrings

# The package's strings alone: synced into an empty catalog, named as the
# app's is, or the tool matches none of them to it.
mkdir "$derived/package"
print '{ "sourceLanguage" : "en", "strings" : {}, "version" : "1.0" }' >"$derived/package/Localizable.xcstrings"
xcrun xcstringstool sync "$derived/package/Localizable.xcstrings" --stringsdata $package

xcrun xcstringstool sync $catalog --stringsdata $strings
python3 - $catalog "$derived/package/Localizable.xcstrings" <<'EOF'
import json, re, sys
catalog, package = sys.argv[1:]
owned = set(json.load(open(package))["strings"])
data = json.load(open(catalog))
strings = data["strings"]
for key in list(strings):
    if key in owned:
        strings[key]["extractionState"] = "manual"
    elif strings[key].get("extractionState") == "manual":
        del strings[key]
# As Xcode writes it: " : ", two-space indents, empty objects opened up.
text = json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : "))
text = re.sub(r"^( *)(.*)\{\}", lambda m: f"{m[1]}{m[2]}{{\n\n{m[1]}}}", text, flags=re.M)
open(catalog, "w").write(text)
EOF
echo "Synced Localizable.xcstrings from ${#strings} source files (${#package} in DesignSystem)."
