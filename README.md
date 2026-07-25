# claude-state

Reproducible, snapshottable state management for an AI coding agent running in
a disposable dev environment.

## The idea

Most of what accumulates in an agent's config directory is not state — it's
cache. Plugin checkouts, marketplace clones, catalogue caches: all of it is
fully described by a few small manifest files and a commit SHA. Treating it as
state means persisting and backing up tens of megabytes that a rebuild can
regenerate in seconds.

This repo draws the line explicitly, in [`classification.nix`](./classification.nix),
and builds everything else — the CLI, the CI checks, the docs — as a
consequence of that one file:

| Class | Meaning | Backed up? |
|---|---|---|
| `earned` | Irreplaceable — transcripts, trust state, session history | yes |
| `declared` | Belongs in version control; this is a projection of it | yes |
| `derived` | Reconstructible from declarations | no |
| `ephemeral` | Process-scoped; restoring it is actively harmful | no |
| `secret` | Excluded by policy — injected at runtime, never on disk | no |

**A path matching no rule is treated as `earned`.** It gets backed up and
reported as unclassified, never silently dropped. See
[`docs/classification.md`](./docs/classification.md) for the full table — it is
generated from the manifest and a CI check fails if it ever drifts.

## The CLI

```
claude-state converge   # reconstruct from declarations only; idempotent
claude-state verify     # assert and report; writes nothing, ever
claude-state snapshot   # back up everything not derived/ephemeral/secret
claude-state restore --target DIR [--snapshot ID]
claude-state drill      # prove the repository can actually be restored from
```

Backed by [restic](https://restic.net) — content-defined chunking means a
snapshot with no exclusions at all is still cheap, which is what makes
default-include-and-report affordable instead of a curated allowlist.

## Using it

As a flake input:

```nix
inputs.claude-state.url = "github:RayanJavan/claude-state";
```

Or, in a dev container that isn't Nix-based, the published Feature:

```jsonc
{
  "features": { "ghcr.io/rayanjavan/claude-state/claude-state:1": {} },
  "mounts": [{ "source": "nix-store", "target": "/nix", "type": "volume" }]
}
```

The `/nix` volume mount matters: without it, every rebuild re-downloads the
entire Nix closure. It's an optimization, not a dependency — the Nix store is
itself `derived`, so losing the volume costs time, never data.

**No systemd assumed.** The dev environment this was built for (GitHub
Codespaces) has none, so the Feature installs Nix with `--init none` and
starts the daemon itself via a small idempotent helper, called before every
`converge` / `verify`.

## Stated limitation

The restic repository defaults to a path under `/workspaces` — local to the
environment. That survives a container **rebuild**. It does **not** survive
environment **deletion** (Codespaces' default: 30 days inactive). Point
`RESTIC_REPOSITORY` at S3-compatible object storage to raise that tier; nothing
else in this design changes if you do.

## Verifying the design holds

```
nix flake check     # classification coverage, verify-writes-nothing,
                     # a byte-for-byte synthetic backup/restore round trip,
                     # secret-exclusion, and docs-vs-manifest drift —
                     # all built in the Nix sandbox, no network required
```

`nix flake check` proves the *tooling*. Proving the *actual* repository in a
live environment is what `claude-state drill` is for — run it on a schedule,
not just once.
