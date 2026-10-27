# colima

`colima/install` installs Colima and the Docker CLI on macOS with Homebrew. Colima runs the Docker engine in a small Linux VM. The script has three modes. The default mode installs the tools only. `--setup` starts the VM at login for one user. `--shared` runs one VM for the whole Mac that several users can share.

## Requirements

- macOS. The script stops on other systems.
- Homebrew in `/opt/homebrew` or `/usr/local`, or on the `PATH`.
- `python3`, to edit `~/.docker/config.json`.
- For `--shared`: `sudo`.

## Usage

Download the script:

```bash
curl -sL debian.lol/colima/install -o colima-install && chmod +x colima-install
```

### Default mode

Install the tools only. Run the script as your normal user, not with `sudo`:

```bash
./colima-install
```

Then start the VM yourself:

```bash
colima start
```

### Per-user mode (--setup)

Install the tools and add a LaunchAgent (a per-user macOS service) that starts the VM at login:

```bash
./colima-install --setup
```

The script waits up to 3 minutes for the Docker socket at `~/.colima/default/docker.sock`. Then it selects the `colima` docker context. The first start downloads the Lima VM image and takes longer.

The LaunchAgent also loads over SSH. At logout, the LaunchAgent and the VM stop.

### Shared mode (--shared)

Install the tools and add a LaunchDaemon (a system-wide macOS service). The VM runs as one owner user, starts at boot and continues after logout:

```bash
sudo bash ./colima-install --shared --members alice,bob
```

The owner is the user from `--user`. Without `--user`, it is the user that ran `sudo`.

Each member of the `colima` group then points the docker CLI at the shared socket:

```bash
export DOCKER_HOST=unix:///opt/colima/default/docker.sock   # bash, zsh
set -Ux DOCKER_HOST unix:///opt/colima/default/docker.sock  # fish
docker ps
```

A new group membership takes effect at the next login. If `id -Gn` does not show `colima`, run `newgrp colima` (bash, zsh) or open a new fish session.

### Amazon ECR registries

Give each ECR registry with `--ecr`. You can use `--ecr` in all three modes:

```bash
./colima-install --ecr 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com,public.ecr.aws
```

`docker pull` from these registries then gets a token from your AWS credentials. You do not run `docker login`. `AWS_PROFILE` must name an account that can pull from the registry.

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `--setup` | Off | Write a per-user LaunchAgent and start the VM. |
| `--shared` | Off | Write a system-wide LaunchDaemon and start a shared VM. Requires `sudo`. |
| `--user <name>` | `$SUDO_USER` | With `--shared`, the user that the shared VM runs as. |
| `--members <u1,u2>` | None | With `--shared`, users to add to the `colima` group. |
| `--ecr <r1,r2>` | None | ECR registries that use `docker-credential-ecr-login`. You can give the flag more than once. |
| `--dns <ip,ip>` | `1.1.1.1,8.8.8.8` | DNS servers for the VM, in `--setup` and `--shared`. You can give the flag more than once. |
| `--recreate-vm` | Off | Delete the VM before the restart, in `--setup` and `--shared`. |
| `-h`, `--help` | | Show the help text. |

If you give `--setup` and `--shared` together, the script uses `--shared` and ignores `--setup`. An unknown flag prints a warning, and the script continues.

## What it changes

In all modes:

- Homebrew formulae: if they are missing, it installs `colima`, `docker`, `docker-compose`, `docker-buildx`, `docker-credential-helper` and `docker-credential-helper-ecr`.
- Plugin directory: it adds `$(brew --prefix)/lib/docker/cli-plugins` to `cliPluginsExtraDirs` in `~/.docker/config.json`. Without this entry, `docker compose` fails with `unknown command`, and `docker build` uses the classic builder. With `--shared`, it does this for the owner and for each user in `--members`.
- ECR: it maps each `--ecr` registry to `ecr-login` in `credHelpers` in the same file.
- Docker Desktop leftovers: if `~/.docker/config.json` refers to the `desktop` credential helper, it changes `credsStore` to `osxkeychain` and removes `desktop` entries from `credHelpers`. It skips this step with `--shared`.

With `--setup`:

- It writes `~/Library/LaunchAgents/net.abiosoft.colima.<user>.plist` and loads it into the `user/<uid>` launchd domain.
- It logs to `~/Library/Logs/colima.log`.
- If the `colima` docker context is missing, it creates the context. Then it selects the context.

With `--shared`:

- If the `colima` group is missing, it creates the group. Then it adds the owner and the members to the group.
- It creates `/opt/colima` (`COLIMA_HOME`) and `/opt/lima` (`LIMA_HOME`), owned by the owner and the `colima` group, with mode `2775`.
- It writes `/Library/LaunchDaemons/net.abiosoft.colima.shared.plist` and loads it into the `system` launchd domain.
- It logs to `/var/log/colima-shared.log`.
- The socket is `/opt/colima/default/docker.sock`, mode `0660`, group `colima`.

## Notes

If a VM already runs, `--setup` and `--shared` stop it before they load the new service. If `colima status` reports a damaged state, the script runs `colima delete --force`. This deletes the local images, containers and volumes.

To keep local images, containers and volumes, do not use `--recreate-vm`. The flag deletes the VM disk. Use it after you change `--dns` on an existing VM, because the VM reads its DNS servers only at the first boot.

If the LaunchAgent does not load, the script runs `colima start` directly. The VM then runs for this session only and does not start at the next login. The script prints the `launchctl bootstrap` command to try again.

If another tool such as OrbStack or Docker Desktop is also installed, the docker CLI uses the active docker context. Run `docker context use colima` to use Colima. In shared mode, set `DOCKER_HOST` as shown above.
