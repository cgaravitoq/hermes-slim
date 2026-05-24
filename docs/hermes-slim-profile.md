# hermes-slim profile

This fork should stay close to `NousResearch/hermes-agent`. The slim image is
implemented through Docker packaging, not broad source-tree deletions.

## Current profile

- Base source: `upstream/main`.
- Build extras: `messaging`, `cron`, and `mcp`, resolved from `uv.lock`.
- Runtime system packages: `ca-certificates`, `git`, `openssh-client`, `procps`,
  `ripgrep`, and `tini`.
- Runtime Python installer: pinned `uv`/`uvx` binary for lazy optional deps.
- Excluded from the Docker build context: browser/dashboard UI trees, tests,
  docs, optional skills, bundled skills, benchmark environments, and local
  runtime state.

## Policy

Keep file/path slimming in `.dockerignore` whenever possible. Keep dependency
slimming in Docker install extras. Do not delete upstream source just to make
the container smaller.

If a required file imports a heavy optional dependency at import time, prefer a
lazy import, optional import, feature gate, or runtime configuration switch. Use
a source patch only when the runtime genuinely cannot work without it, and
document that patch here.

## Validation

For each upstream sync:

1. Start from current `upstream/main`.
2. Reapply this Docker profile.
3. Build the image.
4. Run `hermes --help` inside the image.
5. Run the target gateway smoke test from the downstream deployment repo.
