#!/bin/sh
set -eu
project_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
cd "$project_dir"
xcrun --sdk macosx swiftc -O RocoDex/Scanner/ReferenceSearch.swift RocoDex/Scanner/SpiritRecognizer.swift RocoDex/Scanner/LocalArtLocator.swift Tools/BuildScanIndex.swift -o "$temp_dir/index"
"$temp_dir/index" RocoDex/Resources
