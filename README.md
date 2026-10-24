# pibox

A development sandbox for the [Pi agent](https://pi.dev/), using rootless Podman by default.
Includes Node.js, Python, Go, Rust, Git, GitHub CLI, PostgreSQL clients, and build tools.

## Usage

```bash
./pibox.sh                     # Start Pi
./pibox.sh shell               # Open Bash
./pibox.sh -p 'hello'          # Pass Pi arguments
make build                    # Build locally
```

The default image is [`docker.io/jirauha/pibox`](https://hub.docker.com/r/jirauha/pibox).
Set `PIBOX_ENGINE=docker` for Docker; use the same engine for builds and runs.

Optional PATH installation:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/pibox.sh" ~/.local/bin/pibox
```

## Configuration

Set environment variables before running:

| Variable | Default / purpose |
| --- | --- |
| `PIBOX_ENGINE` | `podman` or `docker` |
| `PIBOX_IMAGE` | `docker.io/jirauha/pibox` |
| `PIBOX_WORKSPACE` | Current directory |
| `PIBOX_MEMORY`, `PIBOX_CPUS` | Unset; opt-in resource limits |
| `PIBOX_NETWORK` | `bridge`; use `none` to disable networking |
| `PIBOX_READ_ONLY` | `0`; set `1` for a read-only container filesystem |
| `PIBOX_GH_AUTH` | `0`; set `1` to persist GitHub auth |
| `PIBOX_HOME_VOLUME`, `PIBOX_GH_CONFIG_VOLUME` | `pi-agent-home`, `pi-gh-config` |
| `PIBOX_SANDBOX_UID`, `PIBOX_SANDBOX_GID` | Image user IDs, both `1000` |
| `PIBOX_TTY` | `auto`, `1`, or `0` |
| `PIBOX_SELINUX_SUFFIX` | `:z` |
| `PIBOX_POSTGRES_HOST` | Forwarded as `PGHOST`; port defaults to `5432` |
| `PIBOX_EXTRA_ARGS` | Extra run flags; whitespace-separated, without shell quoting |

CPU/memory limits require suitable cgroup support on rootless hosts. Without
explicit limits, the sandbox can exhaust host resources.

For custom images, prepare writable `.pi/agent` and `.config/gh` directories for
the image user. Podman maps the host user with `keep-id`. For local Docker builds,
use `make build SANDBOX_UID=$(id -u) SANDBOX_GID=$(id -g)` and pass the same IDs at runtime.

## GitHub auth

```bash
PIBOX_GH_AUTH=1 ./pibox.sh shell
# Inside the sandbox:
gh auth login
gh auth setup-git
```

Use `PIBOX_GH_AUTH=1` on subsequent runs to reuse auth.
For parallel Git worktrees, see the [Pi Worktree extension](https://github.com/AjayPoshak/pi-worktree-extension).

## Storage and security

Config persists in shared named volumes. Override their names to avoid sharing
across projects. Existing volumes with incorrect ownership need manual migration
or replacement; startup no longer repairs them. Rebuild the image for the new
directory ownership setup.

The sandbox can write the workspace and access forwarded `ANTHROPIC_API_KEY` and
any mounted credentials. Persistent config can carry malicious extensions into
future sessions. Don't share writable config across untrusted projects or mount
host home directories or engine sockets. For untrusted code, use a separate checkout,
omit credentials, and consider `PIBOX_NETWORK=none`.
