# Changelog

All notable changes to **Eris Tunnel 2** are recorded here.
This project follows [Semantic Versioning](https://semver.org/).

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
