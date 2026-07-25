
# claude-state — reconstruct, verify, snapshot and restore an agent's state.
#
# Five verbs, each with a contract that does not bend:
#
#   converge   reconstructs from declarations only; touches nothing undeclared
#   verify     asserts and reports; writes nothing, ever
#   snapshot   backs up everything not classified as derived/ephemeral/secret
#   restore    restores to a target directory; never over live state
#   drill      proves the repository can actually be restored from
#
# CLASSIFICATION_DIR is baked in at build time by default.nix.

shopt -s dotglob nullglob

ok()   { printf '  ok   %s\n' "$*"; }
warn() { printf '  warn %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }
die()  { printf 'claude-state: %s\n' "$*" >&2; exit 2; }

WORKDIR=""
cleanup() {
  if [ -n "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

workdir() {
  if [ -z "$WORKDIR" ]; then
    WORKDIR="$(mktemp -d)"
  fi
  printf '%s' "$WORKDIR"
}

state_dir() {
  printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

mapfile -t CLASSIFIED_GLOBS < "$CLASSIFICATION_DIR/classified-globs.txt"
mapfile -t EXCLUDED_GLOBS   < "$CLASSIFICATION_DIR/excluded-globs.txt"

# A path is classified if it matches a glob exactly. Globs are deliberately
# unquoted on the right-hand side of == so that pattern matching happens.
matches_classified() {
  local rel="$1" glob
  for glob in "${CLASSIFIED_GLOBS[@]}"; do
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2053
    if [[ "$rel" == $glob ]]; then
      return 0
    fi
  done
  return 1
}

matches_excluded() {
  local rel="$1" glob
  for glob in "${EXCLUDED_GLOBS[@]}"; do
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2053
    if [[ "$rel" == $glob ]]; then
      return 0
    fi
  done
  return 1
}

# True when some glob classifies something *inside* this directory, meaning the
# directory is partially classified and we must descend rather than report it.
has_classified_descendant() {
  local rel="$1" glob
  for glob in "${CLASSIFIED_GLOBS[@]}"; do
    case "$glob" in
      "$rel"/*) return 0 ;;
    esac
  done
  return 1
}

UNCLASSIFIED=()

# Walks the state directory, reporting the shallowest unclassified paths.
# Descends only where a directory is partially classified, so a fully
# classified subtree costs one comparison rather than a full traversal.
scan_unclassified() {
  local dir="$1" prefix="$2" entry rel base
  for entry in "$dir"/*; do
    base="$(basename "$entry")"
    rel="${prefix}${base}"
    if matches_classified "$rel"; then
      continue
    fi
    if [ -d "$entry" ] && [ ! -L "$entry" ] && has_classified_descendant "$rel"; then
      scan_unclassified "$entry" "$rel/"
      continue
    fi
    UNCLASSIFIED+=("$rel")
  done
}

require_repo() {
  [ -n "${RESTIC_REPOSITORY:-}" ] || die "RESTIC_REPOSITORY is not set"
  if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
    die "neither RESTIC_PASSWORD nor RESTIC_PASSWORD_FILE is set"
  fi
}

repo_initialised() {
  restic cat config >/dev/null 2>&1
}

# Renders the runtime exclude file. Globs are relative in the manifest and
# absolute here, because restic matches against full paths.
render_exclude_file() {
  local dir="$1" out glob
  out="$(workdir)/excludes.txt"
  : > "$out"
  for glob in "${EXCLUDED_GLOBS[@]}"; do
    [ -n "$glob" ] || continue
    printf '%s/%s\n' "$dir" "$glob" >> "$out"
  done
  printf '%s' "$out"
}

cmd_converge() {
  local dir
  dir="$(state_dir)"

  section "[claude-state] converge — reconstructs from declarations only"

  # The state directory is the core promise and must always succeed.
  # Backup-repo setup is a separate concern: an environment that has never had
  # RESTIC_PASSWORD provisioned yet should still be usable, so this degrades to
  # a warning rather than blocking container creation entirely.
  if [ -d "$dir" ]; then
    ok "state directory present: $dir"
  else
    mkdir -p "$dir"
    ok "created state directory: $dir"
  fi

  if [ -z "${RESTIC_REPOSITORY:-}" ] || { [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; }; then
    warn "backup repository not configured (RESTIC_REPOSITORY / RESTIC_PASSWORD unset)"
    warn "state directory is ready, but nothing will be snapshotted until it is"
  elif repo_initialised; then
    ok "backup repository already initialised"
  else
    restic init >/dev/null
    ok "backup repository initialised: $RESTIC_REPOSITORY"
  fi

  printf '\n'
}

cmd_verify() {
  local dir status=0 count latest
  dir="$(state_dir)"

  section "[claude-state] verify — reports only, writes nothing"

  section "state directory"
  if [ -d "$dir" ]; then
    ok "$dir exists"
  else
    bad "$dir is missing"
    printf '\n'
    return 1
  fi

  section "classification coverage"
  UNCLASSIFIED=()
  scan_unclassified "$dir" ""
  if [ "${#UNCLASSIFIED[@]}" -eq 0 ]; then
    ok "every path is classified"
  else
    status=1
    bad "${#UNCLASSIFIED[@]} unclassified path(s) — these ARE backed up, but the"
    printf '       manifest should be updated to say so deliberately:\n'
    local path
    for path in "${UNCLASSIFIED[@]}"; do
      printf '         %s\n' "$path"
    done
  fi

  section "backup repository"
  if [ -z "${RESTIC_REPOSITORY:-}" ]; then
    bad "RESTIC_REPOSITORY is not set"
    status=1
  elif ! repo_initialised; then
    bad "repository unreachable or uninitialised: $RESTIC_REPOSITORY"
    status=1
  else
    ok "repository reachable: $RESTIC_REPOSITORY"
    count="$(restic snapshots --tag claude-state --json 2>/dev/null | jq 'length')"
    if [ "$count" -eq 0 ]; then
      warn "no snapshots yet — run 'claude-state snapshot'"
    else
      latest="$(restic snapshots --tag claude-state --json 2>/dev/null | jq -r '.[-1].time')"
      ok "$count snapshot(s), most recent $latest"
    fi
  fi

  if [ "$status" -eq 0 ]; then
    printf '\n[claude-state] all good\n\n'
  else
    printf '\n[claude-state] problems found — see above\n\n'
  fi
  return "$status"
}

cmd_snapshot() {
  local dir exclude
  dir="$(state_dir)"
  require_repo
  [ -d "$dir" ] || die "state directory does not exist: $dir"
  repo_initialised || die "repository not initialised — run 'claude-state converge'"

  exclude="$(render_exclude_file "$dir")"

  section "[claude-state] snapshot"
  restic backup "$dir" \
    --exclude-file "$exclude" \
    --tag claude-state \
    --skip-if-unchanged

  section "retention"
  restic forget \
    --tag claude-state \
    --keep-last 10 \
    --keep-daily 7 \
    --keep-weekly 4 \
    --prune
  printf '\n'
}

cmd_restore() {
  local snapshot="latest" target="" live resolved
  require_repo

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target)   target="${2:-}"; shift 2 ;;
      --snapshot) snapshot="${2:-}"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  [ -n "$target" ] || die "--target is required"

  # Restoring over live state would destroy the thing being protected.
  live="$(readlink -f "$(state_dir)" 2>/dev/null || state_dir)"
  mkdir -p "$target"
  resolved="$(readlink -f "$target")"
  if [ "$resolved" = "$live" ]; then
    die "refusing to restore over the live state directory"
  fi

  section "[claude-state] restore"
  restic restore "$snapshot" --target "$target"
  ok "restored $snapshot into $target"
  printf '\n'
}

cmd_drill() {
  local dir work restored status=0 entry base rel
  dir="$(state_dir)"
  require_repo
  repo_initialised || die "repository not initialised — run 'claude-state converge'"

  section "[claude-state] drill — proves the repository can be restored from"

  section "repository integrity"
  if restic check --read-data-subset=5% >/dev/null 2>&1; then
    ok "structure and a 5% data sample verified"
  else
    bad "restic check failed"
    status=1
  fi

  section "restore"
  work="$(workdir)/drill"
  mkdir -p "$work"
  if restic restore latest --target "$work" >/dev/null 2>&1; then
    ok "latest snapshot restored to scratch"
  else
    bad "restore failed"
    printf '\n[claude-state] drill FAILED\n\n'
    return 1
  fi

  # restic reproduces the absolute path beneath the target.
  restored="${work}${dir}"

  section "content"
  if [ ! -d "$restored" ]; then
    bad "restored tree missing expected path $restored"
    printf '\n[claude-state] drill FAILED\n\n'
    return 1
  fi

  # Every live top-level path that should have been captured must be present.
  # Byte-equality against a live directory is not asserted: the agent writes
  # continuously, so equality would fail for reasons unrelated to the backup.
  # The synthetic drill in CI asserts equality against a static fixture.
  for entry in "$dir"/*; do
    base="$(basename "$entry")"
    rel="$base"
    if matches_excluded "$rel"; then
      continue
    fi
    if [ -e "$restored/$base" ]; then
      ok "present: $rel"
    else
      bad "missing from restore: $rel"
      status=1
    fi
  done

  if [ "$status" -eq 0 ]; then
    printf '\n[claude-state] drill passed\n\n'
  else
    printf '\n[claude-state] drill FAILED\n\n'
  fi
  return "$status"
}

usage() {
  cat <<'USAGE'
claude-state — reproducible, snapshottable agent state

  converge   Reconstruct from declarations only. Idempotent.
  verify     Assert and report. Writes nothing. Non-zero on divergence.
  snapshot   Back up everything not classified derived/ephemeral/secret.
  restore    Restore a snapshot.  --target DIR [--snapshot ID]
  drill      Prove the repository can be restored from.
  classify   Print the generated classification table.

Environment:
  CLAUDE_CONFIG_DIR   agent state directory (default ~/.claude)
  RESTIC_REPOSITORY   backup repository location
  RESTIC_PASSWORD[_FILE]
USAGE
}

main() {
  local verb="${1:-}"
  if [ "$#" -gt 0 ]; then
    shift
  fi
  case "$verb" in
    converge) cmd_converge "$@" ;;
    verify)   cmd_verify "$@" ;;
    snapshot) cmd_snapshot "$@" ;;
    restore)  cmd_restore "$@" ;;
    drill)    cmd_drill "$@" ;;
    classify) cat "$CLASSIFICATION_DIR/classification.md" ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown verb: $verb (try --help)" ;;
  esac
}

main "$@"
