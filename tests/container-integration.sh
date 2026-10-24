#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PIBOX_ENGINE="${1:?engine required}"
export PIBOX_IMAGE="${PIBOX_IMAGE:-localhost/pibox-test}"
TMP="$(mktemp -d)"
export PIBOX_WORKSPACE="$TMP"
export PIBOX_HOME_VOLUME="pibox-test-home-$$"
export PIBOX_GH_CONFIG_VOLUME="pibox-test-gh-$$"
export PIBOX_TTY=0 PIBOX_GIT_IDENTITY=0 PIBOX_GH_AUTH=1
export PIBOX_SANDBOX_UID="${PIBOX_SANDBOX_UID:-1000}"
export PIBOX_SANDBOX_GID="${PIBOX_SANDBOX_GID:-1000}"
cleanup() {
  "$PIBOX_ENGINE" volume rm -f "$PIBOX_HOME_VOLUME" "$PIBOX_GH_CONFIG_VOLUME" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT
"$PIBOX_ENGINE" build --build-arg "SANDBOX_UID=$PIBOX_SANDBOX_UID" \
  --build-arg "SANDBOX_GID=$PIBOX_SANDBOX_GID" -t "$PIBOX_IMAGE" "$ROOT"
owner="$(stat -c '%u:%g' "$TMP")"
# Both volumes start fresh: ownership must come from the image, not a helper.
# The variables and substitutions below belong to the container.
# shellcheck disable=SC2016
bash "$ROOT/pibox.sh" shell -c '
  test "$(id -u)" != 0
  touch /workspace/write-test
  printf persistent > "$HOME/.pi/agent/test-state"
  printf auth > "$HOME/.config/gh/test-state"
  pi --version
'
[[ "$(stat -c '%u:%g' "$TMP")" == "$owner" ]]
[[ "$(stat -c '%u:%g' "$TMP/write-test")" == "$owner" ]]
# Recreate the container: both volumes must remain usable.
# shellcheck disable=SC2016
bash "$ROOT/pibox.sh" shell -c '
  test "$(cat "$HOME/.pi/agent/test-state")" = persistent
  test "$(cat "$HOME/.config/gh/test-state")" = auth
  touch "$HOME/.pi/agent/second-run" "$HOME/.config/gh/second-run"
'
printf '%s integration tests passed.\n' "$PIBOX_ENGINE"
