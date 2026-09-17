#!/usr/bin/env bash
set -euo pipefail

IMAGE="${PIBOX_IMAGE:-pi-sandbox}"
WORKSPACE="${PIBOX_WORKSPACE:-$PWD}"
WORKDIR="${PIBOX_WORKDIR:-/workspace}"
HOME_VOLUME="${PIBOX_HOME_VOLUME:-pi-agent-home}"
HOME_TARGET="${PIBOX_HOME_TARGET:-/home/sandbox/.pi/agent}"
SANDBOX_UID="${PIBOX_SANDBOX_UID:-$(id -u)}"
SANDBOX_GID="${PIBOX_SANDBOX_GID:-$(id -g)}"

MEMORY="${PIBOX_MEMORY:-2g}"
CPUS="${PIBOX_CPUS:-2}"
PIDS_LIMIT="${PIBOX_PIDS_LIMIT:-512}"
NETWORK_DEFAULT="${PIBOX_NETWORK_DEFAULT:-bridge}"
POSTGRES_HOST="${PIBOX_POSTGRES_HOST:-}"
POSTGRES_PORT="${PIBOX_POSTGRES_PORT:-5432}"

READ_ONLY="${PIBOX_READ_ONLY:-0}"
DROP_CAPS="${PIBOX_DROP_CAPS:-1}"
NO_NEW_PRIVS="${PIBOX_NO_NEW_PRIVS:-1}"
SELINUX_SUFFIX="${PIBOX_SELINUX_SUFFIX:-:Z}"
GIT_IDENTITY="${PIBOX_GIT_IDENTITY:-1}"
GIT_NAME="${PIBOX_GIT_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
GIT_EMAIL="${PIBOX_GIT_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"
GH_AUTH="${PIBOX_GH_AUTH:-1}"
GH_CONFIG_VOLUME="${PIBOX_GH_CONFIG_VOLUME:-pi-gh-config}"
GH_CONFIG_TARGET="${PIBOX_GH_CONFIG_TARGET:-/home/sandbox/.config/gh}"
INTERACTIVE=0
[[ -t 0 && -t 1 && -z "${CI:-}" ]] && INTERACTIVE=1

enabled() { [[ "${1:-0}" == "1" ]]; }

select_network() {
  local requested="${PIBOX_NETWORK:-}"

  case "$requested" in
    "") ;;
    ask) ;;
    *) printf '%s\n' "$requested"; return ;;
  esac

  if [[ "$requested" != "ask" ]] && ! enabled "${PIBOX_NETWORK_PROMPT:-1}"; then
    printf '%s\n' "$NETWORK_DEFAULT"
    return
  fi

  if ! enabled "$INTERACTIVE" || [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    printf '%s\n' "$NETWORK_DEFAULT"
    return
  fi

  local networks=()
  mapfile -t networks < <(docker network ls --filter driver=bridge --format '{{.Name}}' 2>/dev/null || true)

  if [[ ${#networks[@]} -eq 0 ]]; then
    printf '%s\n' "$NETWORK_DEFAULT"
    return
  fi

  printf 'Docker network:\n' >/dev/tty
  local i
  for i in "${!networks[@]}"; do
    printf '  %d) %s' "$((i + 1))" "${networks[$i]}" >/dev/tty
    [[ "${networks[$i]}" == "$NETWORK_DEFAULT" ]] && printf ' (default)' >/dev/tty
    printf '\n' >/dev/tty
  done

  local choice
  printf 'Select network [%s]: ' "$NETWORK_DEFAULT" >/dev/tty
  read -r choice </dev/tty || choice=""

  if [[ -z "$choice" ]]; then
    printf '%s\n' "$NETWORK_DEFAULT"
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= ${#networks[@]} )); then
    printf '%s\n' "${networks[$((10#$choice - 1))]}"
  else
    printf '%s\n' "$choice"
  fi
}

NETWORK="$(select_network)"

args=(
  --rm
  --memory "$MEMORY"
  --cpus "$CPUS"
  --pids-limit "$PIDS_LIMIT"
  --network "$NETWORK"
  -e ANTHROPIC_API_KEY
  -v "${WORKSPACE}:${WORKDIR}${SELINUX_SUFFIX}"
  -v "${HOME_VOLUME}:${HOME_TARGET}"
  -w "$WORKDIR"
)

case "${PIBOX_TTY:-auto}" in
  auto) enabled "$INTERACTIVE" && args+=(-it) ;;
  1|true|yes) args+=(-it) ;;
  0|false|no) ;;
  *) printf 'Invalid PIBOX_TTY=%s (use auto, 1, or 0)\n' "$PIBOX_TTY" >&2; exit 2 ;;
esac

if [[ "${1:-}" == "shell" ]]; then
  args+=(--entrypoint bash)
  shift
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

# Extra raw docker-run args, e.g.:
#   PIBOX_EXTRA_ARGS='--env OPENAI_API_KEY'
if [[ -n "${PIBOX_EXTRA_ARGS:-}" ]]; then
  # Intentionally split like a shell for simple flag lists.
  # shellcheck disable=SC2206
  extra_args=($PIBOX_EXTRA_ARGS)
  args+=("${extra_args[@]}")
fi

# Docker named volumes are created as root-owned. Pi writes lock directories
# beside settings/auth files at startup, so make the mounted config directory
# writable by the non-root sandbox user before launching Pi.
if enabled "${PIBOX_INIT_HOME_VOLUME:-1}"; then
  docker volume create "$HOME_VOLUME" >/dev/null
  init_volumes=(-v "${HOME_VOLUME}:${HOME_TARGET}")
  init_cmd="mkdir -p '$HOME_TARGET' && chown -R '$SANDBOX_UID:$SANDBOX_GID' '$HOME_TARGET'"

  if enabled "$GH_AUTH"; then
    docker volume create "$GH_CONFIG_VOLUME" >/dev/null
    init_volumes+=(-v "${GH_CONFIG_VOLUME}:${GH_CONFIG_TARGET}")
    init_cmd="$init_cmd && mkdir -p '$GH_CONFIG_TARGET' && chown -R '$SANDBOX_UID:$SANDBOX_GID' '$GH_CONFIG_TARGET'"
  fi

  docker run --rm \
    --entrypoint sh \
    -u 0 \
    "${init_volumes[@]}" \
    "$IMAGE" \
    -c "$init_cmd"
fi

docker run "${args[@]}" "$IMAGE" "$@"
