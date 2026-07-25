#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# converge already ran via postCreateCommand with RESTIC_PASSWORD set, so the
# repo must be initialised and verify must be clean. Asserted through
# claude-state, not a bare `restic` call: restic is bundled inside the
# writeShellApplication wrapper's own runtime PATH, not exposed as a
# standalone binary in the profile — claude-state is the only interface this
# feature promises.
#
# claude-state-daemon-ensure runs once here rather than before each check:
# it's idempotent and the daemon it starts persists for the container's
# lifetime, so per-check invocations would be redundant.
claude-state-daemon-ensure

check "verify passes with the repo configured" bash -lc 'claude-state verify'
check "snapshot succeeds" bash -lc 'claude-state snapshot'
check "drill passes against the real repository" bash -lc 'claude-state drill'

reportResults
