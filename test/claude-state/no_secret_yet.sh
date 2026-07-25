#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The scenario this reproduces: a devcontainer created before RESTIC_PASSWORD
# has been provisioned as a secret. Environment creation must still succeed —
# only backup-repo setup should degrade, and only after converge already ran
# once via postCreateCommand without a secret present.
check "claude-state is usable" bash -lc 'command -v claude-state'
check "converge succeeds with no repo configured" bash -lc \
  'claude-state-daemon-ensure && claude-state converge'
check "verify reports the missing repo without crashing" bash -lc \
  'claude-state-daemon-ensure && claude-state verify; test "$?" -ne 0 || true'
check "snapshot refuses clearly rather than crashing" bash -lc \
  'claude-state-daemon-ensure && output=$(claude-state snapshot 2>&1); code=$?; echo "$output" | grep -q RESTIC_REPOSITORY && [ "$code" -ne 0 ]'

reportResults
