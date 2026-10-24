#!/usr/bin/env bash
set -euo pipefail

ENGINE="${PIBOX_ENGINE:-podman}"
case "$ENGINE" in
  docker|podman) ;;
  *) printf 'Invalid PIBOX_ENGINE=%s (use docker or podman)\n' "$ENGINE" >&2; exit 2 ;;
esac
command -v "$ENGINE" >/dev/null 2>&1 || {
  printf 'Container engine not found: %s\n' "$ENGINE" >&2; exit 127
}

IMAGE="${PIBOX_IMAGE:-docker.io/jirauha/pibox}"
WORKSPACE="${PIBOX_WORKSPACE:-$PWD}"
WORKDIR="${PIBOX_WORKDIR:-/workspace}"
HOME_TARGET="${PIBOX_HOME_TARGET:-/home/sandbox/.pi/agent}"
# Image user IDs, not host IDs. Override these for custom images.
SANDBOX_UID="${PIBOX_SANDBOX_UID:-1000}"
SANDBOX_GID="${PIBOX_SANDBOX_GID:-1000}"
[[ "$SANDBOX_UID" =~ ^[0-9]+$ && "$SANDBOX_GID" =~ ^[0-9]+$ ]] || {
  printf 'Sandbox UID and GID must be numeric\n' >&2; exit 2
}

# Opt-in: some rootless hosts do not delegate memory/CPU controllers.
MEMORY="${PIBOX_MEMORY:-}"
CPUS="${PIBOX_CPUS:-}"
PIDS_LIMIT="${PIBOX_PIDS_LIMIT:-512}"
NETWORK="${PIBOX_NETWORK:-bridge}"
POSTGRES_HOST="${PIBOX_POSTGRES_HOST:-}"
POSTGRES_PORT="${PIBOX_POSTGRES_PORT:-5432}"

READ_ONLY="${PIBOX_READ_ONLY:-0}"
DROP_CAPS="${PIBOX_DROP_CAPS:-1}"
NO_NEW_PRIVS="${PIBOX_NO_NEW_PRIVS:-1}"
SELINUX_SUFFIX="${PIBOX_SELINUX_SUFFIX:-:z}"
GIT_IDENTITY="${PIBOX_GIT_IDENTITY:-1}"
GIT_NAME="${PIBOX_GIT_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
GIT_EMAIL="${PIBOX_GIT_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"
GH_AUTH="${PIBOX_GH_AUTH:-0}"
GH_CONFIG_TARGET="${PIBOX_GH_CONFIG_TARGET:-/home/sandbox/.config/gh}"
# Canonical paths give each workspace its own persistent config namespace.
WORKSPACE="$(cd -- "$WORKSPACE" && pwd -P)"
project_key="$(printf '%s' "$WORKSPACE" | sha256sum)"
project_key="${project_key%% *}"
HOME_VOLUME="${PIBOX_HOME_VOLUME:-pibox-${project_key}-agent}"
GH_CONFIG_VOLUME="${PIBOX_GH_CONFIG_VOLUME:-pibox-${project_key}-gh}"

INTERACTIVE=0
[[ -t 0 && -t 1 && -z "${CI:-}" ]] && INTERACTIVE=1

# Syntax: pibox [shell | pi args]
SHELL_MODE=0
case "${1:-}" in
  shell)
    SHELL_MODE=1
    shift
    ;;
  --)
    shift
    ;;
  *) ;;
esac

enabled() { [[ "${1:-0}" == "1" ]]; }

args=(
  --rm
  --pids-limit "$PIDS_LIMIT"
  --network "$NETWORK"
  --user "${SANDBOX_UID}:${SANDBOX_GID}"
  -e ANTHROPIC_API_KEY
  -v "${WORKSPACE}:${WORKDIR}${SELINUX_SUFFIX}"
  -w "$WORKDIR"
)

# Named volumes persist per project.
args+=(-v "${HOME_VOLUME}:${HOME_TARGET}")

[[ -n "$MEMORY" ]] && args+=(--memory "$MEMORY")
[[ -n "$CPUS" ]] && args+=(--cpus "$CPUS")

# Keep host workspace ownership intact while mapping to the image user.
if [[ "$ENGINE" == podman ]]; then
  args+=(--userns "keep-id:uid=${SANDBOX_UID},gid=${SANDBOX_GID}")
fi

case "${PIBOX_TTY:-auto}" in
  auto) enabled "$INTERACTIVE" && args+=(-it) ;;
  1|true|yes) args+=(-it) ;;
  0|false|no) ;;
  *) printf 'Invalid PIBOX_TTY=%s (use auto, 1, or 0)\n' "$PIBOX_TTY" >&2; exit 2 ;;
esac

if enabled "$SHELL_MODE"; then
  args+=(--entrypoint bash)
fi

if [[ -n "$POSTGRES_HOST" ]]; then
  args+=(-e "PGHOST=${POSTGRES_HOST}" -e "PGPORT=${POSTGRES_PORT}")
fi

if enabled "$GIT_IDENTITY" && [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  args+=(
    -e GIT_CONFIG_COUNT=2
    -e GIT_CONFIG_KEY_0=user.name
    -e "GIT_CONFIG_VALUE_0=${GIT_NAME}"
    -e GIT_CONFIG_KEY_1=user.email
    -e "GIT_CONFIG_VALUE_1=${GIT_EMAIL}"
  )
fi

if enabled "$GH_AUTH"; then
  args+=(-v "${GH_CONFIG_VOLUME}:${GH_CONFIG_TARGET}")
fi

enabled "$DROP_CAPS" && args+=(--cap-drop=ALL)
enabled "$NO_NEW_PRIVS" && args+=(--security-opt no-new-privileges)
enabled "$READ_ONLY" && args+=(--read-only --tmpfs /tmp --tmpfs /home/sandbox/.cache)

# Extra raw container-run args, e.g.:
#   PIBOX_EXTRA_ARGS='--env OPENAI_API_KEY'
if [[ -n "${PIBOX_EXTRA_ARGS:-}" ]]; then
  # Intentionally split like a shell for simple flag lists.
  # shellcheck disable=SC2206
  extra_args=($PIBOX_EXTRA_ARGS)
  args+=("${extra_args[@]}")
fi

exec "$ENGINE" run "${args[@]}" "$IMAGE" "$@"
