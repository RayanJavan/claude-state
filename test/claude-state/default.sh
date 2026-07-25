#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# converge/verify already ran via postCreateCommand with RESTIC_PASSWORD set,
# so the repo must be initialised and verify must be clean.
check "repository was initialised by postCreateCommand" bash -lc \
  'claude-state-daemon-ensure && restic cat config >/dev/null'
check "verify passes with the repo configured" bash -lc \
  'claude-state-daemon-ensure && claude-state verify'
check "snapshot succeeds" bash -lc \
  'claude-state-daemon-ensure && claude-state snapshot'
check "drill passes against the real repository" bash -lc \
  'claude-state-daemon-ensure && claude-state drill'

reportResults
