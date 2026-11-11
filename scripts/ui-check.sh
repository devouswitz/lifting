#!/bin/bash
# Runs the UI tests on an iOS simulator: ./scripts/ui-check.sh ["iPhone 18 Pro"]
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-project.py > /dev/null
xcodebuild test -project Lifting.xcodeproj -scheme Setform -destination "platform=iOS Simulator,name=${1:-iPhone 18 Pro}" -only-testing:SetformUITests 2>&1 \
    | grep -E "error:|Test Case .* (passed|failed)|Executed .* tests|TEST (SUCCEEDED|FAILED)|BUILD FAILED"
