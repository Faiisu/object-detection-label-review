#!/bin/zsh
set -eu
cd "${0:A:h}"
TEST_BINARY="$(mktemp -t label-review-test)"
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc -target arm64-apple-macosx13.0 -swift-version 5 -D TESTING Sources/Dataset.swift Sources/Canvas.swift Sources/App.swift Tests/main.swift -o "$TEST_BINARY" -framework AppKit
"$TEST_BINARY" "$@"
