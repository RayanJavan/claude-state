<!-- GENERATED from classification.nix. Do not edit by hand — edit the manifest. -->

# Path classification

Every path in the agent state directory belongs to exactly one class below.
A path matching no entry is treated as `earned`: it is backed up, and
reported as unclassified. Classification fails toward capture, so an
upstream release that adds a new path produces noise, never silent loss.

Backed up: `declared`, `earned`. Excluded: `derived`, `ephemeral`, `secret`.

## `declared`

Should live in version control; the copy here is a projection.

**Included in backups: yes**

| Path | Why |
|---|---|
| `CLAUDE.md` | user-level agent instructions |
| `settings.json` | user-level settings |
| `settings.local.json` | local setting overrides |

## `derived`

Reconstructible from declarations. Losing this costs time, not data.

**Included in backups: no**

| Path | Why |
|---|---|
| `cache` | changelog and issue caches |
| `plugins/*-cache.json` | plugin catalogue cache |
| `plugins/cache` | plugin checkouts at SHAs pinned in installed_plugins.json |
| `plugins/marketplaces` | marketplace clones named in known_marketplaces.json |
| `skills` | symlinks into plugin-provided skill directories |

## `earned`

Irreplaceable. Cannot be regenerated from anything.

**Included in backups: yes**

| Path | Why |
|---|---|
| `.claude.json` | trust, onboarding, last-session pointer, account identity |
| `backups` | the agent's own rotating .claude.json backups |
| `file-history` | edit undo history |
| `history.jsonl` | prompt history |
| `plugins/data` | plugin-local persisted data |
| `plugins/installed_plugins.json` | plugin versions and pinned commit SHAs |
| `plugins/known_marketplaces.json` | marketplace sources |
| `projects` | conversation transcripts — the reason any of this exists |
| `statsig` | feature-flag state; small, and cheap to keep |
| `tasks` | task state across sessions |
| `todos` | per-session todo lists |

## `ephemeral`

Process-scoped. Restoring it is actively harmful — a stale lock is worse than a missing one.

**Included in backups: no**

| Path | Why |
|---|---|
| `.last-cleanup` | housekeeping timestamp |
| `.last-update-result.json` | self-update result |
| `daemon` | daemon control key and dispatch roster |
| `daemon.lock` | daemon lock file |
| `daemon.log` | daemon log |
| `daemon.status.json` | daemon liveness |
| `ide` | per-PID IDE lock files |
| `jobs` | background job working directories |
| `plugins/.last_inuse_sweep` | plugin housekeeping timestamp |
| `session-env` | per-session environment scratch |
| `sessions` | per-PID session descriptors |
| `shell-snapshots` | captured shell init state |

## `secret`

Excluded by policy. Credentials are injected at runtime and must never enter a backup.

**Included in backups: no**

| Path | Why |
|---|---|
| `.credentials.json` | OAuth credentials — superseded by the token in the secret store |
