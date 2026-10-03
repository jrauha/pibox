#!/usr/bin/env bash
set -euo pipefail

IMAGE="${PIBOX_IMAGE:-jirauha/pibox}"
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

# Syntax: pibox [name] [shell [shell args] | -- [pi args]]
WORKTREE_MODE=0
WORKTREE_NAME=""
SHELL_MODE=0
case "${1:-}" in
  ""|shell|--) ;;
  -*) printf 'Pi arguments must follow -- (e.g. pibox -- %s)\n' "$1" >&2; exit 2 ;;
  *) WORKTREE_MODE=1; WORKTREE_NAME="$1"; shift ;;
esac

if [[ "${1:-}" == -- ]]; then
  shift
elif [[ "${1:-}" == shell ]]; then
  SHELL_MODE=1
  shift
elif (($#)); then
  printf 'Pi arguments must follow -- (e.g. pibox %s -- <pi args>)\n' "$WORKTREE_NAME" >&2
  exit 2
fi

setup_worktree() {
  local source_dir="$WORKSPACE" exclude path_git_root path_common
  if ! WORKTREE_REPO="$(cd -- "$source_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"; then
    printf 'Worktree mode requires PIBOX_WORKSPACE to be inside a Git repository\n' >&2
    exit 2
  fi
  WORKTREE_REPO="$(cd -- "$WORKTREE_REPO" && pwd -P)"
  if ! git -C "$WORKTREE_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'Worktree mode requires a repository with at least one commit\n' >&2
    exit 2
  fi
  GIT_COMMON_DIR="$(cd -- "$WORKTREE_REPO" && cd -- "$(git rev-parse --git-common-dir)" && pwd -P)"
  if [[ "$WORKTREE_REPO" == *:* || "$GIT_COMMON_DIR" == *:* ||
        "$WORKTREE_REPO" == *$'\n'* || "$GIT_COMMON_DIR" == *$'\n'* ]]; then
    printf 'Worktree mode does not support colons or newlines in repository paths\n' >&2
    exit 2
  fi

  if [[ ! "$WORKTREE_NAME" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] ||
     ! git check-ref-format --branch "pibox/$WORKTREE_NAME" >/dev/null 2>&1; then
    printf 'Invalid worktree name: %s\n' "$WORKTREE_NAME" >&2
    exit 2
  fi
  WORKTREE_BRANCH="pibox/$WORKTREE_NAME"
  WORKTREE_DIR="$WORKTREE_REPO/.pibox/worktrees"
  WORKTREE_PATH="$WORKTREE_DIR/$WORKTREE_NAME"
  if [[ -L "$WORKTREE_REPO/.pibox" || -L "$WORKTREE_DIR" || -L "$WORKTREE_PATH" ]]; then
    printf 'Refusing to use a symlinked worktree path: %s\n' "$WORKTREE_PATH" >&2
    exit 2
  fi

  if [[ -e "$WORKTREE_PATH" ]]; then
    path_git_root="$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel 2>/dev/null || true)"
    path_common="$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ "$(cd -- "$path_git_root" 2>/dev/null && pwd -P)" != "$WORKTREE_PATH" ]] ||
       [[ "$(cd -- "$WORKTREE_PATH" && cd -- "$path_common" 2>/dev/null && pwd -P)" != "$GIT_COMMON_DIR" ]] ||
       ! git -C "$WORKTREE_REPO" worktree list --porcelain | grep -Fx "worktree $WORKTREE_PATH" >/dev/null; then
      printf 'Path exists but is not a registered worktree of this repository: %s\n' "$WORKTREE_PATH" >&2
      exit 2
    fi
    printf 'Reopening worktree %s\n' "$WORKTREE_PATH" >&2
  else
    if git -C "$WORKTREE_REPO" show-ref --verify --quiet "refs/heads/$WORKTREE_BRANCH"; then
      printf 'Branch already exists without its worktree: %s\n' "$WORKTREE_BRANCH" >&2
      exit 2
    fi
    mkdir -p -- "$WORKTREE_DIR"
    exclude="$GIT_COMMON_DIR/info/exclude"
    if [[ ! -f "$exclude" ]] || ! grep -Fxq '/.pibox/worktrees/' "$exclude"; then
      printf '\n/.pibox/worktrees/\n' >>"$exclude"
    fi
    git -C "$WORKTREE_REPO" worktree add -b "$WORKTREE_BRANCH" "$WORKTREE_PATH" HEAD
    printf 'Created worktree %s (branch %s)\n' "$WORKTREE_PATH" "$WORKTREE_BRANCH" >&2
  fi

  # Git's .git file and worktree metadata contain host-absolute paths.
  # Keep those paths intact rather than relocating the worktree to /workspace.
  WORKSPACE="$WORKTREE_PATH"
  WORKDIR="$WORKTREE_PATH"
  # Git metadata is shared by concurrent worktree containers on SELinux hosts.
  if [[ -z "${PIBOX_SELINUX_SUFFIX:-}" ]]; then SELINUX_SUFFIX=:z; fi
}

enabled() { [[ "${1:-0}" == "1" ]]; }

if enabled "$WORKTREE_MODE"; then
  setup_worktree
fi

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

if enabled "$WORKTREE_MODE"; then
  args+=(-v "${GIT_COMMON_DIR}:${GIT_COMMON_DIR}${SELINUX_SUFFIX}")
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
