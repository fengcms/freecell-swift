#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product FreeCell
binary_dir="$(swift build --show-bin-path)"
check_dir="$(mktemp -d /tmp/freecell-localization-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cat > "$check_dir/GameResources.swift" <<'SWIFT'
import Foundation
enum GameResources {
    static let bundle = Bundle(path: CommandLine.arguments[1])!
}
SWIFT
swiftc -parse-as-library -I "$binary_dir/Modules" \
    Sources/FreeCellApp/Localization.swift "$check_dir/GameResources.swift" \
    Sources/FreeCellApp/AppSettings.swift Sources/FreeCellApp/GameAudio.swift Sources/FreeCellApp/GameSession.swift \
    Tests/SessionChecks/SessionChecks.swift \
    "$binary_dir"/FreeCellPresentation.build/*.swift.o "$binary_dir"/FreeCellCore.build/*.swift.o \
    -o "$check_dir/SessionChecks"
"$check_dir/SessionChecks" "$binary_dir/FreeCell_FreeCellApp.bundle"
