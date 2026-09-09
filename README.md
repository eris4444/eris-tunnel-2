# ERIS TUNNEL 2

**🌐 Language / زبان**
[**English**](README.md) • [فارسی](README.fa.md)

```
╭────────────────────────────────────────────────────────────────╮
│ ███████╗██████╗ ██╗ ███████╗                                   │
│ ██╔════╝██╔══██╗██║ ██╔════╝                                   │
│ █████╗  ██████╔╝██║ ███████╗                                   │
│ ██╔══╝  ██╔══██╗██║ ╚════██║                                   │
│ ███████╗██║  ██║██║ ███████║                                   │
│ ╚══════╝╚═╝  ╚═╝╚═╝ ╚══════╝                                   │
│ T U N N E L  2   ·   backhaul reverse tunnel                   │
╰────────────────────────────────────────────────────────────────╯
```

**Advanced Backhaul Reverse Tunnel Manager**
`Version 2.0.0`
Support: `@erisrttg`

---

## Overview

**Eris Tunnel 2** is a Bash-based manager for installing, creating, operating,
monitoring, testing and troubleshooting reverse tunnels powered by
**Musixal/Backhaul**.

> **IRAN = Server**
> **KHAREJ = Client**
> The Pair Code is generated on IRAN and pasted on KHAREJ.

Right after you pick the side, you pick the **engine** that carries the tunnel:

| Engine | What it is |
| --- | --- |
| **Backhaul** | [Musixal/Backhaul](https://github.com/Musixal/Backhaul) — the classic core; performance profiles apply |
| **gost** | [go-gost/gost](https://github.com/go-gost/gost) v3.3.0 — relay + rtcp, nine transports |

Both sides of a tunnel must run the same engine. The pair code carries the
choice, so the KHAREJ side sets itself up to match.

Then the tunnel is created in one of **two modes**:

| Mode | What your users get |
| --- | --- |
| **Port forward** | Ports on the IRAN server that reach a panel on KHAREJ |
| **SOCKS5 proxy** | A socks5 proxy on the IRAN server whose traffic exits from KHAREJ |

## Quick Install

```
curl -fsSL https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/install.sh | bash
```

Then:

```
eristun2
```

## Architecture

```
USER
  │
  ▼
┌──────────────────────┐
│      IRAN SERVER     │
│   Backhaul Server    │
│   User-facing Ports  │
└──────────┬───────────┘
           │ Reverse Tunnel
           ▼
┌──────────────────────┐
│     KHAREJ SERVER    │
│   Backhaul Client    │
│ Xray / Panel / Apps  │
└──────────────────────┘
```

## Core Features

- Guided IRAN / KHAREJ tunnel creation, in port-forward or socks5-proxy mode
- **SOCKS5 proxy mode**: a proxy on IRAN that exits from the KHAREJ ip
- Pair Code V4, with B3 / B2 / B1 backward compatibility
- Multi-port forwarding and custom target mapping
- Two engines: Backhaul or gost, chosen per tunnel and carried in the pair code
- Backhaul transports: `tcp`, `tcpmux`, `ws`, `wsmux`, `wss`, `wssmux`, `udp`
- gost transports: `mtls`, `tls`, `tcp`, `mws`, `wss`, `ws`, `quic`, `kcp`, `grpc`
- Performance profiles: Stable, Balanced, Low Ping, Turbo
- Live terminal dashboard and kernel-level connection inspection
- Latency and throughput testing, both passive and active
- TLS certificate manager with Let's Encrypt via `acme.sh`
- systemd services, boot startup and scheduled restart timers
- Core and script self-update

<details>
<summary><b>Full feature list</b></summary>

- Advanced tuning overrides
- Endpoint management
- Traffic accounting
- Live logs, errors and event summaries
- Drop / reconnect pattern analysis
- KHAREJ speed responder
- Health check and link test
- Config fingerprint comparison
- IRAN reachability testing
- Certificate auto-discovery
- Self-signed and manual certificates
- Certificate expiry monitoring
- Partial tunnel cleanup
- Safe service stop / force kill
- Automatic config regeneration
- Manual config editing
- Random tunnel tokens
- IP / NAT detection
- Port conflict checks
- Dependency installer
- Custom update source
- Switch a tunnel between forward and proxy mode at any time
- Proxy credential rotation and a live end-to-end proxy test
- Install as `eristun2`
- Full uninstall

</details>

## Performance Profiles

| Profile  | Best for                             |
| -------- | ------------------------------------ |
| Stable   | Lossy or unstable routes             |
| Balanced | General use                          |
| Low Ping | Gaming and latency-sensitive traffic |
| Turbo    | High user / connection counts        |

A profile is picked when the tunnel is created and can be **changed at any time
afterwards** from `Manage tunnels -> [5] Profile`. The screen compares all four
side by side and applies the one you pick straight away: the config is
regenerated, the pair code is re-issued on the IRAN side, and the service is
restarted.

Each side owns different fields, and the table shows only the ones that side
actually writes:

| | |
| --- | --- |
| IRAN (server) | `channel_size`, `heartbeat`, `mux_con` |
| KHAREJ (client) | `connection_pool`, `aggressive_pool`, `retry_interval`, `dial_timeout` |
| both | `keepalive`, `nodelay` |

Mux framing is identical in every profile, so the two servers may run different
profiles without breaking the tunnel — but if you want the whole path on Turbo,
change it on both.

## Tunnel Menu

The per-tunnel screen is grouped by what each action does. `Pair code` only
appears on the IRAN side, since that is the only side that produces one.

```
CONTROL     1 Start        2 Stop       3 Restart
PAIRING     p Pair code                              (IRAN only)
CONFIGURE   4 Ports        9 SOCKS5 proxy            (4 is forward mode only)
            5 Profile      6 Endpoint   7 Scheduled restart
INSPECT     8 Show config  s Speed test L Logs + connections
ADVANCED    e Edit config by hand       d Delete tunnel
```

Advanced tuning — the transport switch and the per-value pins — is `[a]` inside
the Profile screen.

The main menu:

```
TUNNELS   1 New tunnel - IRAN    2 New tunnel - KHAREJ   3 Manage tunnels
MONITOR   4 Dashboard            5 Diagnostics
SYSTEM    6 Core                 u Update                x Uninstall
```

## The gost Engine

Backhaul puts the user ports in the IRAN config. gost works the other way
round: IRAN runs a relay with remote binding enabled, and KHAREJ asks it to
open the ports.

```
IRAN     gost -L "relay+mtls://user:token@:443?bind=true"

KHAREJ   gost -L "rtcp://:8000/127.0.0.1:8000"               -L "rtcp://:2087/127.0.0.1:2087"               -F "relay+mtls://user:token@IRAN:443"
```

`bind=true` is what lets the far side open ports on your IRAN server, so the
relay **always** requires credentials — the tunnel token is the password.

| | |
| --- | --- |
| Service, both ends | `eris-gost@<tunnel>.service` |
| Arguments | `gost.env` (mode 600); `[8] Show config` prints them readably |
| Version | pinned to **v3.3.0**, installed from `[6] Engines` |
| Certificates | gost generates its own for the TLS transports |

### Choosing a gost transport

| Transport | Good for |
| --- | --- |
| `mtls` | encrypted and multiplexed — the default, and the one to start with |
| `tls` | encrypted, one connection per stream |
| `tcp` | plain and fastest, easiest to fingerprint |
| `mws` / `wss` / `ws` | websocket framing, for putting a CDN in front |
| `quic` / `kcp` | UDP based, better on lossy paths |
| `grpc` | HTTP/2 framing, blends in with gRPC traffic |

Set the same one on both servers. `[6] Endpoint` changes it later.

### What the gost engine does not do

- **The port list lives on KHAREJ.** The `rtcp` listeners are on the client, so
  the pair code carries the ports across. Changing them means re-pairing the
  KHAREJ side — the ports screen says so and re-prints the code.
- **No performance profiles.** They tune Backhaul's pool, channel size and mux
  buffers, none of which exist in gost, so `[5] Profile` is hidden on a gost
  tunnel rather than pretending to work.
- **TCP only** — UDP forwarding is not wired up for this engine.
- User ports appear on IRAN only while KHAREJ is connected, because the relay
  opens them on the client's behalf.

## SOCKS5 Proxy Mode

Instead of forwarding fixed ports, a tunnel can be handed out as an outbound
proxy. The socks5 server runs **on the IRAN server itself** and chains through
the tunnel to an exit on KHAREJ:

```
app -socks5-> IRAN 0.0.0.0:PROXY_PORT      socks5 server on IRAN
                 chained to
              IRAN 127.0.0.1:BRIDGE_PORT   backhaul, loopback-bound
                 tunnel
              KHAREJ 127.0.0.1:EXIT_PORT   socks5 exit
                 out to the internet
```

The exit ip a site sees is the **KHAREJ** one.

Pick `SOCKS5 proxy` when creating the IRAN tunnel, then pair the KHAREJ server —
it brings its own exit up from the pair code in one step. An existing tunnel can
be moved between modes from `Manage tunnels -> [9] SOCKS5 proxy`.

| | |
| --- | --- |
| Service, both ends | `eris-proxy@<tunnel>.service` |
| Publicly bound | only IRAN's socks listener, and it always needs credentials |
| Tunnel hop | `127.0.0.1:BRIDGE_PORT` on IRAN — nothing but the local proxy reaches it |
| Proxy engine | `gost`, installed on demand from GitHub releases |
| Credentials | optional — you are asked, and asked for the values |
| Where they live | `proxy.env` (mode 600), never in the unit file |
| Transport | TCP only; SOCKS5 UDP ASSOCIATE is not carried |

### Credentials are optional

When you create a proxy tunnel it asks *"protect the proxy with a username and
password?"*. Say yes and it asks which username and password you want; say no
and it sets none. `[3] Credentials` on the proxy screen asks the same question
again later, on either side. Pressing Enter at either prompt takes the generated
suggestion.

> **Running without credentials means anyone who can reach `PROXY_PORT` can use
> the proxy**, and whatever they send leaves from your KHAREJ server's ip — which
> is a good way to get that server blacklisted or terminated. The manager warns
> you when you choose it and keeps the warning on the status screen. Only do it
> when something else already restricts who can reach the port.

Whatever you choose, both ends must match — the pair code carries it.

Worth knowing:

- The bridge port is IRAN-local plumbing. It is bound to loopback, is not in the
  pair code, and you never need to open it in a firewall. Open `PROXY_PORT` for
  your users and the tunnel port for KHAREJ, nothing else.
- Proxy mode needs a TCP transport; `udp` is refused.
- While a tunnel is in proxy mode its user-port list is kept but not forwarded,
  so switching back to forward mode restores it untouched.
- Changing the proxy port or credentials on IRAN means re-pairing KHAREJ, or
  setting the same values there by hand.

`[t] Test it` dials out through the proxy and prints the exit ip — from IRAN that
exercises the whole chain. `[5] Client settings` prints a ready
`socks5://user:pass@host:port` line.

## Diagnostics

```
Live Log
Last 60 Lines
Health Check
Link Test
Config Fingerprint
Reach Iran Server
Speed Responder
Toggle Debug Logs
```

## Core Manager

```
Latest GitHub Release
Local files from /root/backhaul
Custom URL
```

Supported architectures:

```
amd64
arm64
arm
386
```

The SHA-256 of every downloaded core binary is printed before installation.
Custom URLs must use HTTPS and require an explicit confirmation.

## Security

Eris Tunnel 2 carries the hardening done on the paths where data arrives from
outside the server:

- A Pair Code is fully validated before use. Tokens are restricted to
  `A-Z a-z 0-9 + / = . _ @ : -` and port maps to digits and separators, so a
  crafted code cannot smuggle shell metacharacters onto the server.
- `meta.conf` is parsed as key/value data against a whitelist of known keys
  rather than being sourced by the shell.
- IPv4 and hostname validation reject out-of-range octets and leading dashes.
- All temporary files use `mktemp`, so nothing lands on a predictable path
  under `/tmp`.

## Update Source

```
https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/eris-tunnel-2.sh
```

## Server Paths

```
/etc/eris-tunnel-2/
/etc/eris-tunnel-2/tunnels/
/etc/eris-tunnel-2/tunnels/<name>/proxy.env
/etc/eris-tunnel-2/certs/
/etc/systemd/system/backhaul@.service
/etc/systemd/system/eris-proxy@.service
/usr/local/bin/backhaul
/usr/local/bin/eris-gost
/usr/local/bin/eristun2
```

## Migrating from an older install

The data directory moved, so existing tunnels are not picked up automatically:

```
systemctl stop 'backhaul@*'
cp -a /etc/dark-backhaul /etc/eris-tunnel-2
systemctl start 'backhaul@*'
```

Tunnel configs, `meta.conf` files and B1/B2 Pair Codes work unchanged.

## No Web Dashboard

Backhaul's built-in web interface (`sniffer` / `web_port`) is not offered by this
manager, and generated configs pin it off so no HTTP listener is ever opened. If
a tunnel from an older build still has one running, the manager spots it on the
next start and offers to turn it off.

The live dashboard on the main menu is a terminal view, and is unaffected.

## Upstream

The tunnel engines are **Musixal/Backhaul** and **go-gost/gost**.
Eris Tunnel 2 is an independent management layer, derived from the
MIT-licensed **darktunnelmika/dark-backhaul**, and is not affiliated with
either upstream project.

## Version & Support

```
Eris Tunnel 2
Version: 2.0.0
Support: @erisrttg
```

**🌐 Language / زبان**
[**English**](README.md) • [فارسی](README.fa.md)
