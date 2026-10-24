# pibox

Simple opinionated dev sandbox for the [Pi agent](https://pi.dev/).

Included tools:

- Node.js/npm and `pi`
- Python 3, pip, and venv
- Go
- Rust, Cargo, and rustfmt
- Git, GitHub CLI, ripgrep, fd
- PostgreSQL client tools and common build tools

## Image

The default image is published at [`jirauha/pibox`](https://hub.docker.com/r/jirauha/pibox).

```bash
podman pull docker.io/jirauha/pibox
```

## Build locally

```bash
make build
```

## Run

```bash
./pibox.sh
```

Open a shell instead of `pi`:

```bash
./pibox.sh shell
```

Pass Pi arguments directly:

```bash
./pibox.sh -p 'hello'
```

Or install it on your `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/pibox.sh" ~/.local/bin/pibox
pibox
```

## Podman

Rootless Podman is the default:

```bash
pibox shell
make build
```

To use Docker instead, set `PIBOX_ENGINE=docker` for both the launcher and Make.

Docker and Podman have separate local image and volume stores. The image name
is fully qualified to avoid Podman short-name resolution prompts.

Podman uses `--userns=keep-id:uid=1000,gid=1000` so the host user can write the
workspace as the image user, without changing host file ownership. Custom images
must set `PIBOX_SANDBOX_UID` and `PIBOX_SANDBOX_GID` to their image user IDs.
The Makefile defaults to `1000:1000` and passes its `SANDBOX_UID`/`SANDBOX_GID`
settings to both builds and runs. With Docker, use the host UID/GID when building
locally if they differ from 1000 and workspace writes are needed.

The image prepares non-root-owned Pi and GitHub config directories at build
time. Fresh volumes inherit their ownership. Startup never runs a root repair
container or recursively changes ownership. Custom images must prepare the same
directories (including custom mount targets) for their configured user.
Rebuild the image to pick up this behavior; older published images may not yet
prepare the GitHub directory.

Existing incorrectly owned volumes require an explicit, one-time migration or
replacement. Stop their users and back up data first; migrate to the same user
mapping used by the launcher. Do not add `:U` to the workspace mount.
`PIBOX_INIT_HOME_VOLUME` has been removed.

CPU and memory limits are opt-in because some rootless hosts do not delegate
these cgroup controllers. Set `PIBOX_MEMORY=4g` and/or `PIBOX_CPUS=2` to enable
them; leave them unset or empty to omit the corresponding flags. Rootless Podman
requires cgroup v2 and appropriate controller delegation to enforce them.
Without these limits, the container can exhaust host memory or CPU. Explicitly
configured limits are passed to the engine and are never silently dropped.

## Config isolation and untrusted projects

By default, each canonical workspace path gets separate Pi config and (when
explicitly enabled) GitHub auth volumes. The names use a SHA-256 hash of the path;
symlinks resolve to the same workspace, while separate worktrees get separate
config. Moving a project selects new volumes; old volumes are not deleted.

GitHub auth persistence is disabled by default; `PIBOX_GH_AUTH=1` opts in.

The sandbox can still modify the mounted workspace and use the forwarded
`ANTHROPIC_API_KEY`. For untrusted code, use a disposable checkout, omit API
credentials, and consider `PIBOX_NETWORK=none`, for example:

```bash
env -u ANTHROPIC_API_KEY PIBOX_NETWORK=none pibox shell
```

No host home or engine socket is mounted by default. Extra mounts and flags can weaken this boundary. `keep-id`
is a permission mapping, not an additional security boundary.

Persistent config can carry malicious extensions/settings into future sessions
for the same project. Do not share writable config or credential volumes across
untrusted projects. Explicit `PIBOX_HOME_VOLUME` / `PIBOX_GH_CONFIG_VOLUME`
overrides opt out of per-project naming. Old global volumes (`pi-agent-home` and
`pi-gh-config`) are not reused automatically; choosing them explicitly restores
sharing and may require the one-time ownership migration described above.

## Git worktrees

For parallel Pi tasks in isolated Git worktrees, use the [Pi Worktree extension](https://github.com/AjayPoshak/pi-worktree-extension). Install it once inside the sandbox:

```bash
./pibox.sh shell
pi install npm:pi-worktree-extension
exit
```

See the [extension README](https://github.com/AjayPoshak/pi-worktree-extension#readme) for details. Extensions execute with the sandbox's permissions; review third-party code before installing it.

## Common options

Configure with environment variables:

```bash
PIBOX_MEMORY=4g PIBOX_CPUS=4 pibox
PIBOX_NETWORK=none pibox
PIBOX_READ_ONLY=1 pibox
```

Useful variables:

- `PIBOX_ENGINE` - `podman` (default) or `docker`; also used by the Makefile
- `PIBOX_IMAGE` - image, default `docker.io/jirauha/pibox`
- `PIBOX_SANDBOX_UID` / `PIBOX_SANDBOX_GID` - image user IDs, default `1000:1000`
- `PIBOX_HOME_VOLUME` / `PIBOX_GH_CONFIG_VOLUME` - explicit persistent volume names; default per workspace
- `PIBOX_WORKSPACE` - host directory to mount, default current directory
- `PIBOX_MEMORY` - optional memory limit, unset by default
- `PIBOX_CPUS` - optional CPU limit, unset by default
- `PIBOX_NETWORK` - engine network, default `bridge`
- `PIBOX_TTY` - container TTY mode: `auto` default, `1` force, `0` disable
- `PIBOX_SELINUX_SUFFIX` - bind-mount SELinux label suffix, default `:z` for sharing files between containers
- `PIBOX_POSTGRES_HOST` - expose as `PGHOST` in the container
- `PIBOX_EXTRA_ARGS` - extra raw engine `run` arguments (simple whitespace-separated flags; not shell quoting)
- `PIBOX_GH_AUTH` - mount GitHub CLI config, default `0`; set `1` to opt in

## GitHub auth for pushing

First authenticate inside the sandbox:

```bash
PIBOX_GH_AUTH=1 pibox shell
```

Then run:

```bash
gh auth login
gh auth setup-git
```

Use `PIBOX_GH_AUTH=1` on future runs in the same workspace to reuse its auth
volume. Leave it unset for tasks that do not need credentials.

## PostgreSQL example

```bash
PIBOX_NETWORK=myapp_default PIBOX_POSTGRES_HOST=postgres pibox
```

## Tests

```bash
bash tests/pibox.sh                     # Mocked Docker/Podman argument tests
bash tests/container-integration.sh podman # Builds an image; requires rootless Podman
bash tests/container-integration.sh docker # Requires Docker and host UID/GID 1000
```

For Docker on other host IDs, set `PIBOX_SANDBOX_UID=$(id -u)` and
`PIBOX_SANDBOX_GID=$(id -g)` when running the integration test.
The integration script also supports custom image UID/GID settings with rootless Podman.

## Extend the image

Create a project-specific image when you need extra system packages:

```dockerfile
FROM jirauha/pibox

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends php composer \
  && rm -rf /var/lib/apt/lists/*

USER 1000:1000
```

Build and use it:

```bash
podman build -t my-pibox .
PIBOX_IMAGE=my-pibox pibox
```
