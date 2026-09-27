#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
# Command Line Tools do not include XCTest; this small harness needs only Swift.
swiftc Sources/VoiceInputCore/Session.swift Tests/VoiceInputCoreTests/SessionTests.swift -o .build/checks/session-tests
.build/checks/session-tests
