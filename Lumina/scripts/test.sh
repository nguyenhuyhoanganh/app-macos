#!/bin/zsh
# Chạy test. Với Command Line Tools, SwiftPM không tự nạp plugin macro của swift-testing
# (nằm trong host/plugins/testing/), nên `swift test` trần có lúc báo
# "plugin for module 'TestingMacros' not found". Chỉ thẳng đường dẫn plugin cho trình biên dịch.
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swift)")")"
PLUGINS="$TOOLCHAIN/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  exec swift test "$@"
fi
