#!/bin/bash
# Runs the test suite with Command Line Tools only: Testing.framework and its
# macro plugin live outside the default search paths when Xcode is not installed.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=/Library/Developer/CommandLineTools
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
exec swift test --build-system native \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xswiftc -plugin-path -Xswiftc "$DEV/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
