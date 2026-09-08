# Changelog

All notable changes to **Eris Tunnel 2** are recorded here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.6.0] - 2026-09-08

### Added

- **Proxy credentials are now a question, not a rule.** Creating a proxy-mode
  tunnel asks *"protect the proxy with a username and password?"*. Answer yes
  and it asks for the username and the password you want; answer no and it sets
  none at all. The same question is behind `[3] Credentials` on the proxy
  screen, on both sides, so a running proxy can be opened or closed later.
  Pressing Enter at either prompt accepts a generated suggestion.

  Running without credentials means **anyone who can reach the proxy port can
  use it**, and their traffic leaves from your KHAREJ server's ip. The manager
  says so at the moment you choose it, and keeps saying so on the status
  screen while it is off. That is the trade you are making, not a bug.

- `sweep_web_dashboard` runs at startup: if a tunnel from an older build still
  has Backhaul serving a web dashboard, it offers to regenerate the config and
  restart that tunnel.

### Changed

- **Refreshed the look.** Double-ruled frames, a violet-to-pink logo gradient
  with a violet frame colour, `▸`-marked menu items, `▌`-marked section
  headers, and `✓ ✗ ▲ ▸` status glyphs in place of `+ x ! >`.

- **Reworked the main menu.** Creating and managing tunnels comes first, the
  core installer moved into a SYSTEM group, and maintenance moved onto letter
  keys:

  ```
  TUNNELS   1 New tunnel - IRAN    2 New tunnel - KHAREJ   3 Manage tunnels
  MONITOR   4 Dashboard            5 Diagnostics
  SYSTEM    6 Core                 u Update                x Uninstall
  ```

- In the per-tunnel menu, `[9] SOCKS5 proxy` now sits next to `[4] Ports`,
  since between them they decide what the tunnel actually does.

- The pair code stays **B4**: empty credential fields are what "no
  authentication" looks like on the wire, so a 1.5.1 side still pairs fine with
  a 1.6.0 side whenever credentials are in use. A no-credentials code is only
  understood from 1.6.0 onward.

- A tunnel whose credentials were *asked for* but no longer validate loads with
  proxy mode off rather than running an unintentionally open proxy. With
  credentials deliberately off, no such check applies.

### Removed

- **The built-in web dashboard is gone.** The prompts, the `WEB_PORT` and
  `SNIFFER` metadata, the status rows and the `sniffer_log` file all went with
  it, and generated configs now pin `sniffer = false` / `web_port = 0` so
  Backhaul never opens an HTTP listener. Existing tunnels are offered the
  cleanup described above on the next start.

  The terminal dashboard (main menu `[4]`) is untouched — it was never the web
  one.

## [1.5.1] - 2026-09-08

### Added

- **Tunnel modes.** An IRAN tunnel is now created as one of two shapes, picked
  from a menu right after the public ip is entered:

  - `port forward` — the classic one. Ports on IRAN reach a panel on KHAREJ.
  - `socks5 proxy` — the tunnel is handed out as an outbound proxy instead.

- **Proxy mode runs the socks5 server on IRAN itself**, and chains it through
  the tunnel to an exit on KHAREJ:

  ```
  app -socks5-> IRAN 0.0.0.0:PROXY_PORT      socks5 server on IRAN
                   chained to
                IRAN 127.0.0.1:BRIDGE_PORT   backhaul, loopback-bound
                   tunnel
                KHAREJ 127.0.0.1:EXIT_PORT   socks5 exit
                   out to the internet
  ```

  The exit ip a site sees is the KHAREJ one. The **only publicly bound port is
  IRAN's own socks listener**, and it always asks for a username and password.
  The tunnel's own hop is `127.0.0.1:BRIDGE_PORT` on IRAN, so nothing but the
  local proxy can reach it — Backhaul's documented `"127.0.0.1:port=target"`
  form makes that bind possible.

- Both ends run the proxy as `eris-proxy@<tunnel>.service`. One unit template
  serves both roles: the whole argument list lives in a per-tunnel `proxy.env`
  (mode 600) and reaches `ExecStart` as an unbraced `$GOST_ARGS`, which systemd
  splits on whitespace — so credentials never sit in the unit file.

- `gost` is the proxy engine, installed on demand from GitHub releases for the
  detected architecture, with its sha256 printed first. It is the only small
  proxy that both serves socks5 and chains to an upstream one, which is exactly
  what proxy mode needs.

- A tunnel can be moved between modes later from `Manage tunnels -> [9] SOCKS5
  proxy`, on either side. The user-port list is kept while a tunnel sits in
  proxy mode, so switching back restores it untouched.

- `[t] Test it` dials out through the proxy and prints the exit ip — from IRAN
  it proves the whole chain, from KHAREJ just the exit.
  `[5] Client settings` prints a ready `socks5://user:pass@host:port` line.

- Traffic accounting follows the mode: user ports in forward mode, the socks
  port in proxy mode. Health check gained the bridge socket, the proxy service
  and the exit socket.

### Changed

- **Pair code is now B4**, carrying the mode, the exit port, the public proxy
  port and the credentials, so pairing a KHAREJ server brings its exit up in one
  step. Codes are emitted with an `ETN-` prefix. **B3, B2 and B1 still parse**,
  and `DBH-` prefixed codes from 1.0.2 and from DARK VPN Backhaul keep working.
  The bridge port is IRAN-local plumbing and is deliberately not in the code.
- Every mode and proxy field is validated on arrival and re-validated on each
  `meta.conf` load: user `A-Z a-z 0-9 _ -` (1–32), password
  `A-Z a-z 0-9 . _ + -` (6–64). `:` `@` `/` and every shell metacharacter are
  refused, so nothing hostile reaches the systemd unit or the proxy url. A
  tunnel that lacks anything proxy mode needs loads as a plain forward, never as
  half of one.
- Proxy mode refuses the `udp` transport, and switches a new tunnel to the
  default transport rather than building something that cannot work.
- `gh_asset_url` was split so a release asset can be resolved for any
  repository, not just the Backhaul core.
- `meta_set` replaces the scattered `sed -i` calls that edited `meta.conf`, and
  appends a key that is not there yet instead of silently doing nothing.
- Tunnels created before this version gain `MODE="forward"` and the proxy keys
  on first load, and behave exactly as they did.
- The dashboard's LISTENING panel now includes the proxy's sockets.

### Fixed

- Creating a KHAREJ tunnel could write a stale `TLS_CERT` / `TLS_KEY` path into
  its `meta.conf`, carried over from an IRAN tunnel visited earlier in the same
  session. Both are now cleared before the metadata is written.

### Removed

- The first 1.5.1 build published the proxy the other way round — a socks server
  on KHAREJ reached through an ordinary forwarded port — which left the only
  authentication out on the far side of the tunnel. That shape is gone. On
  startup the manager takes down and deletes the `eris-socks@` unit it left
  behind, so nothing keeps listening under rules this build no longer applies.
  Turn proxy mode on again from a tunnel's `[9]` screen.
- Uninstall now also removes `eris-proxy@.service` and the gost binary.

## [1.0.2] - 2026-09-08

First release under the **Eris Tunnel 2** name. The manager was rebranded end
to end and its on-disk identity changed, so this is a clean 1.0.x line rather
than a continuation of the upstream numbering.

### Changed

- Project renamed to **Eris Tunnel 2**. Banner, menus, systemd unit
  descriptions and Pair Code headers all carry the new name.
- Command renamed `darkbh` -> **`eristun2`** (`/usr/local/bin/eristun2`).
- Data directory moved `/etc/dark-backhaul` -> **`/etc/eris-tunnel-2`**
  (tunnels and certs live under it as before).
- Script file renamed `dark-backhaul.sh` -> **`eris-tunnel-2.sh`**, and the
  install / self-update sources now point at
  `github.com/eris4444/eris-tunnel-2`.
- Manager marker changed `DARKVPN-BACKHAUL-SCRIPT` -> `ERIS-TUNNEL-2-SCRIPT`.
  The installer and the self-update path both verify the new marker.
- iptables accounting chain renamed `DARKBH_ACCT` -> `ERISTUN2_ACCT`.
- Support contact is now `@erisrttg`.

### Migration from a DARK VPN Backhaul install

Existing tunnels are not picked up automatically, because the data directory
moved. On a host that already runs the old manager:

```
systemctl stop 'backhaul@*'
cp -a /etc/dark-backhaul /etc/eris-tunnel-2
systemctl start 'backhaul@*'
```

`meta.conf` files, tunnel configs and B1/B2 Pair Codes are unchanged and work
as they are. The old `darkbh` command can then be removed with
`rm -f /usr/local/bin/darkbh`.

### Inherited behaviour

Everything the upstream 1.9.2 release did is carried over unchanged, including
its security work:

- Pair Codes are fully validated before use; `meta.conf` is parsed as key/value
  data against a whitelist instead of being sourced by the shell.
- `valid_token` (8-128 chars, `A-Z a-z 0-9 + / = . _ @ : -`) and
  `valid_ports_csv` guard both the Pair Code path and manual entry.
- `valid_ip4` range-checks each octet and rejects leading zeros;
  `valid_host` rejects hostnames beginning with `-`.
- All temporary files use `mktemp`.
- The SHA-256 of every downloaded core binary is shown before installation, and
  custom core URLs must be HTTPS with explicit confirmation.

## Upstream

Eris Tunnel 2 is derived from the MIT-licensed **DARK VPN Backhaul Manager**
(`darktunnelmika/dark-backhaul`), forked at its 1.9.2 release. The tunnel core
itself comes from [Musixal/Backhaul](https://github.com/Musixal/Backhaul).
