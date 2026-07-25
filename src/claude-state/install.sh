#!/usr/bin/env bash
# Installs Nix (no systemd assumed — this feature targets Codespaces, which has
# none) and fetches claude-state from the flake at $FLAKEREF. Everything below
# is infrastructure: it makes the CLI reachable and keeps the daemon alive. No
# path is classified here — that decision lives only in classification.nix
# inside the flake.
set -euo pipefail

FLAKEREF="${FLAKEREF:-github:RayanJavan/claude-state}"
RESTICREPOSITORY="${RESTICREPOSITORY:-/workspaces/.claude-state-backup}"
CLAUDECONFIGDIR="${CLAUDECONFIGDIR:-/workspaces/.claude-data}"

REMOTE_USER="${_REMOTE_USER:-node}"
REMOTE_HOME="${_REMOTE_USER_HOME:-/home/$REMOTE_USER}"

echo "claude-state feature: installing Nix (single-daemon, no systemd)"

if [ ! -d /nix ]; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install linux --init none --no-confirm
else
  echo "claude-state feature: /nix already present (mounted volume) — skipping install"
fi

# The daemon has no init system to supervise it here, so a helper starts it
# idempotently. Lifecycle commands call this before every converge/verify.
install -d /usr/local/bin
cat > /usr/local/bin/claude-state-daemon-ensure <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SOCK=/nix/var/nix/daemon-socket/socket
if [ ! -S "$SOCK" ]; then
  sudo -b /nix/var/nix/profiles/default/bin/nix-daemon >/var/log/nix-daemon.log 2>&1
  for _ in $(seq 1 50); do
    [ -S "$SOCK" ] && break
    sleep 0.1
  done
fi
SCRIPT
chmod +x /usr/local/bin/claude-state-daemon-ensure

# Every login shell needs nix on PATH and pointed at the daemon.
cat > /etc/profile.d/99-claude-state-nix.sh <<'PROFILE'
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
export CLAUDE_STATE_FLAKEREF="__FLAKEREF__"
export RESTIC_REPOSITORY="__RESTICREPOSITORY__"
export CLAUDE_CONFIG_DIR="__CLAUDECONFIGDIR__"
PROFILE
sed -i "s|__FLAKEREF__|${FLAKEREF}|; s|__RESTICREPOSITORY__|${RESTICREPOSITORY}|; s|__CLAUDECONFIGDIR__|${CLAUDECONFIGDIR}|" \
  /etc/profile.d/99-claude-state-nix.sh

/usr/local/bin/claude-state-daemon-ensure

# The CLI is installed into the remote user's Nix profile, not root's — every
# lifecycle command and interactive shell runs as $REMOTE_USER.
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
sudo -u "$REMOTE_USER" -H bash -lc \
  "nix profile install '${FLAKEREF}#claude-state' --extra-experimental-features 'nix-command flakes'"

# nix profile installs to ~/.nix-profile/bin, which the daemon.sh above does
# not add to PATH by itself — link it somewhere already on everyone's PATH.
ln -sfn "${REMOTE_HOME}/.nix-profile/bin/claude-state" /usr/local/bin/claude-state

echo "claude-state feature: installed. RESTIC_PASSWORD must still be supplied as a secret."
