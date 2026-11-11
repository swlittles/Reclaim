#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run ReclaimCoreTests
python3 -m unittest discover -s Tests/ReleaseTests -p 'test_*.py'
