#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The scenario this reproduces: a devcontainer created before RESTIC_PASSWORD
# has been provisioned as a secret. Environment creation must still succeed —
# only backup-repo setup should degrade, and only after converge already ran
# once via postCreateCommand without a secret present.
#
# claude-state-daemon-ensure runs once here rather than before each check —
# see default.sh for why.
claude-state-daemon-ensure

check "claude-state is usable" bash -lc 'command -v claude-state'
check "converge succeeds with no repo configured" bash -lc 'claude-state converge'
check "verify reports the missing repo without crashing" bash -lc '! claude-state verify'

# resticRepository IS set in this scenario (the feature option default) —
# only RESTIC_PASSWORD is missing, so require_repo's actual message names
# RESTIC_PASSWORD, not RESTIC_REPOSITORY.
check "snapshot refuses clearly rather than crashing" bash -lc \
  'output=$(claude-state snapshot 2>&1); code=$?; echo "$output" | grep -q RESTIC_PASSWORD && [ "$code" -ne 0 ]'

reportResults
