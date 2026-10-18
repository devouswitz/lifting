#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
python3 - <<'PY'
from pathlib import Path
import re
tests=Path('Tests/LiftingCoreTests/TrainingTests.swift').read_text()
names=re.findall(r'func (test\w+)\(\)( throws)?',tests)
lines=['import Foundation', '@main struct CoreCheckRunner { static func main() {', 'let tests = TrainingTests()']
for name, throwing in names:
    if throwing:
        lines.append(f'do {{ try tests.{name}() }} catch {{ failedChecks += 1; print("FAIL {name}: \\(error)") }}')
    else:
        lines.append(f'tests.{name}()')
lines += [f'print("{len(names)} test cases; \\(failedChecks) failures")', 'exit(failedChecks == 0 ? 0 : 1)', '}}']
Path('.build/checks/Runner.swift').write_text('\n'.join(lines))
PY
swiftc -swift-version 5 -D STANDALONE_CHECKS -parse-as-library Sources/LiftingCore/*.swift Checks/Compatibility.swift Tests/LiftingCoreTests/TrainingTests.swift .build/checks/Runner.swift -o .build/checks/CoreChecks
.build/checks/CoreChecks
