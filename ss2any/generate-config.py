#!/usr/bin/env python3
"""ss2any config generator.

Two subcommands, sharing one parser:

  plan-ports <config>   Print one "PORT/PROTO" line per inbound (used by the
                        host-side `run` launcher to build docker -p flags).

  generate   <config>   Emit a full sing-box JSON config to stdout (used by
                        the container entrypoint).

The config is YAML (preferred) or JSON. Schema:

  inbounds:
    - port: 8388
      password: alice
      method: chacha20-ietf-poly1305     # optional
      network: tcp                       # tcp | udp | tcp_and_udp
      route: chain-jp                    # name of upstream OR chain
      tag: ss-jp                         # optional
      listen: "::"                       # optional
  upstreams:
    hop_a: "vless://..."
    hop_b: "trojan://..."
  chains:
    chain-jp: [hop_a, hop_b]             # client -> hop_a -> hop_b -> internet

A single-link shortcut (no config file) is supported via env vars:
PROXY_LINK + SS_PORT + SS_PASSWORD (+ SS_METHOD, SS_NETWORK).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from urllib.parse import parse_qs, unquote, urlparse

OUTBOUND_TAG = "proxy-out"


# ---------- URL parsers ----------

def _qs(parsed) -> dict[str, str]:
    return {k: v[0] for k, v in parse_qs(parsed.query).items()}


def _apply_tls(out: dict, q: dict, default_sni: str) -> None:
    security = q.get("security", "none")
    if security not in ("tls", "reality", "xtls"):
        return
    tls = {
        "enabled": True,
        "server_name": q.get("sni") or q.get("peer") or q.get("host") or default_sni,
    }
    if q.get("alpn"):
        tls["alpn"] = [a for a in q["alpn"].split(",") if a]
    if q.get("fp"):
        tls["utls"] = {"enabled": True, "fingerprint": q["fp"]}
    if q.get("allowInsecure") in ("1", "true"):
        tls["insecure"] = True
    if security == "reality":
        tls["reality"] = {
            "enabled": True,
            "public_key": q.get("pbk", ""),
            "short_id": q.get("sid", ""),
        }
    out["tls"] = tls


def _apply_transport(out: dict, q: dict, default_host: str) -> None:
    net = q.get("type", "tcp")
    if net in ("tcp", "raw", ""):
        return
    if net == "ws":
        t = {"type": "ws", "path": q.get("path", "/")}
        if q.get("host"):
            t["headers"] = {"Host": q["host"]}
        out["transport"] = t
    elif net == "grpc":
        out["transport"] = {"type": "grpc", "service_name": q.get("serviceName", "")}
    elif net in ("http", "h2"):
        t = {"type": "http"}
        if q.get("path"):
            t["path"] = q["path"]
        if q.get("host"):
            t["host"] = [h for h in q["host"].split(",") if h]
        out["transport"] = t
    elif net == "httpupgrade":
        out["transport"] = {
            "type": "httpupgrade",
            "path": q.get("path", "/"),
            "host": q.get("host", default_host),
        }
    elif net == "quic":
        out["transport"] = {"type": "quic"}
    else:
        sys.stderr.write(f"warn: unknown transport '{net}', falling back to tcp\n")


def parse_vless(url: str) -> dict:
    p = urlparse(url)
    q = _qs(p)
    out = {
        "type": "vless",
        "server": p.hostname,
        "server_port": p.port,
        "uuid": unquote(p.username or ""),
    }
    if q.get("flow"):
        out["flow"] = q["flow"]
    if q.get("encryption") and q["encryption"] != "none":
        out["packet_encoding"] = q["encryption"]
    _apply_tls(out, q, default_sni=p.hostname or "")
    _apply_transport(out, q, default_host=p.hostname or "")
    return out


def parse_trojan(url: str) -> dict:
    p = urlparse(url)
    q = _qs(p)
    out = {
        "type": "trojan",
        "server": p.hostname,
        "server_port": p.port,
        "password": unquote(p.username or ""),
    }
    if "security" not in q:
        q["security"] = "tls"
    _apply_tls(out, q, default_sni=p.hostname or "")
    _apply_transport(out, q, default_host=p.hostname or "")
    return out


def parse_vmess(url: str) -> dict:
    payload = url[len("vmess://"):]
    payload += "=" * (-len(payload) % 4)
    data = json.loads(base64.urlsafe_b64decode(payload.encode()))
    out = {
        "type": "vmess",
        "server": data.get("add"),
        "server_port": int(data.get("port", 0)),
        "uuid": data.get("id"),
        "security": data.get("scy", "auto"),
        "alter_id": int(data.get("aid", 0) or 0),
    }
    q = {
        "type": data.get("net", "tcp"),
        "security": "tls" if data.get("tls") == "tls" else "none",
        "sni": data.get("sni") or data.get("host") or data.get("add"),
        "host": data.get("host", ""),
        "path": data.get("path", "/"),
        "alpn": data.get("alpn", ""),
        "fp": data.get("fp", ""),
        "serviceName": data.get("path", ""),
    }
    _apply_tls(out, q, default_sni=data.get("add", ""))
    _apply_transport(out, q, default_host=data.get("add", ""))
    return out


def parse_ss(url: str) -> dict:
    p = urlparse(url)
    userinfo = p.username or ""
    password = p.password
    method = userinfo
    if password is None:
        try:
            pad = "=" * (-len(userinfo) % 4)
            decoded = base64.urlsafe_b64decode((userinfo + pad).encode()).decode()
            if ":" in decoded:
                method, password = decoded.split(":", 1)
        except Exception:
            pass
    return {
        "type": "shadowsocks",
        "server": p.hostname,
        "server_port": p.port,
        "method": method,
        "password": unquote(password or ""),
    }


def parse_hysteria2(url: str) -> dict:
    p = urlparse(url)
    q = _qs(p)
    out = {
        "type": "hysteria2",
        "server": p.hostname,
        "server_port": p.port,
        "password": unquote(p.username or ""),
    }
    tls = {"enabled": True, "server_name": q.get("sni") or p.hostname or ""}
    if q.get("insecure") in ("1", "true"):
        tls["insecure"] = True
    if q.get("alpn"):
        tls["alpn"] = [a for a in q["alpn"].split(",") if a]
    out["tls"] = tls
    if q.get("obfs"):
        out["obfs"] = {"type": q["obfs"], "password": q.get("obfs-password", "")}
    return out


def parse_tuic(url: str) -> dict:
    p = urlparse(url)
    q = _qs(p)
    out = {
        "type": "tuic",
        "server": p.hostname,
        "server_port": p.port,
        "uuid": unquote(p.username or ""),
        "password": unquote(p.password or ""),
        "congestion_control": q.get("congestion_control", "bbr"),
    }
    tls = {"enabled": True, "server_name": q.get("sni") or p.hostname or ""}
    if q.get("alpn"):
        tls["alpn"] = [a for a in q["alpn"].split(",") if a]
    if q.get("allow_insecure") in ("1", "true"):
        tls["insecure"] = True
    out["tls"] = tls
    return out


PARSERS = {
    "vless": parse_vless,
    "trojan": parse_trojan,
    "vmess": parse_vmess,
    "ss": parse_ss,
    "hysteria2": parse_hysteria2,
    "hy2": parse_hysteria2,
    "tuic": parse_tuic,
}


def parse_link(url: str) -> dict:
    scheme = url.split("://", 1)[0].lower()
    if scheme not in PARSERS:
        raise ValueError(f"unsupported scheme: {scheme}")
    return PARSERS[scheme](url)


# ---------- Schema loading ----------

def _load_yaml_or_json(text: str) -> dict:
    try:
        import yaml  # type: ignore
        return yaml.safe_load(text)
    except ImportError:
        return json.loads(text)


def load_schema(path: str | None) -> dict:
    """Load a schema from file, or synthesize one from env vars.

    Falls back to the legacy single-link path when no file exists but
    PROXY_LINK is set.
    """
    if path and os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            schema = _load_yaml_or_json(f.read())
        if not isinstance(schema, dict):
            sys.exit(f"{path}: top-level must be a mapping")
        return schema

    link = os.environ.get("PROXY_LINK", "").strip()
    if not link:
        link_file = os.environ.get("PROXY_LINK_FILE", "")
        if link_file and os.path.isfile(link_file):
            with open(link_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        link = line
                        break
    if not link:
        sys.exit("no config file and no PROXY_LINK env var")
    return {
        "inbounds": [{
            "port": int(os.environ.get("SS_PORT", "8388")),
            "password": os.environ.get("SS_PASSWORD") or "",
            "method": os.environ.get("SS_METHOD", "chacha20-ietf-poly1305"),
            "network": os.environ.get("SS_NETWORK", "tcp"),
            "route": "default",
            "tag": "ss-in",
        }],
        "upstreams": {"default": link},
    }


# ---------- Output builders ----------

UDP_BOTH = {"tcp_and_udp", "tcp,udp", "both", "any"}


def cmd_plan_ports(schema: dict) -> None:
    seen: set[tuple[int, str]] = set()
    for ib in schema.get("inbounds", []):
        try:
            port = int(ib["port"])
        except (KeyError, TypeError, ValueError):
            sys.exit(f"inbound missing/invalid 'port': {ib!r}")
        network = (ib.get("network") or "tcp").lower()
        protos = ["tcp", "udp"] if network in UDP_BOTH else [network]
        for proto in protos:
            if proto not in ("tcp", "udp"):
                sys.exit(f"inbound port {port}: bad network '{proto}'")
            key = (port, proto)
            if key in seen:
                sys.exit(f"duplicate inbound port {port}/{proto}")
            seen.add(key)
            print(f"{port}/{proto}")


def cmd_generate(schema: dict) -> None:
    upstreams = schema.get("upstreams") or {}
    chains = schema.get("chains") or {}
    if not isinstance(upstreams, dict):
        sys.exit("'upstreams' must be a mapping of name -> url")
    if not isinstance(chains, dict):
        sys.exit("'chains' must be a mapping of name -> list[str]")

    inbounds_out: list[dict] = []
    outbounds_out: list[dict] = []
    rules: list[dict] = []
    summary: list[str] = []

    raw_inbounds = schema.get("inbounds") or []
    if not raw_inbounds:
        sys.exit("'inbounds' must contain at least one entry")

    for idx, ib in enumerate(raw_inbounds):
        port = int(ib["port"])
        ib_tag = ib.get("tag") or f"ss-in-{port}"
        password = ib.get("password")
        if not password:
            sys.exit(f"inbound {ib_tag}: 'password' is required")
        method = ib.get("method", "chacha20-ietf-poly1305")
        network = (ib.get("network") or "tcp").lower()

        sb_in = {
            "type": "shadowsocks",
            "tag": ib_tag,
            "listen": ib.get("listen", "::"),
            "listen_port": port,
            "method": method,
            "password": password,
        }
        if network not in UDP_BOTH:
            sb_in["network"] = network
        inbounds_out.append(sb_in)

        route_name = ib.get("route")
        if not route_name:
            sys.exit(f"inbound {ib_tag}: 'route' is required")
        if route_name in chains:
            chain = list(chains[route_name])
        elif route_name in upstreams:
            chain = [route_name]
        else:
            sys.exit(
                f"inbound {ib_tag}: route '{route_name}' is neither a chain "
                f"nor an upstream"
            )
        if not chain:
            sys.exit(f"chain '{route_name}' is empty")

        # Build per-inbound outbound chain. Tags are unique per (inbound, position)
        # so the same upstream can be reused across inbounds without collision.
        prev_tag: str | None = None
        for hop_idx, up_name in enumerate(chain):
            if up_name not in upstreams:
                sys.exit(f"upstream '{up_name}' (chain '{route_name}') is not defined")
            try:
                ob = parse_link(upstreams[up_name])
            except Exception as exc:
                sys.exit(f"upstream '{up_name}': {exc}")
            ob["tag"] = f"{ib_tag}__{hop_idx:02d}__{up_name}"
            if prev_tag:
                ob["detour"] = prev_tag
            outbounds_out.append(ob)
            prev_tag = ob["tag"]

        assert prev_tag is not None
        rules.append({"inbound": [ib_tag], "outbound": prev_tag})
        summary.append(
            f"  {ib_tag} :{port}/{network}  ->  "
            + " -> ".join(chain)
        )

    outbounds_out.append({"type": "direct", "tag": "direct"})
    outbounds_out.append({"type": "block", "tag": "block"})

    cfg = {
        "log": {
            "level": os.environ.get("LOG_LEVEL", schema.get("log_level", "info")),
            "timestamp": True,
        },
        "dns": {
            "servers": [{"tag": "local", "address": "local"}],
            "strategy": "prefer_ipv4",
        },
        "inbounds": inbounds_out,
        "outbounds": outbounds_out,
        "route": {"rules": rules, "final": "direct"},
    }

    sys.stderr.write("ss2any routes:\n" + "\n".join(summary) + "\n")
    json.dump(cfg, sys.stdout, indent=2)
    sys.stdout.write("\n")


# ---------- Entry point ----------

def main() -> None:
    ap = argparse.ArgumentParser(prog="generate-config.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("plan-ports", "generate"):
        s = sub.add_parser(name)
        s.add_argument("config", nargs="?", help="path to ss2any.yaml (optional)")

    args = ap.parse_args()
    schema = load_schema(args.config)
    if args.cmd == "plan-ports":
        cmd_plan_ports(schema)
    elif args.cmd == "generate":
        cmd_generate(schema)


if __name__ == "__main__":
    main()
