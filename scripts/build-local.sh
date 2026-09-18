#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$project_root/.build-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$project_root/.build-cache/swift"
swift build --package-path "$project_root/apps/macos" --scratch-path "$project_root/.build-cache/build" --cache-path "$project_root/.build-cache/swift"
