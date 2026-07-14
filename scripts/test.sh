#!/usr/bin/env bash
# Single local entrypoint for shelfseer's checks — mirrors .github/workflows/ci.yml
# (job `swift`, working-directory: app). Run before a push.
set -euo pipefail
cd "$(dirname "$0")/../app"
swift --version
swift build
swift run ShelfseerTests
