#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  print -u2 'Usage: scripts/build-app.sh [release|debug]'
  exit 2
fi
swift build -c "$configuration" --arch arm64 --product FreeCell
binary_dir="$(swift build -c "$configuration" --arch arm64 --show-bin-path)"
app_dir="$PWD/build/FreeCell.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/FreeCell" "$app_dir/Contents/MacOS/FreeCell"
# Store resources in a standard bundle location so ad-hoc signing can seal the app.
cp -R "$binary_dir/FreeCell_FreeCellApp.bundle" "$app_dir/Contents/Resources/"
cp App/Info.plist "$app_dir/Contents/Info.plist"
if [[ -f App/FreeCell.icns ]]; then cp App/FreeCell.icns "$app_dir/Contents/Resources/FreeCell.icns"; fi
cp App/IconSources/ATTRIBUTION.txt "$app_dir/Contents/Resources/Icon-Attribution.txt"
cp LICENSE "$app_dir/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --deep --sign - "$app_dir"
print "Built: $app_dir"
