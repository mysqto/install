# go

`go` installs the latest Go release from `go.dev`. It runs on Linux and macOS. If the installed `go` version is already the latest, the script does not download it again.

## Requirements

- Linux or macOS.
- One of these CPU types: `x86_64`, `i386`/`i686`, `aarch64`/`arm64`, or `armv6l`.
- Root access. If you are not root, the script runs itself again with `sudo`.
- `curl`, `tar`, and `python3`. The script uses `python3` to resolve file paths.

## Usage

Download the script and run it:

```bash
curl -sL debian.lol/go -o go && chmod +x go
./go
```

To also install the Go tools that the script lists, add `--setup`:

```bash
./go --setup
```

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-s`, `--setup` | off | After Go is installed, runs `go install` for `gocode`, `golangci-lint`, and `goimports`. |

The script shows a warning for any other argument and then continues.

## What it changes

The install location depends on the operating system:

| System | Go root | Links to the binaries |
|--------|---------|------------------------|
| Linux | `/opt/go` | `/usr/bin/<tool>` through `update-alternatives` |
| macOS on Intel | `/usr/local/opt/go` | `/usr/local/bin/<tool>` |
| macOS on Apple Silicon | `/opt/homebrew/opt/go` | `/opt/homebrew/bin/<tool>` |

On Linux without `update-alternatives`, the script makes the links in `/usr/local/bin` instead. The script makes one link for each file in `<go root>/bin`, for example `go` and `gofmt`.

With `--setup`, `go install` runs as root. The tools go into the Go binary directory of the root user, not of your own user.

## Notes

- If an older Go root exists at the install location, the script deletes it before it extracts the new release.
- `gocode` comes from `github.com/nsf/gocode`. That project is no longer maintained.
