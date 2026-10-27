# piware

`piware/install` adds the FlightAware PiAware APT repository to a Debian or Ubuntu host. It extracts the FlightAware signing key from the `flightaware-apt-repository` package, writes an APT source entry, and runs `apt-get update`. It does not install PiAware itself.

## Requirements

- Debian or Ubuntu. The script stops on other distributions.
- Root access.
- Network access to `flightaware.com`.

## Usage

Download the installer:

```bash
curl -sL debian.lol/piware/install -o piware-install && chmod +x piware-install
```

Add the repository with the detected codename and architecture:

```bash
sudo ./piware-install
```

Add the repository for a specific codename and architecture:

```bash
sudo ./piware-install --codename bookworm --arch armhf
```

After the script completes, install PiAware:

```bash
sudo apt-get install piaware
```

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `--codename` | detected | Debian codename, for example `bookworm` |
| `--arch` | detected | APT architecture, for example `armhf`, `arm64`, or `amd64` |
| `--repo-url` | `https://flightaware.com/adsb/piaware/files/packages` | Repository URL for the source entry |
| `-h`, `--help` | | Shows the help text |

The script reads the codename from `VERSION_CODENAME` in `/etc/os-release`. If that value is missing, it maps Debian versions 9 to 12 to their codenames. For all other versions, it uses `buster`.

The script reads the architecture from `dpkg --print-architecture`. If that fails, it maps the output of `uname -m`.

If the `CURL_OPTS` or `WGET_OPTS` environment variable is set, the script adds it to the download command.

## What it changes

- `/usr/share/keyrings/flightaware-archive-keyring.gpg`: the FlightAware signing key.
- `/etc/apt/sources.list.d/piaware.list`: the source entry. If the file exists, the script first copies it to `piaware.list.bak.<timestamp>`.
- Packages: when they are missing, `gnupg`, `binutils`, `curl`, `wget`, and `xz-utils`.

## Notes

- On Ubuntu, the script writes the Ubuntu codename into the source entry. If `apt-get update` reports that the release is not found, run the script again with `--codename` and a Debian codename.
- If one of `curl` and `wget` is missing, the script installs it. The script needs only one of them.
