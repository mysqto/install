# ddns

`ddns/install` keeps a Cloudflare DNS record pointed at the public IP address of a Linux host. It installs an update script and a cron job. The cron job runs the update script every 5 minutes by default. If the record does not exist, the script creates it. When the IP address changes, the script updates the record.

## Requirements

- A Linux host with `apt-get`, `dnf`, or `yum`. When `curl`, `jq`, or cron is missing, the installer uses one of them to install it.
- Root access.
- A Cloudflare API token that can edit DNS records in the zone.
- The Cloudflare Zone ID of the zone that holds the record.

## Usage

Download the installer:

```bash
curl -sL debian.lol/ddns/install -o ddns-install && chmod +x ddns-install
```

Install an `A` record for `home.example.com`:

```bash
sudo ./ddns-install --token CF_API_TOKEN --zone-id ZONE_ID --name home.example.com
```

Install an `AAAA` record that updates every 10 minutes:

```bash
sudo ./ddns-install --token CF_API_TOKEN --zone-id ZONE_ID --name home.example.com \
  --type AAAA --interval '*/10'
```

You can also run the installer through `im`. `im -ddns` sends all arguments after `-ddns` to `ddns/install`:

```bash
im -ddns --token CF_API_TOKEN --zone-id ZONE_ID --name home.example.com
```

The installer runs one update immediately after it installs. To run an update by hand, run `/usr/local/bin/ddns-cloudflare` as root.

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-t`, `--token` | none (required) | Cloudflare API token |
| `-z`, `--zone-id` | none (required) | Cloudflare Zone ID |
| `-n`, `--name` | none (required) | DNS record name, for example `home.example.com` |
| `-T`, `--type` | `A` | Record type, `A` or `AAAA` |
| `-l`, `--ttl` | `60` | Record TTL in seconds |
| `-P`, `--proxied` | off | Turns on the Cloudflare proxy for the record |
| `-i`, `--interval` | `*/5` | Minute field of the cron entry |
| `-h`, `--help` | | Shows the help text |

If the `CURL_OPTS` environment variable is set when you install, the installer saves it in the configuration. The update script then adds it to each `curl` call.

## What it changes

- `/etc/ddns/cloudflare.conf`: the configuration, with the API token. The installer sets mode `600`.
- `/usr/local/bin/ddns-cloudflare`: the update script.
- `/etc/ddns/.current_ip`: the last IP address that the script sent to Cloudflare.
- `/var/log/ddns-cloudflare.log`: one line for each run.
- The root crontab: one entry, `<interval> * * * * /usr/local/bin/ddns-cloudflare`, with a checksum comment.
- Packages: when they are missing, `curl`, `jq`, and `cron` or `cronie`.

The update script gets the public IP address from `api.ipify.org` (`api64.ipify.org` for `AAAA`), with `ifconfig.co` as the fallback.

## Notes

- Give `--interval` a cron minute field, not a plain number. The value `10` runs the job once an hour at minute 10. Use `*/10` for every 10 minutes.
- If you run the installer again with a different `--interval`, it adds a second cron entry. It does not remove the old entry. Remove it with `crontab -e`.
- If you change the record in the Cloudflare dashboard, the script does not see the change while the public IP address stays the same. The script compares the IP address with `/etc/ddns/.current_ip` first. Delete that file to force a check against Cloudflare.
- The log file grows without limit. No log rotation is installed.
