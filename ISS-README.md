# iss

`iss` is a short wrapper that downloads and runs the [`ss-rust`](ss-rust) Shadowsocks server installer. It takes one optional argument, the password.

## Requirements

- The requirements of `ss-rust`. `iss` adds none of its own.
- Network access to `debian.lol`. If that host does not respond in 5 seconds, `iss` uses the GitHub copy of the repository at `raw.githubusercontent.com/mysqto/install/gh-pages`.

## Usage

Download the script and run it:

```bash
curl -sL debian.lol/iss -o iss && chmod +x iss
./iss
```

To set the Shadowsocks password, add `--password`:

```bash
./iss --password 'your_password_here'
```

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-p`, `--password` | none | Sends `--password <value>` to `ss-rust`. Without it, `ss-rust` uses its own default. |

`iss` does not forward any other argument to `ss-rust`. To use other `ss-rust` options, run `ss-rust` directly.

## What it changes

`iss` changes nothing itself. `ss-rust` makes all the changes.

## Notes

- `iss` calls `warn`, `info`, and `error`, but it does not define them. If you give an unknown argument, or if neither download host responds, the shell shows `command not found`. If both hosts fail, the script does not stop.
