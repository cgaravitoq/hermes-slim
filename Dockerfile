# syntax=docker/dockerfile:1.7

FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source

# Build the Python environment with native build tooling isolated from the
# runtime image.
FROM python:3.13-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential gcc git libffi-dev python3-dev && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes
COPY . .

# Slim runtime profile: install only the extras needed by the deployed
# messaging/ecommerce gateway. Heavy optional backends stay lazy/opt-in.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /opt/hermes/.venv && \
    VIRTUAL_ENV=/opt/hermes/.venv uv pip install -e ".[messaging,cron,mcp]"


FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    HERMES_HOME=/opt/data \
    VIRTUAL_ENV=/opt/hermes/.venv \
    PATH="/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"

# Runtime-only tools used by Hermes sessions and the gateway. Browser/UI build
# dependencies intentionally stay out of this slim image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git openssh-client procps ripgrep tini && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/

WORKDIR /opt/hermes
COPY --from=builder /opt/hermes/.venv /opt/hermes/.venv
COPY --chown=hermes:hermes . .

RUN chmod -R a+rX /opt/hermes && \
    chown -R hermes:hermes /opt/hermes/.venv

VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
