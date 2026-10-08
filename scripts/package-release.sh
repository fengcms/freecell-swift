#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-app.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
output_dir="$PWD/build/releases/$version"
archive_name="FreeCell-$version-macOS-AppleSilicon.zip"
disk_image_name="FreeCell-$version-macOS-AppleSilicon.dmg"
staging_dir="$output_dir/dmg-staging"
mkdir -p "$output_dir"
codesign --verify --deep --strict build/FreeCell.app
[[ "$(lipo -archs build/FreeCell.app/Contents/MacOS/FreeCell)" == "arm64" ]]
ditto -c -k --sequesterRsrc --keepParent build/FreeCell.app "$output_dir/$archive_name"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
ditto build/FreeCell.app "$staging_dir/FreeCell.app"
ln -s /Applications "$staging_dir/Applications"
rm -f "$output_dir/$disk_image_name"
hdiutil create -quiet -volname "FreeCell $version" -srcfolder "$staging_dir" \
  -ov -format UDZO "$output_dir/$disk_image_name"
rm -rf "$staging_dir"
(cd "$output_dir" && shasum -a 256 "$archive_name" "$disk_image_name" > SHA256SUMS.txt)
print "Release archive: $output_dir/$archive_name"
print "Release disk image: $output_dir/$disk_image_name"
