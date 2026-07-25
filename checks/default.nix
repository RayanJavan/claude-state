# Checks that must build for `nix flake check` to pass.
#
# A Nix check is a derivation: if it builds, it passed. These run in the build
# sandbox with no network, which is why every backup target is a local
# repository and every fixture is synthetic.
#
# The division of labour matters. These checks prove the *tooling* — that
# classification covers, that verify is read-only, that a backup round-trips
# byte-for-byte. Proving the *actual repository* in a live environment is what
# `claude-state drill` is for. Neither substitutes for the other.

{ pkgs, classify, cli }:

let
  # A synthetic state directory mirroring a real layout, with at least one
  # concrete path per glob in the manifest.
  #
  # It is deliberately static: byte-equality assertions are only meaningful
  # against something that is not being written to concurrently.
  fixture = pkgs.runCommand "agent-state-fixture" { } ''
    mkdir -p "$out"
    cd "$out"

    # earned
    mkdir -p projects file-history tasks todos backups statsig
    echo '{"hasCompletedOnboarding":true}' > .claude.json
    echo '{"display":"hello"}'             > history.jsonl
    echo 'transcript'                      > projects/session-one.jsonl
    echo 'edit'                            > file-history/edit-one.json
    echo 'task'                            > tasks/task-one.json
    echo 'todo'                            > todos/todo-one.json
    echo 'backup'                          > backups/.claude.json.backup.1
    echo 'flags'                           > statsig/flags.json

    # declared
    echo '{"model":"opus"}' > settings.json
    echo '{}'               > settings.local.json
    echo '# instructions'   > CLAUDE.md

    # earned, inside an otherwise derived directory
    mkdir -p plugins/data
    echo '{"plugins":{}}'     > plugins/installed_plugins.json
    echo '{"marketplaces":{}}'> plugins/known_marketplaces.json
    echo 'plugin state'       > plugins/data/state.json

    # derived
    mkdir -p plugins/cache/example plugins/marketplaces/example cache skills
    echo 'checkout'  > plugins/cache/example/file
    echo 'clone'     > plugins/marketplaces/example/file
    echo '{}'        > plugins/plugin-catalog-cache.json
    echo 'changelog' > cache/changelog.md
    ln -s ../nowhere  skills/dangling
    echo 'sweep'     > plugins/.last_inuse_sweep

    # ephemeral
    mkdir -p daemon ide sessions session-env shell-snapshots jobs
    echo 'key'   > daemon/control.key
    echo 'lock'  > daemon.lock
    echo 'log'   > daemon.log
    echo '{}'    > daemon.status.json
    echo 'lock'  > ide/1234.lock
    echo '{}'    > sessions/1234.json
    echo 'env'   > session-env/keep
    echo 'snap'  > shell-snapshots/snapshot.sh
    echo 'job'   > jobs/job-one
    echo 'ts'    > .last-cleanup
    echo '{}'    > .last-update-result.json

    # secret
    echo '{"token":"must-never-be-backed-up"}' > .credentials.json
  '';

  # Shared preamble: a writable copy of the fixture, a scratch HOME, and a
  # local restic repository.
  harness = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    export CLAUDE_CONFIG_DIR="$TMPDIR/state"
    cp -r ${fixture} "$CLAUDE_CONFIG_DIR"
    chmod -R u+w "$CLAUDE_CONFIG_DIR"

    export RESTIC_REPOSITORY="$TMPDIR/repo"
    export RESTIC_PASSWORD="check-harness-password"
  '';

  check = name: script: extraInputs: pkgs.runCommand "check-${name}"
    {
      nativeBuildInputs = [ cli pkgs.restic pkgs.jq ] ++ extraInputs;
    }
    (harness + script + "\ntouch \"$out\"\n");

in
{
  # Every path in a realistic layout is classified, and an unknown path is
  # reported rather than silently swallowed. This is the check that protects
  # against an upstream release adding state nobody classified.
  classification-coverage = check "classification-coverage" ''
    claude-state converge

    if ! claude-state verify; then
      echo "FAIL: verify reported problems on a fully classified fixture" >&2
      claude-state verify || true
      exit 1
    fi

    # Now introduce something the manifest has never seen.
    echo 'surprise' > "$CLAUDE_CONFIG_DIR/brand-new-upstream-thing"

    if claude-state verify > "$TMPDIR/out" 2>&1; then
      echo "FAIL: verify exited 0 despite an unclassified path" >&2
      cat "$TMPDIR/out" >&2
      exit 1
    fi

    if ! grep -q 'brand-new-upstream-thing' "$TMPDIR/out"; then
      echo "FAIL: verify did not name the unclassified path" >&2
      cat "$TMPDIR/out" >&2
      exit 1
    fi
  '' [ ];

  # verify must never write. The fixture is hashed before and after; any
  # difference at all fails.
  verify-writes-nothing = check "verify-writes-nothing" ''
    claude-state converge

    before="$(find "$CLAUDE_CONFIG_DIR" -type f -exec sha256sum {} + | sort | sha256sum)"
    claude-state verify || true
    after="$(find "$CLAUDE_CONFIG_DIR" -type f -exec sha256sum {} + | sort | sha256sum)"

    if [ "$before" != "$after" ]; then
      echo "FAIL: verify modified the state directory" >&2
      exit 1
    fi
  '' [ ];

  # A full round trip against a static fixture, where byte-equality IS a
  # meaningful assertion. Also proves the excluded classes really are excluded.
  drill-synthetic = check "drill-synthetic" ''
    claude-state converge
    claude-state snapshot

    claude-state restore --target "$TMPDIR/restored"
    restored="$TMPDIR/restored$CLAUDE_CONFIG_DIR"

    # Everything backed up must come back byte-for-byte.
    for path in projects .claude.json history.jsonl file-history tasks todos \
                backups statsig settings.json settings.local.json CLAUDE.md \
                plugins/installed_plugins.json plugins/known_marketplaces.json \
                plugins/data; do
      if ! diff -r "$CLAUDE_CONFIG_DIR/$path" "$restored/$path" >/dev/null 2>&1; then
        echo "FAIL: $path did not round-trip identically" >&2
        exit 1
      fi
    done

    # Everything excluded must be absent. A secret leaking into a backup is the
    # failure this check exists to catch.
    for path in .credentials.json plugins/cache plugins/marketplaces cache \
                daemon daemon.lock ide sessions shell-snapshots jobs; do
      if [ -e "$restored/$path" ]; then
        echo "FAIL: $path was excluded from backup but appears in the restore" >&2
        exit 1
      fi
    done

    # The drill verb itself must pass against a real repository.
    claude-state drill
  '' [ pkgs.diffutils ];

  # restore must refuse to overwrite the directory it is protecting.
  restore-refuses-live-target = check "restore-refuses-live-target" ''
    claude-state converge
    claude-state snapshot

    if claude-state restore --target "$CLAUDE_CONFIG_DIR" > "$TMPDIR/out" 2>&1; then
      echo "FAIL: restore overwrote the live state directory" >&2
      exit 1
    fi

    if ! grep -q 'refusing' "$TMPDIR/out"; then
      echo "FAIL: restore failed, but not for the expected reason" >&2
      cat "$TMPDIR/out" >&2
      exit 1
    fi
  '' [ ];

  # The committed docs are a build output. If they drift from the manifest,
  # this fails rather than letting the table quietly become fiction.
  docs-current = pkgs.runCommand "check-docs-current" { } ''
    if ! diff -u ${../docs/classification.md} ${classify.docsFile}; then
      echo "" >&2
      echo "FAIL: docs/classification.md is stale." >&2
      echo "Regenerate with: nix build .#classification && cp result/classification.md docs/" >&2
      exit 1
    fi
    touch "$out"
  '';
}
