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

- `PIBOX_IMAGE` - Docker image, default `jirauha/pibox`
- `PIBOX_WORKSPACE` - host directory to mount, default current directory
- `PIBOX_MEMORY` - memory limit, default `2g`
- `PIBOX_CPUS` - CPU limit, default `2`
- `PIBOX_NETWORK` - Docker network, default `bridge`
- `PIBOX_TTY` - Docker TTY mode: `auto` default, `1` force, `0` disable
- `PIBOX_SELINUX_SUFFIX` - bind-mount SELinux label suffix, default `:z` for sharing files between containers
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
