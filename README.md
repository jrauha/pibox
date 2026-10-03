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
docker pull jirauha/pibox
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

## Git worktrees

From a Git repository, pass a name to open Pi in a persistent worktree:

```bash
./pibox.sh feature-auth
./pibox.sh feature-auth -- -p 'hello'
./pibox.sh feature-auth shell
```

This creates `.pibox/worktrees/feature-auth` on branch `pibox/feature-auth`; running it again reopens the same worktree. Without a name, pibox uses the current workspace. Always put Pi arguments after `--` (for example, `./pibox.sh -- -p 'hello'` without a worktree).

Worktrees are never removed automatically. To remove one, run `git worktree remove .pibox/worktrees/feature-auth` from the repo root; delete its branch separately if needed.

In worktree mode, the container runs at the worktree's host path (not `/workspace`) and mounts shared Git metadata read-write.

To copy Git-ignored local files into newly created worktrees, add a `.worktreeinclude` file at the repository root. It uses `.gitignore` syntax, but a file is copied only if it both matches a `.worktreeinclude` pattern and is Git-ignored; tracked files are never copied. For example:

```text
.env
.env.local
config/secrets.json
```

Patterns are relative to the repository root. Matching files are copied from the original working tree when the worktree is first created; reopening it does not overwrite worktree changes.

Or install it on your `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/pibox.sh" ~/.local/bin/pibox
pibox
```

## Common options

Configure with environment variables:

```bash
PIBOX_MEMORY=4g PIBOX_CPUS=4 pibox
PIBOX_NETWORK=none pibox
PIBOX_READ_ONLY=1 pibox
```

Useful variables:

- `PIBOX_IMAGE` - Docker image, default `jirauha/pibox`
- `PIBOX_WORKSPACE` - host directory to mount, default current directory; selects the repository in worktree mode
- `PIBOX_MEMORY` - memory limit, default `2g`
- `PIBOX_CPUS` - CPU limit, default `2`
- `PIBOX_NETWORK` - Docker network; prompts only in an interactive terminal
- `PIBOX_NETWORK_PROMPT` - set to `0` to disable the network prompt
- `PIBOX_TTY` - Docker TTY mode: `auto` default, `1` force, `0` disable
- `PIBOX_POSTGRES_HOST` - expose as `PGHOST` in the container
- `PIBOX_EXTRA_ARGS` - extra raw `docker run` arguments
- `PIBOX_GH_AUTH` - persist sandbox GitHub CLI auth, default `1`; set `0` to disable

## GitHub auth for pushing

First authenticate inside the sandbox:

```bash
pibox shell
```

Then run:

```bash
gh auth login
gh auth setup-git
```

Future runs can reuse the sandbox auth volume. Set `PIBOX_GH_AUTH=0` to disable this mount.

## PostgreSQL example

```bash
PIBOX_NETWORK=myapp_default PIBOX_POSTGRES_HOST=postgres pibox
```

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
docker build -t my-pibox .
PIBOX_IMAGE=my-pibox pibox
```
