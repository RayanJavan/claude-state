# The load-bearing artifact.
#
# Every path in an agent's state directory belongs to exactly one class, and the
# class decides its fate. This file is the single source of truth: the restic
# exclude rules, the documentation table and the coverage fixture are all
# generated from it. Nothing downstream is hand-maintained in parallel.
#
# The rule that makes this safe: a path matching NO glob here is treated as
# `earned` — backed up, and reported as unclassified. Backup classification
# fails toward capture, never toward silence. A hand-curated allowlist would do
# the opposite, and would quietly drop whatever the next upstream release adds.
#
# `backup = false` is the only thing that removes data from a snapshot, so the
# three classes below that set it are the entire risk surface of this file.

{
  earned = {
    backup = true;
    summary = "Irreplaceable. Cannot be regenerated from anything.";
    paths = {
      "projects" = "conversation transcripts — the reason any of this exists";
      ".claude.json" = "trust, onboarding, last-session pointer, account identity";
      "history.jsonl" = "prompt history";
      "file-history" = "edit undo history";
      "tasks" = "task state across sessions";
      "todos" = "per-session todo lists";
      "backups" = "the agent's own rotating .claude.json backups";
      "statsig" = "feature-flag state; small, and cheap to keep";

      # These two are what make the `derived` class reconstructible: they pin
      # every plugin to a repo and a commit SHA. Losing them turns 49 MB of
      # regenerable cache into 49 MB of unrecoverable state, so they are earned
      # even though the tool writes them itself.
      "plugins/installed_plugins.json" = "plugin versions and pinned commit SHAs";
      "plugins/known_marketplaces.json" = "marketplace sources";
      "plugins/data" = "plugin-local persisted data";
    };
  };

  declared = {
    backup = true;
    summary = "Should live in version control; the copy here is a projection.";
    paths = {
      "settings.json" = "user-level settings";
      "settings.local.json" = "local setting overrides";
      "CLAUDE.md" = "user-level agent instructions";
    };
  };

  derived = {
    backup = false;
    summary = "Reconstructible from declarations. Losing this costs time, not data.";
    paths = {
      "plugins/cache" = "plugin checkouts at SHAs pinned in installed_plugins.json";
      "plugins/marketplaces" = "marketplace clones named in known_marketplaces.json";
      "plugins/*-cache.json" = "plugin catalogue cache";
      "cache" = "changelog and issue caches";
      "skills" = "symlinks into plugin-provided skill directories";
    };
  };

  ephemeral = {
    backup = false;
    summary = "Process-scoped. Restoring it is actively harmful — a stale lock is worse than a missing one.";
    paths = {
      "daemon" = "daemon control key and dispatch roster";
      "daemon.lock" = "daemon lock file";
      "daemon.log" = "daemon log";
      "daemon.status.json" = "daemon liveness";
      "ide" = "per-PID IDE lock files";
      "sessions" = "per-PID session descriptors";
      "session-env" = "per-session environment scratch";
      "shell-snapshots" = "captured shell init state";
      "jobs" = "background job working directories";
      ".last-cleanup" = "housekeeping timestamp";
      ".last-update-result.json" = "self-update result";
      "plugins/.last_inuse_sweep" = "plugin housekeeping timestamp";
    };
  };

  secret = {
    backup = false;
    summary = "Excluded by policy. Credentials are injected at runtime and must never enter a backup.";
    paths = {
      ".credentials.json" = "OAuth credentials — superseded by the token in the secret store";
    };
  };
}
