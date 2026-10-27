# socat

These files run `socat` as a systemd service that forwards local ports to remote hosts. Each forward carries TCP and UDP. Use them on a Debian or Ubuntu host.

The directory has three files:

- `socat`: the start and stop script. `im` installs it as `/etc/socat`.
- `socatrc`: the list of forwards. `im` installs it as `/etc/socatrc`.
- `socat.service`: the systemd unit. `im` installs it as `/lib/systemd/system/socat.service`.

## Requirements

- A Debian or Ubuntu host with systemd. `im` installs the `socat` package with `apt`.
- Root, to install the files.

## Usage

1. Download `im`:

   ```bash
   curl -sL debian.lol/im -o im && chmod +x im
   ```

2. Install socat and the three files, as root:

   ```bash
   sudo ./im -so
   ```

3. Edit `/etc/socatrc`. Add one entry for each forward, in the format `remote_host:remote_port|local_port`:

   ```bash
   readonly connections=(
       "203.0.113.10:443|8443"
       "203.0.113.20:53|5353"
   )
   ```

4. Start the service:

   ```bash
   sudo systemctl start socat
   ```

`im -so` enables the service but does not start it. After a reboot, the service starts automatically.

To stop all forwards, run `sudo systemctl stop socat`.

## Options

The `/etc/socat` script takes one argument:

| Argument | What it does |
|----------|--------------|
| `start` | Stop all running `socat` processes, then start one TCP and one UDP listener for each entry in `/etc/socatrc`. |
| `stop` | Stop all running `socat` processes with `kill -9`. |

## What it changes

- Package: `socat`.
- Files: `/etc/socat`, `/etc/socatrc` and `/lib/systemd/system/socat.service`.
- Service: `socat.service` is enabled. It runs as a dynamic user with `CAP_NET_BIND_SERVICE` and restarts after 5 seconds.
- Ports: for each entry, it listens on the local port on all IPv4 addresses, for TCP and for UDP.

## Notes

The forwards use IPv4 only (`TCP4` and `UDP4`). A UDP forward closes after 600 seconds without traffic.

The script skips the example entry `dest_in_host:port_format|local_port`. With only that entry in `/etc/socatrc`, the service starts no forwards.

`start` and `stop` stop every process named `socat` on the host, not only the processes of this service.

Each `start` writes the logs to a new temporary directory, in files named `<host>.tcp.log` and `<host>.udp.log`. The service runs with a dynamic user, so the directory is in a private `/tmp` for the service.
