#!/usr/bin/env bash
# Run via: devcontainer features test -f claude-state --base-image mcr.microsoft.com/devcontainers/base:bookworm
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "nix on PATH" bash -lc 'command -v nix'
check "nix daemon socket present" bash -lc 'test -S /nix/var/nix/daemon-socket/socket'
check "claude-state on PATH" bash -lc 'command -v claude-state'
check "claude-state prints usage" bash -lc 'claude-state --help | grep -q converge'
check "daemon-ensure is idempotent" bash -lc \
  'claude-state-daemon-ensure && claude-state-daemon-ensure'

reportResults
