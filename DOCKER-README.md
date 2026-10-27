# docker

`docker` installs Docker Engine from the official Docker apt repository. It runs on Debian and Ubuntu hosts.

## Requirements

- Debian or Ubuntu. The script stops on any other distribution.
- Root access. If you are not root, the script runs itself again with `sudo`.
- Network access to `download.docker.com`.

## Usage

Download the script and run it on the target host:

```bash
curl -sL debian.lol/docker -o docker && chmod +x docker
./docker
```

To force IPv4 for the download of the Docker GPG key, add `-4`:

```bash
./docker -4
```

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-4`, `--ipv4` | off | Adds `-4` to the `curl` call that downloads the Docker GPG key. |
| `-6`, `--ipv6` | off | Adds `-6` to the `curl` call that downloads the Docker GPG key. |

The script also reads `CURL_OPTS` from the environment. A flag replaces that value. The script ignores all other arguments and does not show a warning for them.

## What it changes

- Installs `ca-certificates` and `curl`.
- Creates `/etc/apt/keyrings` and writes the Docker GPG key to `/etc/apt/keyrings/docker.asc`.
- Writes the apt source `/etc/apt/sources.list.d/docker.list` for the `stable` channel of your distribution and release codename.
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`.

The script does not add a user to the `docker` group. To do that, run `usermod -aG docker <user>`, or use `provision --docker` or `im --docker -u <user>`, which do it for you.

## Notes

- If the script runs without a terminal and you are not root, it uses `gksu` instead of `sudo`. It then writes its output to `output_file` in the current directory.
- The `-4` and `-6` flags do not change how `apt` connects. Only the GPG key download uses them.
