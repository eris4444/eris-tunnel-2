# Changelog

All notable changes to **Eris Tunnel 2** are recorded here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.5.1] - 2026-09-08

### Added

- **Local SOCKS5 proxy over the tunnel.** Alongside plain port forwarding, a
  tunnel can now be handed out as an outbound proxy:

  ```
  app --socks5--> IRAN:users_port --tunnel--> 127.0.0.1:socks_port on KHAREJ --> internet
  ```

  The exit ip a site sees is the KHAREJ one. Turn it on from
  `Manage tunnels -> [9] SOCKS5 proxy`, or answer the new prompt while creating
  an IRAN tunnel.

- The proxy runs on the KHAREJ server as `eris-socks@<tunnel>.service`, bound to
  **127.0.0.1 only**, so the tunnel is the sole way in. Credentials are
  mandatory - there is no unauthenticated mode, because the port is reachable
  from the internet through the IRAN side.

- Provider is picked automatically: **microsocks** from the distribution's own
  repository when it is packaged there, otherwise a pinned-architecture
  **gost** binary from GitHub releases (sha256 shown before it is installed).

- On the IRAN side the proxy is just another mapped port
  (`users_port = 127.0.0.1:socks_port`), so traffic accounting, the health
  check and the ports screen all understand it. The ports list labels that row
  `-> socks5 proxy on kharej`, and deleting it turns socks off rather than
  leaving a dangling mapping.

- `[t] Test the proxy` dials out through the proxy and prints the exit ip, from
  either side.

- `[5] Client settings` prints the host, port, user, password and a ready
  `socks5://user:pass@host:port` line to paste into an app.

- Health check reports the proxy service and its listening socket on KHAREJ,
  and the dashboard's LISTENING panel now includes the proxy's sockets.

### Changed

- **Pair code is now B3** and carries the socks port, public port, user and
  password, so pairing a KHAREJ server sets its proxy up in one step. Codes are
  emitted with an `ETN-` prefix. **B2 and B1 codes still parse**, and `DBH-`
  prefixed codes from Eris Tunnel 2 1.0.2 and DARK VPN Backhaul keep working.
- Every socks field arriving in a pair code is validated before use, and
  re-validated on each `meta.conf` load: user `A-Z a-z 0-9 _ -` (1-32), password
  `A-Z a-z 0-9 . _ + -` (6-64). `:` `@` `/` and every shell metacharacter are
  refused, so nothing hostile can reach the systemd unit or the proxy url.
  A tunnel whose socks fields do not survive validation is loaded with socks off
  instead of half-configured.
- Credentials live in a per-tunnel `socks.env` (mode 600) referenced by the unit
  as an `EnvironmentFile`, never inside the unit file itself.
- `gh_asset_url` was split so a release asset can be resolved for any
  repository, not just the Backhaul core.
- Tunnels created before this version gain the new `meta.conf` keys on first
  load, with socks off.
- `meta_set` replaces the scattered `sed -i` calls that edited `meta.conf`, and
  appends a key that is not there yet instead of silently doing nothing.

### Fixed

- Creating a KHAREJ tunnel could write a stale `TLS_CERT` / `TLS_KEY` path into
  its `meta.conf`, carried over from an IRAN tunnel visited earlier in the same
  session. Both are now cleared before the metadata is written.

### Removed / cleanup

- Uninstall now also removes `eris-socks@.service` and the downloaded gost
  binary.

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
