# hermes-slim profile

This fork ships a lightweight container for low-cost / single-channel
deployments (e.g. a Telegram bot served over HTTP). The goal is the smallest
image that still runs a messaging gateway, without dragging the upstream
browser/dashboard/Node toolchain that such a deployment never invokes.

## How it's structured (hybrid, conflict-free)

The fork no longer rewrites the upstream `Dockerfile`. That was the source of a
merge conflict on every upstream sync (the s6-overlay migration repeatedly
clobbered the tini+gosu entrypoint — see commit `d82dcae77`). Instead:

- **`Dockerfile`**, **`docker/entrypoint.sh`**, **`docker/stage2-hook.sh`**,
  **`docker-compose.yml`** — kept **verbatim from upstream**. `git merge
  upstream/main` never conflicts on them.
- **`Dockerfile.slim`** (fork-only) — the actual slim build: a
  `python:3.13-slim` multi-stage image with tini+gosu, ~470MB.
- **`Dockerfile.slim.dockerignore`** (fork-only) — tight build context for the
  slim build; BuildKit prefers it over `.dockerignore` when building with
  `-f Dockerfile.slim`, so the upstream `.dockerignore` stays untouched.
- **`docker/entrypoint.slim.sh`** (fork-only) — the tini+gosu bootstrap
  (UID/GID remap, volume chown, config seeding) the slim image uses.
- **`docker-compose.slim.yml`** (fork-only) — local-testing compose for the
  slim image.
- **`.github/workflows/build-push.yml`** — builds `Dockerfile.slim` and pushes
  to GHCR.

## Slim build contents

- Base: `python:3.13-slim` (builder + runtime stages).
- Init: tini (PID 1) + gosu (privilege drop). No s6-overlay.
- Python extras: `messaging`, `cron`, `mcp`, `anthropic`. OpenAI / OpenRouter /
  OpenAI-compatible aggregators are served by the core `openai` dependency.
  Everything else lazy-installs at first use via `tools/lazy_deps.py`.
- Runtime system packages: `ca-certificates`, `git`, `openssh-client`,
  `procps`, `ripgrep`, `tini`.
- Excluded from the build context: browser/dashboard/TUI trees, tests, docs,
  optional/bundled skills, benchmark envs, local runtime state.

## Upstreamable feature switches (the PR)

The same slimming, expressed as opt-OUT build ARGs on the **upstream**
Dockerfile (defaults reproduce the current full image byte-for-byte), is
proposed upstream so any user can build a light image without forking:

- `HERMES_WITH_BROWSER=1` — gates the Playwright/Chromium install (~300-400MB).
- `HERMES_WITH_DASHBOARD=1` — gates the web dashboard SPA build + `web` extra.
- `HERMES_WITH_TUI=1` — gates the terminal-UI build.
- `HERMES_WITH_FFMPEG=1`, `HERMES_WITH_DOCKER_CLI=1` — gate those apt packages.
- `HERMES_EXTRAS="all messaging anthropic bedrock azure-identity"` — the
  `uv sync` extra set (default = current invocation).
- `HERMES_PROFILE=full|messaging-only|minimal` — convenience preset.

That upstream image keeps s6-overlay + debian (architectural anchors upstream
won't make optional), so its `messaging-only` profile lands ~500-700MB —
larger than this fork's `Dockerfile.slim` but mainline and zero-maintenance.
This fork keeps `Dockerfile.slim` for the absolute-minimum python-slim image.

## Validation

For each upstream sync:

1. `git merge upstream/main` (expected: clean — no Dockerfile conflict).
2. Build: `docker build -f Dockerfile.slim -t hermes-slim .`
3. `docker run --rm hermes-slim --help`
4. Run the target gateway smoke test from the downstream deployment repo.
