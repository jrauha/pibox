#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/project" "$TMP/other"
ln -s "$TMP/project" "$TMP/alias"
export LOG="$TMP/log" PATH="$TMP/bin:$PATH"
export CI=1 PIBOX_WORKSPACE="$TMP/project" PIBOX_TTY=0 PIBOX_GIT_IDENTITY=0
unset PIBOX_HOME_VOLUME PIBOX_GH_CONFIG_VOLUME PIBOX_GH_AUTH
unset PIBOX_EXTRA_ARGS PIBOX_IMAGE PIBOX_SANDBOX_UID PIBOX_SANDBOX_GID PIBOX_MEMORY PIBOX_CPUS
cat > "$TMP/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >> "$LOG"
printf ' <%s>' "$@" >> "$LOG"
printf '\n' >> "$LOG"
exit "${RUN_EXIT:-0}"
MOCK
cp "$TMP/bin/docker" "$TMP/bin/podman"
chmod +x "$TMP/bin/"*
run() { : > "$LOG"; bash "$ROOT/pibox.sh" "$@"; }
contains() { grep -F -- "$1" "$LOG" >/dev/null; }
rejects() {
  local expected="$1" status=0; shift
  run "$@" >/dev/null 2>&1 || status=$?
  [[ "$status" == "$expected" ]] || {
    printf 'Expected %s, got %s\n' "$expected" "$status" >&2; exit 1;
  }
}
key="$(printf '%s' "$(cd "$TMP/project" && pwd -P)" | sha256sum)"
key="${key%% *}"
for engine in docker podman; do
  export PIBOX_ENGINE="$engine"
  run -p 'hello world'
  [[ "$(wc -l < "$LOG")" == 1 ]]
  contains "$engine <run>"
  contains "<pibox-${key}-agent:/home/sandbox/.pi/agent>"
  ! contains '.config/gh'
  ! contains '<--memory>'
  ! contains '<--cpus>'
  contains '<--user> <1000:1000>'
  contains '<--cap-drop=ALL>'
  contains '<--security-opt> <no-new-privileges>'
  contains '<-p> <hello world>'
  contains '<docker.io/jirauha/pibox>'
  ! contains ':U>'
  if [[ "$engine" == podman ]]; then
    contains '<--userns> <keep-id:uid=1000,gid=1000>'
  else
    ! contains '<--userns>'
  fi
  PIBOX_WORKSPACE="$TMP/alias" run
  contains "<pibox-${key}-agent:/home/sandbox/.pi/agent>"
  PIBOX_WORKSPACE="$TMP/other" run
  ! contains "pibox-${key}-agent"
  PIBOX_HOME_VOLUME=explicit-agent PIBOX_GH_CONFIG_VOLUME=explicit-gh PIBOX_GH_AUTH=1 run
  contains '<explicit-agent:/home/sandbox/.pi/agent>'
  contains '<explicit-gh:/home/sandbox/.config/gh>'
  PIBOX_GH_AUTH=1 run
  contains "<pibox-${key}-gh:/home/sandbox/.config/gh>"
  PIBOX_MEMORY=4g PIBOX_CPUS=3 run shell -c 'echo hello'
  contains '<--memory> <4g> <--cpus> <3>'
  contains '<--entrypoint> <bash>'
  contains '<-c> <echo hello>'
  PIBOX_MEMORY=4g run
  contains '<--memory> <4g>'
  ! contains '<--cpus>'
  PIBOX_CPUS=3 run
  contains '<--cpus> <3>'
  ! contains '<--memory>'
  PIBOX_SANDBOX_UID=1234 PIBOX_SANDBOX_GID=2345 run
  contains '<--user> <1234:2345>'
  PIBOX_TTY=1 run
  contains '<-it>'
  PIBOX_READ_ONLY=1 run
  contains '<--read-only>'
  RUN_EXIT=9 rejects 9
  PIBOX_TTY=bad rejects 2
  PIBOX_SANDBOX_UID=bad rejects 2
  ! contains '<run>'
  PIBOX_HOME_TARGET="/home/sandbox/a'b" run
  contains ":/home/sandbox/a'b>"
done
PIBOX_ENGINE=invalid rejects 2
unset PIBOX_ENGINE
run -- --version
contains 'podman <run>'
contains '<--version>'
printf 'All launcher tests passed.\n'
