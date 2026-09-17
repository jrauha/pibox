FROM node:24-trixie-slim

ARG SANDBOX_UID=1000
ARG SANDBOX_GID=1000
ARG SANDBOX_USER=sandbox

# Polyglot sandbox.
# Node is required for pi itself; Python, Go, and Rust are included for projects.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cargo \
    fd-find \
    gh \
    git \
    golang-go \
    libpq-dev \
    pkg-config \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rustc \
    rustfmt \
  && ln -s /usr/bin/fdfind /usr/local/bin/fd \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

RUN mkdir -p "/home/${SANDBOX_USER}/.pi/agent" \
  && chown -R "${SANDBOX_UID}:${SANDBOX_GID}" "/home/${SANDBOX_USER}"

USER ${SANDBOX_UID}:${SANDBOX_GID}
ENV HOME=/home/${SANDBOX_USER}

WORKDIR /workspace
ENTRYPOINT ["pi"]
