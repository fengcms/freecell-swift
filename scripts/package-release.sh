#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-app.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
output_dir="$PWD/build/releases/$version"
archive_name="FreeCell-$version-macOS-AppleSilicon.zip"
mkdir -p "$output_dir"
codesign --verify --deep --strict build/FreeCell.app
[[ "$(lipo -archs build/FreeCell.app/Contents/MacOS/FreeCell)" == "arm64" ]]
ditto -c -k --sequesterRsrc --keepParent build/FreeCell.app "$output_dir/$archive_name"
(cd "$output_dir" && shasum -a 256 "$archive_name" > SHA256SUMS.txt)
print "Release archive: $output_dir/$archive_name"
