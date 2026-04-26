# syntax=docker/dockerfile:1.7

# ---------- Stage 1: builder ----------
# Build the Python venv with all wheels compiled. Build tools live only here
# and never ship in the final image.
FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM python:3.13-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential gcc python3-dev libffi-dev git && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# Source must be present for the editable install to resolve the project's
# own package list from pyproject.toml.
COPY . .

# Slim ecommerce build: only the extras the agent actually exercises in
# production (telegram/slack/discord/aiohttp messaging, croniter scheduling,
# MCP server integrations). [all] would also pull voice, matrix, modal,
# daytona, bedrock, mistral, dashboard — none of which this image runs.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /opt/hermes/.venv && \
    VIRTUAL_ENV=/opt/hermes/.venv uv pip install -e ".[messaging,cron,mcp]"


# ---------- Stage 2: runtime ----------
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PATH="/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}" \
    HERMES_HOME=/opt/data \
    VIRTUAL_ENV=/opt/hermes/.venv

# Runtime-only system deps. tini reaps orphaned MCP/git/etc. subprocesses
# when hermes runs as PID 1 (#15012). git + openssh-client are needed for
# repo operations the agent performs. ripgrep is the search backend.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ripgrep git openssh-client tini procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/

WORKDIR /opt/hermes

# Venv from builder — already wired to /opt/hermes/.venv so entrypoint's
# `source .venv/bin/activate` keeps working unchanged.
COPY --from=builder /opt/hermes/.venv /opt/hermes/.venv

# Project source. .dockerignore drops web/, tests/, docs/, .git/, etc.
COPY --chown=hermes:hermes . .

RUN chmod -R a+rX /opt/hermes

VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
