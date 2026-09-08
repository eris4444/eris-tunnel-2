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
`Version 1.5.1`
Support: `@erisrttg`

---

## Overview

**Eris Tunnel 2** is a Bash-based manager for installing, creating, operating,
monitoring, testing and troubleshooting reverse tunnels powered by
**Musixal/Backhaul**.

> **IRAN = Server**
> **KHAREJ = Client**
> The Pair Code is generated on IRAN and pasted on KHAREJ.

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

- Guided IRAN / KHAREJ tunnel creation
- **Local SOCKS5 proxy**: hand the tunnel out as an outbound proxy
- Pair Code V3, with B2 / B1 backward compatibility
- Multi-port forwarding and custom target mapping
- Transports: `tcp`, `tcpmux`, `ws`, `wsmux`, `wss`, `wssmux`, `udp`
- Performance profiles: Stable, Balanced, Low Ping, Turbo
- Live dashboard and kernel-level connection inspection
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
- SOCKS5 credential rotation and live proxy test
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

## Tunnel Menu

The per-tunnel screen is grouped by what each action does. `Pair code` only
appears on the IRAN side, since that is the only side that produces one.

```
CONTROL     1 Start        2 Stop       3 Restart
PAIRING     p Pair code                              (IRAN only)
CONFIGURE   4 Ports        5 Tuning     6 Endpoint    7 Scheduled restart
            9 SOCKS5 proxy
INSPECT     8 Show config  s Speed test L Logs + connections
ADVANCED    e Edit config by hand       d Delete tunnel
```

## SOCKS5 Proxy

Besides forwarding fixed ports, a tunnel can be handed out as an outbound
proxy. Apps speak SOCKS5 to the IRAN server, the tunnel carries it to KHAREJ,
and the traffic leaves from there:

```
app --socks5--> IRAN:users_port --tunnel--> 127.0.0.1:socks_port (KHAREJ) --> internet
```

So the exit ip a site sees is the **KHAREJ** one.

Turn it on from `Manage tunnels -> [9] SOCKS5 proxy` on the IRAN side, or answer
the prompt while creating an IRAN tunnel. Pair the KHAREJ server afterwards and
it sets its own proxy up from the pair code in one step.

| | |
| --- | --- |
| Service on KHAREJ | `eris-socks@<tunnel>.service` |
| Bind address | `127.0.0.1` only - the tunnel is the sole way in |
| Provider | `microsocks` from the distro, else `gost` from GitHub releases |
| Credentials | mandatory, stored in `socks.env` (mode 600) |
| Transport | TCP only; SOCKS5 UDP ASSOCIATE is not carried |

On the IRAN side the proxy is just another mapped port
(`users_port = 127.0.0.1:socks_port`), so traffic accounting, the health check
and the ports screen all understand it.

Two things worth knowing:

- Credentials are **required**, because the port is reachable from the internet
  through the IRAN side. Every client arrives at the proxy as `127.0.0.1`, so
  ip-based restrictions are meaningless here and the password is the only gate.
- Changing the ports or credentials on IRAN means re-pairing KHAREJ, or setting
  the same values there by hand. Changing plain user ports still needs no
  re-pairing.

`[t] Test the proxy` dials out through it and prints the exit ip, and
`[5] Client settings` prints a ready `socks5://user:pass@host:port` line.

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
/etc/eris-tunnel-2/tunnels/<name>/socks.env
/etc/eris-tunnel-2/certs/
/etc/systemd/system/backhaul@.service
/etc/systemd/system/eris-socks@.service
/usr/local/bin/backhaul
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

## Upstream

The tunnel core comes from **Musixal/Backhaul**.
Eris Tunnel 2 is an independent management layer, derived from the
MIT-licensed **darktunnelmika/dark-backhaul**, and is not affiliated with
either upstream project.

## Version & Support

```
Eris Tunnel 2
Version: 1.5.1
Support: @erisrttg
```

**🌐 Language / زبان**
[**English**](README.md) • [فارسی](README.fa.md)
