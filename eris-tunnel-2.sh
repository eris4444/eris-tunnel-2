#!/usr/bin/env bash
# ==============================================================================
#  ERIS TUNNEL 2  ·  BACKHAUL
#  Manager for Backhaul reverse tunnels (github.com/Musixal/Backhaul)
#  Support: @erisrttg
#
#  ROLES - the one thing everyone gets backwards:
#    IRAN   = [server]  binds the port, exposes the user-facing ports
#    KHAREJ = [client]  dials out to Iran, holds the real service
#  So the pair code is generated on IRAN and pasted on KHAREJ.
#
#  SOCKS5 mode - the tunnel handed out as an outbound proxy:
#    app -> socks5 on IRAN:public_port -> tunnel -> 127.0.0.1:socks_port on
#    KHAREJ -> internet.  The exit ip a site sees is the KHAREJ one.  The
#    socks server itself runs on KHAREJ as eris-socks@<tunnel>, bound to
#    loopback so the tunnel is the only way in, and always with credentials.
#
#  ERIS-TUNNEL-2-SCRIPT
# ==============================================================================

SCRIPT_VER="1.5.1"
DEV_ID="@erisrttg"

GH_REPO="Musixal/Backhaul"
BASE_DIR="/etc/eris-tunnel-2"
TUN_DIR="$BASE_DIR/tunnels"
LOCAL_CORE_DIR="/root/backhaul"
BIN_PATH="/usr/local/bin/backhaul"
UNIT_FILE="/etc/systemd/system/backhaul@.service"
RS_UNIT="/etc/systemd/system/backhaul-restart@.service"
RS_TIMER="/etc/systemd/system/backhaul-restart@.timer"
CORE_VER_FILE="$BASE_DIR/core.version"
UPDATE_URL_FILE="$BASE_DIR/update.url"
SOCKS_UNIT="/etc/systemd/system/eris-socks@.service"
SOCKS_PROV_FILE="$BASE_DIR/socks.provider"
GOST_REPO="go-gost/gost"
GOST_BIN="/usr/local/bin/eris-gost"
DEFAULT_SOCKS_PORT=1080
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")"

# When started by an installer invoked as `curl ... | bash`, stdin is the curl
# pipe and reaches EOF immediately. Reattach stdin to the controlling terminal
# so every interactive read in the manager works normally.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
  exec </dev/tty
fi

DEFAULT_PORT="3080"
DEFAULT_TRANSPORT="tcpmux"
DEFAULT_POOL="8"
DEFAULT_CHANNEL="2048"
DEFAULT_MUXCON="8"

# ================================================================== UI ======
R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;221m'
C=$'\e[38;5;81m';  M=$'\e[38;5;177m'; W=$'\e[1;97m'
D=$'\e[38;5;244m'; N=$'\e[0m';        BD=$'\e[1m'
L1=$'\e[38;5;33m'; L2=$'\e[38;5;39m'; L3=$'\e[38;5;45m'
L4=$'\e[38;5;51m'; L5=$'\e[38;5;87m'; L6=$'\e[38;5;123m'
BG_OK=$'\e[48;5;22m'; BG_ERR=$'\e[48;5;52m'; BG_WARN=$'\e[48;5;58m'
UIW=62

shopt -s extglob 2>/dev/null
if ! locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then
  for L in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if locale -a 2>/dev/null | grep -qix "${L//./\\.}"; then export LC_ALL="$L"; break; fi
  done
fi
_probe='é'; [ ${#_probe} -eq 1 ] && UTF_OK=1 || UTF_OK=0

vislen() {
  local s="${1//$'\e['*([0-9;])m/}"
  if [ "$UTF_OK" = 1 ]; then printf '%s' "${#s}"; return; fi
  local b c
  b="$(LC_ALL=C; printf '%s' "$s" | wc -c)"
  c="$(printf '%s' "$s" | LC_ALL=C grep -o $'[\x80-\xbf]' 2>/dev/null | wc -l)"
  printf '%s' $(( b - c ))
}
rep() { local ch="$1" n="$2"; [ "${n:-0}" -gt 0 ] 2>/dev/null || return 0
        printf "${ch}%.0s" $(seq 1 "$n"); }
top()   { printf '  %s╭%s╮%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
mid()   { printf '  %s├%s┤%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
bot()   { printf '  %s╰%s╯%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
row()   { local t="$1" l p; l=$(vislen "$t"); p=$((UIW-l)); ((p<0))&&p=0
          printf '  %s│%s %s%*s %s│%s\n' "$C" "$N" "$t" "$p" "" "$C" "$N"; }
blank() { row ""; }
item()  { row "$(printf '%s%s%s  %s%-22s%s %s%s%s' "$Y" "[$1]" "$N" "$W" "$2" "$N" "$D" "${3:-}" "$N")"; }
kv()    { row "$(printf '%s%-13s%s %s' "$D" "$1" "$N" "$2")"; }
sect()  { row "$(printf '%s%s%s' "$M$BD" "$1" "$N")"; }
badge() { printf '%s %s %s' "$2$BD" "$1" "$N"; }

ok()   { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
bad()  { printf '  %sx%s %s\n' "$R" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
info() { printf '  %s>%s %s\n' "$C" "$N" "$*"; }
dim()  { printf '    %s%s%s\n' "$D" "$*" "$N"; }
dot()  { case "$1" in active) printf '%s*%s' "$G" "$N" ;; failed) printf '%s*%s' "$R" "$N" ;;
                     *) printf '%s*%s' "$D" "$N" ;; esac; }

ask() {
  local p="$1" d="${2:-}" v
  if [ -n "$d" ]; then read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" "$d" "$N")" v
  else read -r -p "$(printf '  %s>%s %s: ' "$C" "$N" "$p")" v; fi
  ANS="${v:-$d}"
}
yesno() {
  local p="$1" d="$2" v
  read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" \
      "$([ "$d" = y ] && echo 'Y/n' || echo 'y/N')" "$N")" v
  v="${v:-$d}"; [[ "$v" =~ ^[Yy]$ ]]
}
getkey() { local k; printf '  %s>%s Select: ' "$C" "$N"; read -rsn1 k
           [ -z "$k" ] && k="_"; printf '%s\n\n' "$k"; KEY="$k"; }
pause()  { printf '\n  %spress any key%s' "$D" "$N"; read -rsn1 _; echo; }

core_badge() {
  if [ -x "$BIN_PATH" ]; then badge "READY" "$BG_OK$W"; else badge "NO CORE" "$BG_ERR$W"; fi
}

header() {
  clear
  top
  row "$(printf '%s███████╗%s██████╗ %s██╗ %s███████╗%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s██╔════╝%s██╔══██╗%s██║ %s██╔════╝%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s█████╗  %s██████╔╝%s██║ %s███████╗%s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s██╔══╝  %s██╔══██╗%s██║ %s╚════██║%s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s███████╗%s██║  ██║%s██║ %s███████║%s' "$L3" "$L4" "$L5" "$L6" "$N")"
  row "$(printf '%s╚══════╝╚═╝  ╚═╝╚═╝ ╚══════╝%s' "$D" "$N")"
  row "$(printf '%sT%s U%s N%s N%s E%s L  2%s   %sbackhaul reverse tunnel%s' \
        "$L2" "$L3" "$L4" "$L5" "$L6" "$W$BD" "$N" "$D" "$N")"
  mid
  row "$(printf '%s %score %s%s   %sv%s%s   %s%s%s' \
        "$(core_badge)" "$D" "$N$W" "$(core_version_short)" "$D" "$SCRIPT_VER" "$N" "$M" "$DEV_ID" "$N")"
  bot
  [ -n "${1:-}" ] && { echo; printf '  %s>%s %s%s%s\n' "$L4" "$N" "$W$BD" "$1" "$N"; }
  echo
}

# ============================================================== HELPERS ====
need_root() { [ "$(id -u)" -eq 0 ] || { bad "run as root"; exit 1; }; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_name() { [[ "$1" =~ ^[a-zA-Z0-9_-]{1,24}$ ]]; }
valid_ip4()  {
  [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local o
  for o in "${BASH_REMATCH[@]:1:4}"; do
    [ "${#o}" -gt 1 ] && [ "${o:0:1}" = 0 ] && return 1
    [ "$o" -le 255 ] || return 1
  done
  return 0
}
valid_host() {
  valid_ip4 "$1" && return 0
  [ "${#1}" -le 253 ] || return 1
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]
}
# Anything that ends up inside meta.conf or a shell word must survive this.
valid_token() { [[ "$1" =~ ^[A-Za-z0-9+/=._@:-]{8,128}$ ]]; }
valid_ports_csv() { [[ "$1" =~ ^[0-9a-zA-Z.,:\>=_-]*$ ]] && [ "${#1}" -le 512 ]; }
# Socks credentials end up in a systemd EnvironmentFile and inside a
# socks5://user:pass@host:port url, so keep them clear of : / @ and anything
# a shell would look at twice.
valid_socks_user() { [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; }
valid_socks_pass() { [[ "$1" =~ ^[A-Za-z0-9._+-]{6,64}$ ]]; }
strip_ansi() { sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g' | tr -d '\033\r'; }
is_transport() { case "$1" in tcp|tcpmux|ws|wss|wsmux|wssmux|udp) return 0;; *) return 1;; esac; }
is_mux() { case "$1" in tcpmux|wsmux|wssmux) return 0;; *) return 1;; esac; }
is_tls() { case "$1" in wss|wssmux) return 0;; *) return 1;; esac; }
b64enc() { base64 -w0 2>/dev/null || base64 | tr -d '\n'; }
b64dec() { base64 -d 2>/dev/null; }

pkg_mgr() {
  command -v apt-get >/dev/null 2>&1 && { echo apt; return; }
  command -v dnf >/dev/null 2>&1 && { echo dnf; return; }
  command -v yum >/dev/null 2>&1 && { echo yum; return; }
  command -v apk >/dev/null 2>&1 && { echo apk; return; }
  echo none
}
install_deps() {
  local need=0 c
  for c in curl tar ss awk sed grep openssl; do
    command -v "$c" >/dev/null 2>&1 || need=1
  done
  [ "$need" -eq 0 ] && return 0
  info "installing dependencies"
  case "$(pkg_mgr)" in
    apt) apt-get update -qq >/dev/null 2>&1
         DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl tar iproute2 openssl ca-certificates >/dev/null 2>&1 ;;
    dnf) dnf install -y curl tar iproute openssl ca-certificates >/dev/null 2>&1 ;;
    yum) yum install -y curl tar iproute openssl ca-certificates >/dev/null 2>&1 ;;
    apk) apk add --no-cache bash curl tar iproute2 openssl ca-certificates >/dev/null 2>&1 ;;
  esac
}
arch_tag() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;; aarch64|arm64) echo arm64 ;;
    armv7l|armhf) echo arm ;; i386|i686) echo 386 ;; *) echo unsupported ;;
  esac
}
core_version_short() {
  if [ -x "$BIN_PATH" ]; then
    local v; v="$("$BIN_PATH" -v 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    [ -n "$v" ] && { echo "$v"; return; }
    [ -s "$CORE_VER_FILE" ] && { cat "$CORE_VER_FILE"; return; }
    echo installed
  else echo "not installed"; fi
}
show_sha256() {
  local h; h="$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"
  [ -n "$h" ] && dim "sha256: $h"
}
gen_token() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 24
  else tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 24; fi
}
gen_socks_user() { printf 'eris%s' "$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"; }
gen_socks_pass() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 18
  else tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 18; fi
}
local_ipv4s() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print $2" "a[1]}' | grep -v '^lo '
  else
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | awk '{print "host "$1}'
  fi
}
primary_ipv4() {
  local dev addr
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
    if [ -n "$dev" ]; then
      addr="$(ip -4 -o addr show dev "$dev" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')"
      [ -n "$addr" ] && { echo "$addr"; return; }
    fi
  fi
  local_ipv4s | awk '{print $2; exit}'
}

ip_is_local() { local_ipv4s | awk -v t="$1" '$2==t{f=1} END{exit !f}'; }

# Returns "<address> <source>". The address bound on this machine wins: on an
# Iranian server the outbound lookup is often filtered, and when it answers it
# frequently reports the address traffic *leaves* by, not the one users reach.
detect_server_addr() {
  local pub loc
  loc="$(primary_ipv4)"
  pub="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"
  valid_ip4 "$pub" || pub="$(curl -fsS4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')"
  if valid_ip4 "$loc"; then
    if valid_ip4 "$pub" && [ "$pub" != "$loc" ] && ! ip_is_local "$pub"; then echo "$loc nat:$pub"
    else echo "$loc interface"; fi
  elif valid_ip4 "$pub"; then echo "$pub outbound"
  else echo " none"; fi
}
public_ip() { local a s; read -r a s <<<"$(detect_server_addr)"; echo "$a"; }
port_in_use() { ss -tuln 2>/dev/null | grep -q ":${1} "; }
human_bytes() {
  local b="${1:-0}"
  if   [ "$b" -ge 1073741824 ] 2>/dev/null; then printf '%d.%01dG' $((b/1073741824)) $(( (b%1073741824)*10/1073741824 ))
  elif [ "$b" -ge 1048576 ]    2>/dev/null; then printf '%d.%01dM' $((b/1048576))    $(( (b%1048576)*10/1048576 ))
  elif [ "$b" -ge 1024 ]       2>/dev/null; then printf '%dK' $((b/1024))
  else printf '%sB' "${b:-0}"; fi
}

# =========================================================== CORE INSTALL ==
gh_latest_tag() {
  curl -fsSL --max-time 20 "https://api.github.com/repos/$GH_REPO/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}
gh_asset_url() { gh_asset_url_repo "$GH_REPO" "$1"; }
gh_asset_url_repo() {
  local repo="$1" arch="$2" json urls pick
  json="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)"
  [ -z "$json" ] && return 1
  urls="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' <<<"$json" \
        | sed -E 's/.*"(https[^"]+)"$/\1/' | grep -iE "linux[_-]${arch}" \
        | grep -viE '\.(sha256|asc|sig|txt|md5)$')"
  [ -z "$urls" ] && return 1
  pick="$(grep -iE '\.tar\.gz$|\.tgz$' <<<"$urls" | head -n1)"
  [ -z "$pick" ] && pick="$(head -n1 <<<"$urls")"
  printf '%s\n' "$pick"
}
place_core() {
  local src="$1" tmp bin had=0
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  case "$src" in
    *.tar.gz|*.tgz) tar -xzf "$src" -C "$tmp" 2>/dev/null || { bad "extract failed"; return 1; } ;;
    *.zip) command -v unzip >/dev/null 2>&1 || case "$(pkg_mgr)" in
             apt) apt-get install -y -qq unzip >/dev/null 2>&1 ;;
             apk) apk add --no-cache unzip >/dev/null 2>&1 ;;
             *) $(pkg_mgr) install -y unzip >/dev/null 2>&1 ;; esac
           unzip -oq "$src" -d "$tmp" 2>/dev/null || { bad "extract failed"; return 1; } ;;
    *) cp "$src" "$tmp/backhaul" ;;
  esac
  bin="$(find "$tmp" -type f -iname 'backhaul*' ! -name '*.tar.gz' ! -name '*.zip' \
        ! -name '*.toml' ! -name '*.md' 2>/dev/null | head -n1)"
  [ -z "$bin" ] && bin="$(find "$tmp" -maxdepth 3 -type f -size +1M 2>/dev/null | head -n1)"
  [ -z "$bin" ] && { bad "no binary inside the package"; return 1; }
  chmod +x "$bin"
  if ! "$bin" -v >/dev/null 2>&1; then
    bad "binary will not run here"
    "$bin" -v 2>&1 | head -n3 | sed 's/^/    /'
    return 1
  fi
  [ -x "$BIN_PATH" ] && { cp -f "$BIN_PATH" "$BIN_PATH.bak"; had=1; }
  install -m 0755 "$bin" "$BIN_PATH"
  if ! "$BIN_PATH" -v >/dev/null 2>&1; then
    bad "verification failed - rolling back"
    [ "$had" -eq 1 ] && mv -f "$BIN_PATH.bak" "$BIN_PATH"
    return 1
  fi
  return 0
}
screen_core() {
  header "CORE"
  local arch tag url
  arch="$(arch_tag)"
  [ "$arch" = unsupported ] && { bad "unsupported cpu: $(uname -m)"; pause; return; }
  mkdir -p "$LOCAL_CORE_DIR"
  top
  kv "installed" "$W$(core_version_short)$N"
  kv "arch"      "$W linux_$arch$N"
  mid
  item 1 "From GitHub" "latest release"
  item 2 "From $LOCAL_CORE_DIR" "offline"
  item 3 "From custom URL" ""
  item 0 "Back" ""
  bot; echo; getkey
  case "$KEY" in
    1) info "querying github"
       tag="$(gh_latest_tag)"
       url="$(gh_asset_url "$arch")"
       [ -z "$url" ] && { bad "no linux_$arch asset found - use option 2 or 3"; pause; return; }
       dim "release: ${tag:-?}"; dim "asset:   ${url##*/}"
       local dl; dl="$(mktemp -d)" || { bad "cannot create temp dir"; pause; return; }
       if ! curl -fL --retry 3 --max-time 240 -o "$dl/${url##*/}" "$url"; then
         bad "download failed"; rm -rf "$dl"; pause; return
       fi
       show_sha256 "$dl/${url##*/}"
       cp -f "$dl/${url##*/}" "$LOCAL_CORE_DIR/${url##*/}" 2>/dev/null
       if place_core "$dl/${url##*/}"; then
         echo "$tag" > "$CORE_VER_FILE"; ensure_units
         ok "installed: $(core_version_short)"; restart_all_prompt
       fi
       rm -rf "$dl" ;;
    2) local files=() f i=1
       while IFS= read -r f; do files+=("$f"); done < <(find "$LOCAL_CORE_DIR" -maxdepth 1 -type f \
            \( -name '*.tar.gz' -o -name '*.zip' -o -name 'backhaul*' \) 2>/dev/null | sort)
       if [ ${#files[@]} -eq 0 ]; then
         bad "nothing in $LOCAL_CORE_DIR"; pause; return
       fi
       echo; top; sect "LOCAL FILES"; blank
       for f in "${files[@]}"; do row "$(printf '%s[%d]%s %s' "$Y" "$i" "$N" "$(basename "$f")")"; i=$((i+1)); done
       bot; echo; getkey
       [[ "$KEY" =~ ^[0-9]+$ ]] && [ "$KEY" -ge 1 ] && [ "$KEY" -le ${#files[@]} ] || return
       if place_core "${files[$((KEY-1))]}"; then
         echo local > "$CORE_VER_FILE"; ensure_units
         ok "installed: $(core_version_short)"; restart_all_prompt
       fi ;;
    3) ask "direct url"; [ -z "$ANS" ] && return
       case "$ANS" in https://*) ;; *) bad "https urls only"; pause; return ;; esac
       local dl3; dl3="$(mktemp -d)" || { bad "cannot create temp dir"; pause; return; }
       if ! curl -fL --retry 3 --max-time 240 -o "$dl3/core.pkg" "$ANS"; then
         bad "download failed"; rm -rf "$dl3"; pause; return
       fi
       show_sha256 "$dl3/core.pkg"
       warn "this binary is not from the official release page"
       if ! yesno "install it anyway?" n; then rm -rf "$dl3"; info "cancelled"; pause; return; fi
       if place_core "$dl3/core.pkg"; then
         echo custom > "$CORE_VER_FILE"; ensure_units
         ok "installed: $(core_version_short)"; restart_all_prompt
       fi
       rm -rf "$dl3" ;;
    *) return ;;
  esac
  echo; warn "the core should be the same version on both servers"
  pause
}
restart_all_prompt() {
  local l t; l="$(tunnel_names)"; [ -z "$l" ] && return
  yesno "restart all tunnels now?" y || return
  for t in $l; do systemctl restart "backhaul@$t" 2>/dev/null && ok "$t" || bad "$t"; done
}

# ================================================================ SYSTEMD ==
ensure_dirs() { mkdir -p "$BASE_DIR" "$TUN_DIR" "$LOCAL_CORE_DIR" "$BASE_DIR/certs"; chmod 700 "$BASE_DIR"; }
ensure_units() {
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Eris Tunnel 2 - Backhaul Tunnel (%i)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$BIN_PATH -c $TUN_DIR/%i/config.toml
Restart=always
# without these a stop waits the default 90s, which looks like a freeze
TimeoutStopSec=10
KillMode=mixed
KillSignal=SIGTERM
SendSIGKILL=yes
RestartSec=5
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=backhaul-%i

[Install]
WantedBy=multi-user.target
EOF
  cat > "$RS_UNIT" <<EOF
[Unit]
Description=Eris Tunnel 2 - scheduled restart (%i)

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart backhaul@%i.service
EOF
  cat > "$RS_TIMER" <<'EOF'
[Unit]
Description=Eris Tunnel 2 - scheduled restart timer (%i)

[Timer]
OnUnitActiveSec=1h
OnBootSec=1h
AccuracySec=1min
Unit=backhaul-restart@%i.service

[Install]
WantedBy=timers.target
EOF
  socks_provider_read >/dev/null 2>&1 && socks_write_unit >/dev/null 2>&1
  systemctl daemon-reload 2>/dev/null
}
# =========================================================== SOCKS5 PROXY ==
# The proxy itself is not ours: whichever small socks5 server the host can get
# hold of is wrapped in eris-socks@<tunnel>.  microsocks first, since a distro
# package needs no download and gets security updates; gost as the fallback,
# because plenty of still-supported releases do not carry microsocks.
gost_arch() {
  case "$(arch_tag)" in
    amd64) echo amd64 ;; arm64) echo arm64 ;; arm) echo armv7 ;; 386) echo 386 ;;
    *) echo unsupported ;;
  esac
}
socks_provider_write() { printf '%s\t%s\n' "$1" "$2" > "$SOCKS_PROV_FILE"; chmod 600 "$SOCKS_PROV_FILE"; }
socks_provider_read() { # -> SOCKS_KIND, SOCKS_BIN
  SOCKS_KIND=""; SOCKS_BIN=""
  [ -s "$SOCKS_PROV_FILE" ] || return 1
  IFS=$'\t' read -r SOCKS_KIND SOCKS_BIN < "$SOCKS_PROV_FILE"
  case "$SOCKS_KIND" in microsocks|gost) ;; *) SOCKS_KIND=""; SOCKS_BIN=""; return 1 ;; esac
  [ -x "$SOCKS_BIN" ] || { SOCKS_KIND=""; SOCKS_BIN=""; return 1; }
  return 0
}
socks_provider_name() {
  socks_provider_read || { echo "none"; return; }
  echo "$SOCKS_KIND"
}
socks_install_microsocks() {
  local p
  p="$(command -v microsocks 2>/dev/null)"
  [ -n "$p" ] && { socks_provider_write microsocks "$p"; return 0; }
  case "$(pkg_mgr)" in
    apt) apt-get update -qq >/dev/null 2>&1
         DEBIAN_FRONTEND=noninteractive apt-get install -y -qq microsocks >/dev/null 2>&1 ;;
    dnf) dnf install -y -q microsocks >/dev/null 2>&1 ;;
    yum) yum install -y -q microsocks >/dev/null 2>&1 ;;
    apk) apk add --no-cache microsocks >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
  p="$(command -v microsocks 2>/dev/null)"
  [ -n "$p" ] || return 1
  socks_provider_write microsocks "$p"
}
socks_install_gost() {
  local a url tmp d bin
  a="$(gost_arch)"
  [ "$a" = unsupported ] && { bad "unsupported architecture for gost"; return 1; }
  info "looking for a gost release for linux/$a"
  url="$(gh_asset_url_repo "$GOST_REPO" "$a")" || { bad "no matching gost asset - check connectivity to github"; return 1; }
  dim "${url##*/}"
  tmp="$(mktemp)" || return 1
  if ! curl -fsSL --retry 3 --max-time 120 -o "$tmp" "$url"; then
    bad "download failed"; rm -f "$tmp"; return 1
  fi
  show_sha256 "$tmp"
  d="$(mktemp -d)" || { rm -f "$tmp"; return 1; }
  case "$url" in
    *.tar.gz|*.tgz) tar -xzf "$tmp" -C "$d" 2>/dev/null ;;
    *.zip) command -v unzip >/dev/null 2>&1 || case "$(pkg_mgr)" in
             apt) apt-get install -y -qq unzip >/dev/null 2>&1 ;;
             apk) apk add --no-cache unzip >/dev/null 2>&1 ;;
             none) : ;;
             *) $(pkg_mgr) install -y unzip >/dev/null 2>&1 ;; esac
           unzip -oq "$tmp" -d "$d" 2>/dev/null ;;
    *) cp "$tmp" "$d/gost" ;;
  esac
  rm -f "$tmp"
  bin="$(find "$d" -type f -iname 'gost*' ! -iname '*.md' ! -iname '*.json' ! -iname '*.yml' 2>/dev/null | head -n1)"
  [ -z "$bin" ] && bin="$(find "$d" -maxdepth 3 -type f -size +1M 2>/dev/null | head -n1)"
  [ -z "$bin" ] && { bad "no binary inside the gost package"; rm -rf "$d"; return 1; }
  chmod +x "$bin"
  install -m 0755 "$bin" "$GOST_BIN"; rm -rf "$d"
  if ! "$GOST_BIN" -V >/dev/null 2>&1 && ! "$GOST_BIN" -h >/dev/null 2>&1; then
    bad "gost will not run here"; rm -f "$GOST_BIN"; return 1
  fi
  socks_provider_write gost "$GOST_BIN"
}
socks_ensure_provider() {
  socks_provider_read && return 0
  info "installing a local socks5 server"
  socks_install_microsocks && socks_provider_read && { ok "provider: microsocks"; socks_write_unit; return 0; }
  warn "microsocks is not in this system's repositories - trying gost"
  socks_install_gost && socks_provider_read && { ok "provider: gost"; socks_write_unit; return 0; }
  bad "could not install a socks5 server"
  dim "install microsocks or gost by hand, then enable socks again"
  return 1
}
# ExecStart is written with systemd's own ${VAR} form so the credentials live
# in the per-tunnel EnvironmentFile (mode 600) and never in the unit itself.
socks_exec_line() {
  case "$1" in
    microsocks) printf '%s -i ${SOCKS_BIND} -p ${SOCKS_PORT} -u ${SOCKS_USER} -P ${SOCKS_PASS}' "$2" ;;
    gost)       printf '%s -L socks5://${SOCKS_USER}:${SOCKS_PASS}@${SOCKS_BIND}:${SOCKS_PORT}' "$2" ;;
  esac
}
socks_write_unit() {
  socks_provider_read || return 1
  local ex; ex="$(socks_exec_line "$SOCKS_KIND" "$SOCKS_BIN")"
  [ -n "$ex" ] || return 1
  cat > "$SOCKS_UNIT" <<EOF
[Unit]
Description=Eris Tunnel 2 - local SOCKS5 proxy (%i)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
EnvironmentFile=$TUN_DIR/%i/socks.env
ExecStart=$ex
Restart=always
RestartSec=3
TimeoutStopSec=10
KillMode=mixed
KillSignal=SIGTERM
SendSIGKILL=yes
LimitNOFILE=1048576
NoNewPrivileges=yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=eris-socks-%i

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload 2>/dev/null
  return 0
}
socks_env_write() { # <name>  (uses SOCKS_PORT / SOCKS_USER / SOCKS_PASS)
  local d="$TUN_DIR/$1"
  [ -d "$d" ] || return 1
  cat > "$d/socks.env" <<EOF
SOCKS_BIND=127.0.0.1
SOCKS_PORT=$SOCKS_PORT
SOCKS_USER=$SOCKS_USER
SOCKS_PASS=$SOCKS_PASS
EOF
  chmod 600 "$d/socks.env"
}
socks_raw()  { systemctl is-active "eris-socks@$1" 2>/dev/null; }
socks_down() {
  systemctl disable --now "eris-socks@$1" >/dev/null 2>&1
  systemctl reset-failed "eris-socks@$1" >/dev/null 2>&1
  return 0
}
socks_up() { # <name>
  systemctl enable "eris-socks@$1" >/dev/null 2>&1
  systemctl restart "eris-socks@$1" >/dev/null 2>&1
  sleep 1
  [ "$(socks_raw "$1")" = active ]
}
socks_uri() { printf 'socks5://%s:%s@%s:%s' "$3" "$4" "$1" "$2"; }
socks_test() { # <host> <port> <user> <pass>
  command -v curl >/dev/null 2>&1 || { bad "curl is not installed"; return 1; }
  info "asking api.ipify.org which ip it sees through the proxy"
  local out
  out="$(curl -fsS --max-time 25 -x "socks5h://$3:$4@$1:$2" https://api.ipify.org 2>&1)"
  if [[ "$out" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ok "working - exit ip is $out"; return 0
  fi
  bad "the proxy did not answer"
  [ -n "$out" ] && printf '%s' "$out" | head -n2 | sed 's/^/    /'
  return 1
}
# The socks row inside ports.list is an ordinary mapped port, kept in sync from
# whatever SOCKS_PUB_PORT / SOCKS_PORT currently say.
socks_row_clear() { # <dir> <pub_port>
  [ -n "$2" ] || return 0
  [ -f "$1/ports.list" ] || return 0
  awk -F'\t' -v p="$2" '$1!=p' "$1/ports.list" > "$1/ports.tmp" 2>/dev/null \
    && mv -f "$1/ports.tmp" "$1/ports.list"
  return 0
}
socks_row_set() { # <dir> <pub_port> <socks_port>
  socks_row_clear "$1" "$2"
  printf '%s\t127.0.0.1:%s\n' "$2" "$3" >> "$1/ports.list"
}
socks_row_present() { # <dir> <pub_port>
  [ -n "$2" ] || return 1
  awk -F'\t' -v p="$2" '$1==p{f=1} END{exit !f}' "$1/ports.list" 2>/dev/null
}

set_restart_timer() {
  local name="$1" every="$2" dir; dir="/etc/systemd/system/backhaul-restart@$name.timer.d"
  if [ "$every" = off ]; then
    systemctl disable --now "backhaul-restart@$name.timer" >/dev/null 2>&1
    rm -rf "$dir"; systemctl daemon-reload 2>/dev/null; return 0
  fi
  mkdir -p "$dir"
  printf '[Timer]\nOnUnitActiveSec=\nOnUnitActiveSec=%s\nOnBootSec=\nOnBootSec=%s\n' "$every" "$every" > "$dir/interval.conf"
  systemctl daemon-reload 2>/dev/null
  systemctl enable --now "backhaul-restart@$name.timer" >/dev/null 2>&1
}


# ============================================================== PROFILES ====
# Backhaul ships conservative defaults that behave poorly on a lossy Iran path.
# These are the knobs that actually move the needle, grouped into four presets.
# Every value here is a real field from the upstream config - nothing invented.
profile_apply() { # <profile> ; sets P_*
  local p="$1"
  # --- mux framing is NEGOTIATED, so it must be identical on both servers.
  # Keeping it out of the profiles removes a whole class of failure where one
  # side is Turbo and the other Balanced: the control channel comes up and the
  # client then closes it because the mux handshake does not agree.
  # framesize also has a hard ceiling: smux carries the length in 16 bits.
  P_FRAME=32768; P_RECVBUF=4194304; P_STREAMBUF=65536; P_MUXVER=1
  # --- everything below is per-side and safe to differ
  case "$p" in
    stable)
      P_POOL=4;  P_CHANNEL=1024; P_HEARTBEAT=30; P_KEEPALIVE=20; P_MUXCON=4
      P_AGGRESSIVE=false; P_RETRY=3; P_DIAL=10; P_NODELAY=true ;;
    balanced)
      P_POOL=8;  P_CHANNEL=2048; P_HEARTBEAT=40; P_KEEPALIVE=75; P_MUXCON=8
      P_AGGRESSIVE=false; P_RETRY=3; P_DIAL=10; P_NODELAY=true ;;
    lowping)
      P_POOL=16; P_CHANNEL=2048; P_HEARTBEAT=20; P_KEEPALIVE=20; P_MUXCON=8
      P_AGGRESSIVE=true;  P_RETRY=1; P_DIAL=5;  P_NODELAY=true ;;
    turbo)
      P_POOL=24; P_CHANNEL=4096; P_HEARTBEAT=40; P_KEEPALIVE=60; P_MUXCON=16
      P_AGGRESSIVE=true;  P_RETRY=2; P_DIAL=10; P_NODELAY=true ;;
    *) profile_apply balanced ;;
  esac
}

valid_profile() { case "$1" in stable|balanced|lowping|turbo) return 0;; *) return 1;; esac; }
profile_name() { case "$1" in
  stable) echo "Stable" ;; balanced) echo "Balanced" ;;
  lowping) echo "Low Ping" ;; turbo) echo "Turbo" ;; *) echo "$1" ;; esac; }
profile_hint() { case "$1" in
  stable)   echo "small pool - for lossy paths" ;;
  balanced) echo "upstream defaults - safe start" ;;
  lowping)  echo "small frames - lowest latency" ;;
  turbo)    echo "big pool + buffers - many users" ;; esac; }

pick_profile() {
  { echo; top; sect "PERFORMANCE PROFILE"
    row "$(printf '%schanges pool, channel size, heartbeat and keepalive%s' "$D" "$N")"
    row "$(printf '%smux framing stays identical, so sides may differ%s' "$D" "$N")"; blank
    item 1 "Stable"   "$(profile_hint stable)"
    item 2 "Balanced" "$(profile_hint balanced)"
    item 3 "Low Ping" "$(profile_hint lowping)"
    item 4 "Turbo"    "$(profile_hint turbo)"
    bot; echo; } >&2
  local k; printf '  %s>%s Profile [2]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 1) echo stable ;; 3) echo lowping ;; 4) echo turbo ;; *) echo balanced ;; esac
}

# ================================================================ PICKERS ==
transport_hint() {
  case "$1" in
    tcp)    echo "simplest, no multiplexing" ;;
    tcpmux) echo "recommended - many users" ;;
    ws)     echo "http, works behind cdn" ;;
    wss)    echo "https, needs a cert" ;;
    wsmux)  echo "http + multiplexing" ;;
    wssmux) echo "https + mux - best dpi resistance" ;;
    udp)    echo "for hysteria / tuic only" ;;
  esac
}
pick_transport() {
  { echo; top; sect "TRANSPORT"
    row "$(printf '%smust be identical on both servers%s' "$D" "$N")"; blank
    item 1 "tcp"    "$(transport_hint tcp)"
    item 2 "tcpmux" "$(transport_hint tcpmux)"
    item 3 "ws"     "$(transport_hint ws)"
    item 4 "wsmux"  "$(transport_hint wsmux)"
    item 5 "wss"    "$(transport_hint wss)"
    item 6 "wssmux" "$(transport_hint wssmux)"
    item 7 "udp"    "$(transport_hint udp)"
    bot; echo; } >&2
  local k; printf '  %s>%s Transport [2]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 1) echo tcp ;; 3) echo ws ;; 4) echo wsmux ;; 5) echo wss ;; 6) echo wssmux ;; 7) echo udp ;; *) echo tcpmux ;; esac
}
pick_restart() {
  { echo; top; sect "SCHEDULED RESTART"
    row "$(printf '%sclears a degraded tunnel on a fixed interval%s' "$D" "$N")"; blank
    item 1 "off" ""
    item 2 "1h"  "recommended"
    item 3 "6h"  ""
    item 4 "12h" ""
    item 5 "24h" ""
    bot; echo; } >&2
  local k; printf '  %s>%s Restart every [1]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 2) echo 1h ;; 3) echo 6h ;; 4) echo 12h ;; 5) echo 24h ;; *) echo off ;; esac
}
cert_cn() {
  openssl x509 -in "$1" -noout -subject 2>/dev/null \
    | sed -nE 's/.*CN[[:space:]]*=[[:space:]]*([^,/]+).*/\1/p' | head -n1
}
cert_expiry() {
  local d; d="$(openssl x509 -in "$1" -noout -enddate 2>/dev/null | cut -d= -f2)"
  [ -z "$d" ] && { echo "?"; return; }
  date -d "$d" '+%Y-%m-%d' 2>/dev/null || echo "$d"
}
cert_days_left() {
  local d n e
  e="$(openssl x509 -in "$1" -noout -enddate 2>/dev/null | cut -d= -f2)"
  [ -z "$e" ] && { echo -1; return; }
  d="$(date -d "$e" +%s 2>/dev/null)" || { echo -1; return; }
  n="$(date +%s)"; echo $(( (d - n) / 86400 ))
}
cert_pair_matches() {
  local c k a b
  a="$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null | openssl md5 2>/dev/null)"
  b="$(openssl pkey -in "$2" -pubout 2>/dev/null | openssl md5 2>/dev/null)"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# Fills CERT_PATHS / CERT_KEYS / CERT_NAMES with every usable pair found.
scan_certs() {
  CERT_PATHS=(); CERT_KEYS=(); CERT_NAMES=()
  local c k cn d
  # certbot
  for d in /etc/letsencrypt/live/*/; do
    [ -d "$d" ] || continue
    c="$d/fullchain.pem"; k="$d/privkey.pem"
    [ -s "$c" ] && [ -s "$k" ] || continue
    CERT_PATHS+=("$c"); CERT_KEYS+=("$k"); CERT_NAMES+=("$(basename "${d%/}")")
  done
  # acme.sh
  for d in /root/.acme.sh/*/ "$HOME"/.acme.sh/*/; do
    [ -d "$d" ] || continue
    cn="$(basename "${d%/}")"; cn="${cn%_ecc}"
    c="$d/fullchain.cer"; k="$d/$cn.key"
    [ -s "$c" ] && [ -s "$k" ] || continue
    CERT_PATHS+=("$c"); CERT_KEYS+=("$k"); CERT_NAMES+=("$cn")
  done
  # x-ui / hiddify style drops
  for d in /root/cert/*/ /root/cert /etc/ssl/panel/*/; do
    [ -d "$d" ] || continue
    for c in "$d"/fullchain.pem "$d"/fullchain.crt "$d"/cert.crt "$d"/*.crt "$d"/*.pem; do
      [ -s "$c" ] || continue
      case "$c" in *privkey*|*.key) continue ;; esac
      k=""
      for cand in "${c%.*}.key" "$d/privkey.pem" "$d/private.key" "$d/private.pem"; do
        [ -s "$cand" ] && { k="$cand"; break; }
      done
      [ -n "$k" ] || continue
      cn="$(cert_cn "$c")"; [ -z "$cn" ] && cn="$(basename "${d%/}")"
      CERT_PATHS+=("$c"); CERT_KEYS+=("$k"); CERT_NAMES+=("$cn")
      break
    done
  done
  # de-duplicate by certificate path
  local i j keepP=() keepK=() keepN=() dup
  for i in "${!CERT_PATHS[@]}"; do
    dup=0
    for j in "${!keepP[@]}"; do [ "${keepP[$j]}" = "${CERT_PATHS[$i]}" ] && dup=1; done
    [ "$dup" -eq 1 ] && continue
    cert_pair_matches "${CERT_PATHS[$i]}" "${CERT_KEYS[$i]}" || continue
    keepP+=("${CERT_PATHS[$i]}"); keepK+=("${CERT_KEYS[$i]}"); keepN+=("${CERT_NAMES[$i]}")
  done
  CERT_PATHS=("${keepP[@]}"); CERT_KEYS=("${keepK[@]}"); CERT_NAMES=("${keepN[@]}")
  return 0
}

make_self_signed() {
  local dir="$1"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$dir/server.key" -out "$dir/server.crt" \
    -subj "/CN=$(hostname -f 2>/dev/null || echo localhost)" >/dev/null 2>&1 || return 1
  chmod 600 "$dir/server.key"
  TLS_CERT="$dir/server.crt"; TLS_KEY="$dir/server.key"
  return 0
}

# ---------------------------------------------------------- ISSUING CERTS --
# acme.sh in standalone mode: no webserver needed, no python, and it installs
# its own renewal cron. The two things that actually make issuance fail are a
# domain that does not point here and a busy port 80, so both are checked
# before anything is attempted.
CERT_STORE="$BASE_DIR/certs"

acme_bin() { echo "${HOME:-/root}/.acme.sh/acme.sh"; }

ensure_acme() {
  [ -x "$(acme_bin)" ] && return 0
  info "installing acme.sh (one time)"
  curl -fsSL https://get.acme.sh 2>/dev/null | sh -s email="admin@$1" >/dev/null 2>&1
  [ -x "$(acme_bin)" ] && { ok "acme.sh installed"; return 0; }
  bad "could not install acme.sh - check outbound https"
  return 1
}

domain_resolves_here() { # <domain> -> 0 match, 1 mismatch, 2 unknown
  local d="$1" want got
  want="$(primary_ipv4 2>/dev/null)"
  [ -n "$want" ] || want="$(hostname -I 2>/dev/null | awk '{print $1}')"
  got="$(getent ahostsv4 "$d" 2>/dev/null | awk 'NF{print $1}' | sort -u | tr '\n' ' ')"
  got="${got%"${got##*[![:space:]]}"}"     # trim, or an empty result reads as found
  [ -n "$got" ] || return 2
  DOMAIN_RESOLVED="$got"
  grep -qw "$want" <<<"$got" && return 0
  # the box may be behind NAT - accept a match against the public address too
  local pub; pub="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"
  [ -n "$pub" ] && grep -qw "$pub" <<<"$got" && return 0
  return 1
}

port80_free() { ! ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -Eq '[:.]80$'; }
port80_user() { ss -ltnp 2>/dev/null | awk 'NR>1 && $4 ~ /[:.]80$/' | grep -oP 'users:\(\("\K[^"]+' | head -n1; }

# Sets TLS_CERT / TLS_KEY on success.
issue_cert() { # <reload-service-or-empty>
  local reload="${1:-}" d out rc
  ask "domain for the certificate"; d="$ANS"
  valid_host "$d" || { bad "invalid domain"; return 1; }
  case "$d" in *.*) ;; *) bad "use a full domain, e.g. tunnel.example.com"; return 1 ;; esac

  info "checking that $d points to this server"
  domain_resolves_here "$d"; rc=$?
  case "$rc" in
    0) ok "$d resolves here (${DOMAIN_RESOLVED% })" ;;
    2) warn "$d does not resolve at all - the A record is missing"
       yesno "try anyway?" n || return 1 ;;
    1) warn "$d resolves to ${DOMAIN_RESOLVED% } which is not this server"
       dim "issuance will fail unless the A record points here"
       yesno "try anyway?" n || return 1 ;;
  esac

  if ! port80_free; then
    local who; who="$(port80_user)"
    bad "port 80 is busy${who:+ (used by $who)}"
    dim "acme.sh needs port 80 free for the http-01 check"
    yesno "stop that service yourself and retry now?" n || return 1
    port80_free || { bad "port 80 still busy"; return 1; }
  fi

  ensure_acme "$d" || return 1
  out="$CERT_STORE/$d"; mkdir -p "$out"; chmod 700 "$CERT_STORE"

  local _acme_log; _acme_log="$(mktemp)" || return 1
  info "requesting a certificate from Let's Encrypt"
  if ! "$(acme_bin)" --issue -d "$d" --standalone --server letsencrypt \
        --keylength ec-256 >"$_acme_log" 2>&1; then
    bad "issuance failed"
    tail -n 8 "$_acme_log" | sed 's/^/    /'
    rm -f "$_acme_log"
    return 1
  fi
  rm -f "$_acme_log"

  local reloadcmd=""
  [ -n "$reload" ] && reloadcmd="systemctl restart $reload"
  if ! "$(acme_bin)" --install-cert -d "$d" --ecc \
        --fullchain-file "$out/fullchain.pem" \
        --key-file "$out/privkey.pem" \
        ${reloadcmd:+--reloadcmd "$reloadcmd"} >/dev/null 2>&1; then
    bad "certificate issued but could not be installed to $out"
    return 1
  fi
  chmod 600 "$out/privkey.pem" 2>/dev/null
  TLS_CERT="$out/fullchain.pem"; TLS_KEY="$out/privkey.pem"
  ok "certificate ready for $d - renews automatically"
  dim "stored in $out"
  return 0
}

# Sets TLS_CERT and TLS_KEY. Returns 1 if the operator backed out.
choose_cert() {
  local dir="$1" i n days
  TLS_CERT=""; TLS_KEY=""
  scan_certs
  echo; top; sect "CERTIFICATE"
  row "$(printf '%swss / wssmux need a cert on the IRAN server%s' "$D" "$N")"; blank
  if [ "${#CERT_PATHS[@]}" -gt 0 ]; then
    row "$(printf '%sfound on this server:%s' "$D" "$N")"
    for i in "${!CERT_PATHS[@]}"; do
      days="$(cert_days_left "${CERT_PATHS[$i]}")"
      n=$((i+1))
      if [ "$days" -lt 0 ] 2>/dev/null; then
        row "$(printf '%s[%d]%s %-26s %sEXPIRED%s' "$Y" "$n" "$N" "${CERT_NAMES[$i]:0:26}" "$R" "$N")"
      elif [ "$days" -lt 15 ]; then
        row "$(printf '%s[%d]%s %-26s %s%sd left%s' "$Y" "$n" "$N" "${CERT_NAMES[$i]:0:26}" "$Y" "$days" "$N")"
      else
        row "$(printf '%s[%d]%s %-26s %s%sd left%s' "$Y" "$n" "$N" "${CERT_NAMES[$i]:0:26}" "$G" "$days" "$N")"
      fi
    done
  else
    row "$(printf '%sno issued certificate found on this server%s' "$D" "$N")"
  fi
  blank
  item i "Get a certificate" "issue one for a domain now"
  item s "Self-signed" "no domain needed"
  item m "Enter paths manually" ""
  item 0 "Back" ""
  bot; echo; getkey
  case "$KEY" in
    i|I) issue_cert "" && return 0; return 1 ;;
    s|S) make_self_signed "$dir" && { ok "self-signed certificate created"; return 0; }
         bad "openssl failed"; return 1 ;;
    m|M) ask "certificate file"; TLS_CERT="$ANS"
         ask "private key file";  TLS_KEY="$ANS"
         [ -s "$TLS_CERT" ] && [ -s "$TLS_KEY" ] || { bad "file not found"; return 1; }
         cert_pair_matches "$TLS_CERT" "$TLS_KEY" || { bad "cert and key do not match"; return 1; }
         ok "using $TLS_CERT"; return 0 ;;
    0|_) return 1 ;;
    *)   if [[ "$KEY" =~ ^[0-9]+$ ]] && [ "$KEY" -ge 1 ] && [ "$KEY" -le "${#CERT_PATHS[@]}" ]; then
           i=$((KEY-1))
           TLS_CERT="${CERT_PATHS[$i]}"; TLS_KEY="${CERT_KEYS[$i]}"
           days="$(cert_days_left "$TLS_CERT")"
           [ "$days" -lt 0 ] 2>/dev/null && warn "this certificate is expired - clients will reject it"
           ok "using ${CERT_NAMES[$i]}"
           return 0
         fi
         bad "invalid choice"; return 1 ;;
  esac
}

# ====================================================== CONFIG GENERATION ==
mux_lines() {
  cat <<EOF
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
EOF
}

# IRAN side. This is where the user-facing ports live.
write_server_config() {
  local dir="$1" lport target
  tune_effective
  {
    echo "# Eris Tunnel 2 | IRAN (server) | $DEV_ID"
    echo "# $(date '+%F %T') | profile: ${PROFILE:-balanced}"
    echo "[server]"
    echo "bind_addr = \"0.0.0.0:$PORT\""
    echo "transport = \"$TRANSPORT\""
    [ "$TRANSPORT" != udp ] && echo "accept_udp = $ACCEPT_UDP"
    echo "token = \"$TOKEN\""
    echo "keepalive_period = $P_KEEPALIVE"
    echo "nodelay = $P_NODELAY"
    echo "heartbeat = $P_HEARTBEAT"
    echo "channel_size = $P_CHANNEL"
    if is_mux "$TRANSPORT"; then
      echo "mux_con = $P_MUXCON"
      echo "mux_version = $P_MUXVER"
      echo "mux_framesize = $P_FRAME"
      echo "mux_recievebuffer = $P_RECVBUF"
      echo "mux_streambuffer = $P_STREAMBUF"
    fi
    if is_tls "$TRANSPORT"; then
      echo "tls_cert = \"${TLS_CERT:-$dir/server.crt}\""
      echo "tls_key = \"${TLS_KEY:-$dir/server.key}\""
    fi
    echo "sniffer = $SNIFFER"
    echo "web_port = $WEB_PORT"
    echo "sniffer_log = \"$dir/sniffer.json\""
    echo "log_level = \"$LOGLEVEL\""
    echo "ports = ["
    while IFS=$'\t' read -r lport target; do
      [ -z "$lport" ] && continue
      if [ -n "$target" ] && [ "$target" != "-" ]; then echo "  \"$lport=$target\","
      else echo "  \"$lport\","; fi
    done < "$dir/ports.list"
    echo "]"
  } > "$dir/config.toml"
  chmod 600 "$dir/config.toml"
}

# KHAREJ side. Dials out to Iran; no inbound port needed here.
write_client_config() {
  local dir="$1"
  tune_effective
  {
    echo "# Eris Tunnel 2 | KHAREJ (client) | $DEV_ID"
    echo "# $(date '+%F %T') | profile: ${PROFILE:-balanced}"
    echo "[client]"
    echo "remote_addr = \"$PEER_IP:$PORT\""
    [ -n "$EDGE_IP" ] && echo "edge_ip = \"$EDGE_IP\""
    echo "transport = \"$TRANSPORT\""
    echo "token = \"$TOKEN\""
    echo "connection_pool = $P_POOL"
    echo "aggressive_pool = $P_AGGRESSIVE"
    echo "keepalive_period = $P_KEEPALIVE"
    echo "dial_timeout = $P_DIAL"
    echo "retry_interval = $P_RETRY"
    echo "nodelay = $P_NODELAY"
    if is_mux "$TRANSPORT"; then
      echo "mux_version = $P_MUXVER"
      echo "mux_framesize = $P_FRAME"
      echo "mux_recievebuffer = $P_RECVBUF"
      echo "mux_streambuffer = $P_STREAMBUF"
    fi
    echo "sniffer = $SNIFFER"
    echo "web_port = $WEB_PORT"
    echo "sniffer_log = \"$dir/sniffer.json\""
    echo "log_level = \"$LOGLEVEL\""
  } > "$dir/config.toml"
  chmod 600 "$dir/config.toml"
}

config_sane() {
  local f="$1"
  [ -s "$f" ] || return 1
  grep -q $'\033' "$f" && return 1
  grep -qE '^\[(server|client)\]$' "$f" || return 1
  grep -qE '^(bind_addr|remote_addr) = ".+"$' "$f" || return 1
  return 0
}

write_meta() {
  cat > "$1/meta.conf" <<EOF
NAME="$NAME"
ROLE="$ROLE"
PORT="$PORT"
TOKEN="$TOKEN"
TRANSPORT="$TRANSPORT"
PROFILE="$PROFILE"
OV_POOL="${OV_POOL:-}"
OV_CHANNEL="${OV_CHANNEL:-}"
OV_HEARTBEAT="${OV_HEARTBEAT:-}"
OV_KEEPALIVE="${OV_KEEPALIVE:-}"
OV_MUXCON="${OV_MUXCON:-}"
OV_AGGRESSIVE="${OV_AGGRESSIVE:-}"
OV_RETRY="${OV_RETRY:-}"
OV_DIAL="${OV_DIAL:-}"
OV_NODELAY="${OV_NODELAY:-}"
OV_FRAME="${OV_FRAME:-}"
OV_RECVBUF="${OV_RECVBUF:-}"
OV_STREAMBUF="${OV_STREAMBUF:-}"
OV_MUXVER="${OV_MUXVER:-}"
AGGRESSIVE="$AGGRESSIVE"
ACCEPT_UDP="$ACCEPT_UDP"
NODELAY="$NODELAY"
SNIFFER="$SNIFFER"
WEB_PORT="$WEB_PORT"
EDGE_IP="$EDGE_IP"
TLS_CERT="$TLS_CERT"
TLS_KEY="$TLS_KEY"
PEER_IP="$PEER_IP"
PUB_IP="$PUB_IP"
SOCKS_ENABLE="${SOCKS_ENABLE:-false}"
SOCKS_PORT="${SOCKS_PORT:-}"
SOCKS_PUB_PORT="${SOCKS_PUB_PORT:-}"
SOCKS_USER="${SOCKS_USER:-}"
SOCKS_PASS="${SOCKS_PASS:-}"
LOGLEVEL="$LOGLEVEL"
RESTART_EVERY="${RESTART_EVERY:-off}"
CREATED="$(date '+%F %T')"
EOF
  chmod 600 "$1/meta.conf"
}

META_KEYS="NAME ROLE PORT TOKEN TRANSPORT CHANNEL_SIZE MUX_CON POOL AGGRESSIVE \
ACCEPT_UDP NODELAY PROFILE OV_POOL OV_CHANNEL OV_HEARTBEAT OV_KEEPALIVE OV_MUXCON \
OV_AGGRESSIVE OV_RETRY OV_DIAL OV_NODELAY OV_FRAME OV_RECVBUF OV_STREAMBUF OV_MUXVER \
SNIFFER WEB_PORT EDGE_IP PEER_IP PUB_IP TLS_CERT TLS_KEY LOGLEVEL RESTART_EVERY \
SOCKS_ENABLE SOCKS_PORT SOCKS_PUB_PORT SOCKS_USER SOCKS_PASS"

meta_set() { # <tunnel> <key> <value>
  local f="$TUN_DIR/$1/meta.conf"
  [ -f "$f" ] || return 1
  if grep -q "^$2=" "$f"; then sed -i "s|^$2=.*|$2=\"$3\"|" "$f"
  else printf '%s="%s"\n' "$2" "$3" >> "$f"; fi
}

load_meta() {
  local dir="$TUN_DIR/$1"
  [ -f "$dir/meta.conf" ] || return 1
  NAME=""; ROLE=""; PORT=""; TOKEN=""; TRANSPORT=""; CHANNEL_SIZE=""; MUX_CON=""
  POOL=""; AGGRESSIVE="false"; ACCEPT_UDP="false"; NODELAY="true"
  PROFILE="balanced"
  OV_POOL=""; OV_CHANNEL=""; OV_HEARTBEAT=""; OV_KEEPALIVE=""; OV_MUXCON=""
  OV_AGGRESSIVE=""; OV_RETRY=""; OV_DIAL=""; OV_NODELAY=""
  OV_FRAME=""; OV_RECVBUF=""; OV_STREAMBUF=""; OV_MUXVER=""
  SNIFFER="false"; WEB_PORT="0"; EDGE_IP=""; PEER_IP=""; PUB_IP=""
  TLS_CERT=""; TLS_KEY=""
  SOCKS_ENABLE="false"; SOCKS_PORT=""; SOCKS_PUB_PORT=""; SOCKS_USER=""; SOCKS_PASS=""
  LOGLEVEL="info"; RESTART_EVERY="off"
  # meta.conf is never sourced: a value that arrived in a pair code would then
  # run as root. Parse it as plain key="value" data instead.
  local _line _k _v
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|'#'*) continue ;; esac
    _k="${_line%%=*}"; _v="${_line#*=}"
    [ "$_k" = "$_line" ] && continue
    [[ "$_k" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    case " $META_KEYS " in *" $_k "*) ;; *) continue ;; esac
    _v="${_v%\"}"; _v="${_v#\"}"
    _v="${_v//[$'\n\r']/}"
    printf -v "$_k" '%s' "$_v"
  done < "$dir/meta.conf"
  # Socks fields can have arrived in a pair code, so re-check them on every
  # load rather than trusting what is on disk.
  [ "$SOCKS_ENABLE" = true ] || SOCKS_ENABLE=false
  valid_port "$SOCKS_PORT" || SOCKS_PORT=""
  valid_port "$SOCKS_PUB_PORT" || SOCKS_PUB_PORT=""
  valid_socks_user "$SOCKS_USER" || SOCKS_USER=""
  valid_socks_pass "$SOCKS_PASS" || SOCKS_PASS=""
  [ -n "$SOCKS_PORT" ] && [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ] || SOCKS_ENABLE=false
  local heal=0
  TRANSPORT="$(printf '%s' "$TRANSPORT" | strip_ansi | tr -d ' \n' | tail -c 8)"
  is_transport "$TRANSPORT" || { TRANSPORT="$DEFAULT_TRANSPORT"; heal=1; }
  valid_profile "$PROFILE" || { PROFILE=balanced; heal=1; }
  [ "$heal" -eq 1 ] && sed -i "s|^TRANSPORT=.*|TRANSPORT=\"$TRANSPORT\"|; s|^PROFILE=.*|PROFILE=\"$PROFILE\"|" "$dir/meta.conf" 2>/dev/null
  # A tunnel written by an older build has none of these keys, and sed cannot
  # rewrite a line that is not there - so append whatever is missing.
  local _k
  for _k in PROFILE OV_POOL OV_CHANNEL OV_HEARTBEAT OV_KEEPALIVE OV_MUXCON \
            OV_AGGRESSIVE OV_RETRY OV_DIAL OV_NODELAY OV_FRAME OV_RECVBUF \
            OV_STREAMBUF OV_MUXVER SOCKS_ENABLE SOCKS_PORT SOCKS_PUB_PORT \
            SOCKS_USER SOCKS_PASS; do
    grep -q "^$_k=" "$dir/meta.conf" 2>/dev/null && continue
    case "$_k" in
      PROFILE)      printf 'PROFILE="%s"\n' "$PROFILE" >> "$dir/meta.conf" ;;
      SOCKS_ENABLE) printf 'SOCKS_ENABLE="false"\n' >> "$dir/meta.conf" ;;
      *)            printf '%s=""\n' "$_k" >> "$dir/meta.conf" ;;
    esac
  done
  return 0
}

regen_config() {
  local n="$1"
  load_meta "$n" || return 1
  if [ "$ROLE" = server ]; then
    if is_tls "$TRANSPORT" && { [ -z "$TLS_CERT" ] || [ ! -s "$TLS_CERT" ]; }; then
      make_self_signed "$TUN_DIR/$n"
      sed -i "s|^TLS_CERT=.*|TLS_CERT=\"$TLS_CERT\"|; s|^TLS_KEY=.*|TLS_KEY=\"$TLS_KEY\"|" "$TUN_DIR/$n/meta.conf"
    fi
    write_server_config "$TUN_DIR/$n"
  else
    write_client_config "$TUN_DIR/$n"
  fi
  config_sane "$TUN_DIR/$n/config.toml"
}

# ============================================================== PAIR CODE ==
ports_csv() {
  local out="" lport target
  while IFS=$'\t' read -r lport target; do
    [ -z "$lport" ] && continue
    if [ -n "$target" ] && [ "$target" != "-" ]; then out="${out:+$out,}${lport}>${target}"
    else out="${out:+$out,}${lport}"; fi
  done < "$1/ports.list"
  echo "$out"
}
pretty_ports() {
  local csv="$1" i out=""
  [ -z "$csv" ] && { echo none; return; }
  IFS=',' read -r -a _pp <<<"$csv"
  for i in "${_pp[@]}"; do out="$out ${i/>/ -> }"; done
  echo "${out# }"
}
tr_idx() { case "$1" in tcp) echo 1 ;; ws) echo 3 ;; wsmux) echo 4 ;; wss) echo 5 ;; wssmux) echo 6 ;; udp) echo 7 ;; *) echo 2 ;; esac; }
idx_tr() { case "$1" in 1) echo tcp ;; 3) echo ws ;; 4) echo wsmux ;; 5) echo wss ;; 6) echo wssmux ;; 7) echo udp ;; *) echo tcpmux ;; esac; }

# B3|IRAN_IP|PORT|TOKEN|TRANSPORT#|PROFILE|RESTART|PORTS|SPORT|SPUB|SUSER|SPASS
# (B2 and B1 are still read, so codes from older builds keep working)
make_pair_code() {
  local sp="" spub="" su="" spw=""
  if [ "${SOCKS_ENABLE:-false}" = true ]; then
    sp="${SOCKS_PORT:-}"; spub="${SOCKS_PUB_PORT:-}"
    su="${SOCKS_USER:-}"; spw="${SOCKS_PASS:-}"
  fi
  local p="B3|$PUB_IP|$PORT|$TOKEN|$(tr_idx "$TRANSPORT")|${PROFILE:-balanced}|${RESTART_EVERY:-off}|$(ports_csv "$1")|$sp|$spub|$su|$spw"
  printf 'ETN-%s' "$(printf '%s' "$p" | b64enc)"
}
parse_pair_code() {
  local code="$1" raw ver ti
  code="${code#ETN-}"; code="${code#DBH-}"; code="$(tr -d '[:space:]' <<<"$code")"
  raw="$(printf '%s' "$code" | b64dec)" || return 1
  PC_IP=""; PC_PORT=""; PC_TOKEN=""; PC_TR=""; PC_POOL=""; PC_PROFILE="balanced"
  PC_RESTART="off"; PC_PORTS=""
  PC_SPORT=""; PC_SPUB=""; PC_SUSER=""; PC_SPASS=""
  if [[ "$raw" == B3\|* ]]; then
    IFS='|' read -r ver PC_IP PC_PORT PC_TOKEN ti PC_PROFILE PC_RESTART PC_PORTS \
                     PC_SPORT PC_SPUB PC_SUSER PC_SPASS <<<"$raw"
  elif [[ "$raw" == B2\|* ]]; then
    IFS='|' read -r ver PC_IP PC_PORT PC_TOKEN ti PC_PROFILE PC_RESTART PC_PORTS <<<"$raw"
  elif [[ "$raw" == B1\|* ]]; then
    IFS='|' read -r ver PC_IP PC_PORT PC_TOKEN ti PC_POOL PC_RESTART PC_PORTS <<<"$raw"
  else return 1; fi
  PC_TR="$(idx_tr "$ti")"
  valid_profile "$PC_PROFILE" || PC_PROFILE=balanced
  [[ "$PC_POOL" =~ ^[0-9]+$ ]] || PC_POOL="$DEFAULT_POOL"
  case "$PC_RESTART" in off|1h|6h|12h|24h) ;; *) PC_RESTART=off ;; esac
  # A pair code is pasted in from outside, so treat every field as hostile.
  valid_ports_csv "$PC_PORTS" || return 1
  valid_token "$PC_TOKEN" || return 1
  if [ -n "$PC_SPORT$PC_SPUB$PC_SUSER$PC_SPASS" ]; then
    valid_port "$PC_SPORT" || return 1
    valid_socks_user "$PC_SUSER" || return 1
    valid_socks_pass "$PC_SPASS" || return 1
    [ -z "$PC_SPUB" ] || valid_port "$PC_SPUB" || return 1
  fi
  valid_host "$PC_IP" && valid_port "$PC_PORT"
}
show_pair_code() {
  local code; code="$(cat "$TUN_DIR/$1/pair.code" 2>/dev/null)"
  [ -z "$code" ] && { bad "no pair code stored"; return; }
  echo; top; sect "PAIR CODE"
  row "$(printf '%spaste this on the KHAREJ server%s' "$D" "$N")"; blank; bot
  echo; printf '%s%s%s\n' "$W" "$code" "$N"; echo
}


# ---------------------------------------------------------- PARTIAL STATE --
# A tunnel directory is created before its metadata is written, so a Ctrl+C
# half way through setup used to leave a folder that no screen could open and
# nothing could delete. Track the in-progress name and clear it on interrupt.
PARTIAL_TUNNEL=""

tunnel_complete() {
  [ -s "$TUN_DIR/$1/meta.conf" ] && [ -s "$TUN_DIR/$1/config.toml" ]
}

# A stuck unit sits in "deactivating" and every systemctl call blocks behind it,
# which from the menu looks exactly like a freeze. Bound the stop and force it.
stop_tunnel_hard() {
  local n="$1"
  socks_down "$n"
  systemctl disable "backhaul@$n" >/dev/null 2>&1
  if ! timeout 15 systemctl stop "backhaul@$n" >/dev/null 2>&1; then
    warn "service did not stop in time - forcing it"
    systemctl kill -s SIGKILL "backhaul@$n" >/dev/null 2>&1
    sleep 1
  fi
  systemctl reset-failed "backhaul@$n" >/dev/null 2>&1
  return 0
}

discard_partial() {
  [ -n "$PARTIAL_TUNNEL" ] || return 0
  local p="$PARTIAL_TUNNEL"; PARTIAL_TUNNEL=""
  [ -d "$TUN_DIR/$p" ] || return 0
  tunnel_complete "$p" && return 0
  rm -rf "${TUN_DIR:?}/$p"
  return 0
}

on_interrupt() {
  trap - INT TERM
  echo
  if [ -n "$PARTIAL_TUNNEL" ]; then
    discard_partial
    printf '  %s!%s cancelled - the half-created tunnel was removed\n' "$Y" "$N"
  else
    printf '  %s!%s cancelled\n' "$Y" "$N"
  fi
  exit 130
}

# Catches leftovers from a hard kill, a dropped ssh session or an older build.
sweep_partials() {
  local n broken=()
  while read -r n; do
    [ -n "$n" ] || continue
    tunnel_complete "$n" || broken+=("$n")
  done <<<"$(tunnel_names)"
  [ ${#broken[@]} -eq 0 ] && return 0
  echo
  top; sect "INCOMPLETE TUNNELS"
  row "$(printf '%sthese were never finished and cannot be started%s' "$D" "$N")"
  blank
  for n in "${broken[@]}"; do row "$(printf '%s%s%s' "$R" "$n" "$N")"; done
  bot; echo
  if yesno "remove them?" y; then
    for n in "${broken[@]}"; do
      stop_tunnel_hard "$n"
      :
      rm -rf "${TUN_DIR:?}/$n"
      ok "removed $n"
    done
    pause
  fi
  return 0
}


# ============================================================ ACCOUNTING ====
# Backhaul reports no counters of its own. On the IRAN side it owns real
# listening sockets, so a dedicated iptables chain with target-less rules can
# count the bytes without changing what any packet does: a rule with no -j
# simply increments and falls through.
ACCT_CHAIN="ERISTUN2_ACCT"

acct_ensure_chain() {
  command -v iptables >/dev/null 2>&1 || return 1
  iptables -w 5 -N "$ACCT_CHAIN" 2>/dev/null
  iptables -w 5 -C INPUT  -j "$ACCT_CHAIN" 2>/dev/null || iptables -w 5 -I INPUT  1 -j "$ACCT_CHAIN" 2>/dev/null
  iptables -w 5 -C OUTPUT -j "$ACCT_CHAIN" 2>/dev/null || iptables -w 5 -I OUTPUT 1 -j "$ACCT_CHAIN" 2>/dev/null
  return 0
}
acct_sync() { # <tunnel> - make sure every user port of this tunnel is counted
  local n="$1" lport t
  load_meta "$n" >/dev/null 2>&1 || return 1
  [ "$ROLE" = server ] || return 0
  [ -s "$TUN_DIR/$n/ports.list" ] || return 0
  acct_ensure_chain || return 1
  while IFS=$'\t' read -r lport t; do
    valid_port "$lport" || continue
    iptables -w 5 -C "$ACCT_CHAIN" -p tcp --dport "$lport" 2>/dev/null || iptables -w 5 -A "$ACCT_CHAIN" -p tcp --dport "$lport" 2>/dev/null
    iptables -w 5 -C "$ACCT_CHAIN" -p tcp --sport "$lport" 2>/dev/null || iptables -w 5 -A "$ACCT_CHAIN" -p tcp --sport "$lport" 2>/dev/null
  done < "$TUN_DIR/$n/ports.list"
  return 0
}
acct_bytes() { # <dpt|spt> <port>
  iptables -w 5 -L "$ACCT_CHAIN" -v -n -x 2>/dev/null \
    | awk -v m="$1:$2" '$0 ~ m {s+=$2} END{print s+0}'
}
# "<in> <out>" in bytes, or "-1 -1" when this side cannot be measured
tunnel_traffic() {
  local n="$1" lport t inb=0 outb=0 a
  load_meta "$n" >/dev/null 2>&1 || { echo "-1 -1"; return; }
  [ "$ROLE" = server ] || { echo "-1 -1"; return; }
  [ -s "$TUN_DIR/$n/ports.list" ] || { echo "0 0"; return; }
  while IFS=$'\t' read -r lport t; do
    valid_port "$lport" || continue
    a="$(acct_bytes dpt "$lport")"; inb=$((inb + ${a:-0}))
    a="$(acct_bytes spt "$lport")"; outb=$((outb + ${a:-0}))
  done < "$TUN_DIR/$n/ports.list"
  echo "$inb $outb"
}
fmt_traffic() { [ "${1:--1}" -lt 0 ] 2>/dev/null && printf '' || human_bytes "$1"; }

# =========================================================== TUNNEL BASICS =
tunnel_names() { ls -1 "$TUN_DIR" 2>/dev/null; }
tunnel_count() { tunnel_names | grep -c . ; }
svc_raw() { systemctl is-active "backhaul@$1" 2>/dev/null; }
svc_uptime_short() {
  local ts t n d
  ts="$(systemctl show "backhaul@$1" -p ActiveEnterTimestamp --value 2>/dev/null)"
  [ -z "$ts" ] && { echo "-"; return; }
  t="$(date -d "$ts" +%s 2>/dev/null)" || { echo "-"; return; }
  n="$(date +%s)"; d=$((n-t)); ((d<0)) && { echo "-"; return; }
  if   [ "$d" -ge 86400 ]; then printf '%dd%02dh' $((d/86400)) $((d%86400/3600))
  elif [ "$d" -ge 3600 ];  then printf '%dh%02dm' $((d/3600)) $((d%3600/60))
  else printf '%dm%02ds' $((d/60)) $((d%60)); fi
}
drops_since() { journalctl -u "backhaul@$1" --since "$2" --no-pager 2>/dev/null \
                | grep -ciE 'disconnect|reconnect|connection failed|retry'; }

start_tunnel() {
  local n="$1"
  config_sane "$TUN_DIR/$n/config.toml" || { bad "generated config failed the sanity check"; return 1; }
  systemctl enable "backhaul@$n" >/dev/null 2>&1
  acct_sync "$n" >/dev/null 2>&1
  systemctl restart "backhaul@$n" 2>/dev/null
  sleep 2
  [ "$(svc_raw "$n")" = active ] && { ok "backhaul@$n running, enabled on boot"; return 0; }
  bad "service failed to start"; echo
  journalctl -u "backhaul@$n" -n 8 --no-pager -o cat 2>/dev/null | grep -viE '^\s*$' | tail -n 6 | sed "s/^/    $R/;s/\$/$N/"
  return 1
}

pick_tunnel() {
  local l names=() i=1 n
  l="$(tunnel_names)"
  [ -z "$l" ] && { bad "no tunnels yet"; return 1; }
  echo; top; sect "TUNNELS"; blank
  while read -r n; do
    [ -z "$n" ] && continue
    names+=("$n")
    if ! tunnel_complete "$n"; then
      row "$(printf '%s[%d]%s %s%s %-13s %sINCOMPLETE%s' "$Y" "$i" "$N" "$R" "x" "$n" "$R" "$N")"
      i=$((i+1)); continue
    fi
    load_meta "$n"
    row "$(printf '%s[%d]%s %s %-13s %s%-6s%s %s%s%s' "$Y" "$i" "$N" "$(dot "$(svc_raw "$n")")" \
        "$n" "$D" "$([ "$ROLE" = server ] && echo iran || echo kharej)" "$N" "$D" \
        "$([ "$ROLE" = server ] && echo ":$PORT" || echo "-> $PEER_IP:$PORT")" "$N")"
    i=$((i+1))
  done <<<"$l"
  blank; item 0 "Back" ""; bot; echo; getkey
  [[ "$KEY" =~ ^[0-9]+$ ]] || return 1
  [ "$KEY" -eq 0 ] || [ "$KEY" -gt "${#names[@]}" ] && return 1
  SELECTED="${names[$((KEY-1))]}"
  return 0
}

read_ports_into() {
  local out="$1" tunnel_port="$2" p n=0 parr
  : > "$out"
  while :; do
    ask "ports"
    IFS=', ' read -r -a parr <<<"$ANS"
    n=0; : > "$out"
    for p in "${parr[@]}"; do
      valid_port "$p" || continue
      [ "$p" = "$tunnel_port" ] && { bad "$p is the tunnel port - skipped"; continue; }
      printf '%s\t-\n' "$p" >> "$out"; n=$((n+1))
    done
    [ "$n" -gt 0 ] && break
    bad "enter at least one valid port"
  done
}

# ============================================================ CREATE IRAN ==
screen_new_iran() {
  header "NEW TUNNEL - IRAN (server side)"
  [ -x "$BIN_PATH" ] || { bad "core not installed - main menu [1]"; pause; return; }
  top; sect "ROLE CHECK"
  row "$(printf '%sIRAN is the [server]. it binds the port and exposes%s' "$D" "$N")"
  row "$(printf '%sthe ports your users connect to. the pair code is%s' "$D" "$N")"
  row "$(printf '%smade here and pasted on the kharej server.%s' "$D" "$N")"
  bot; echo

  local name
  while :; do
    ask "tunnel name"; name="$ANS"
    valid_name "$name" || { bad "letters, digits, - and _ only"; continue; }
    [ -d "$TUN_DIR/$name" ] && { bad "name already exists"; continue; }
    break
  done
  while :; do
    ask "tunnel port" "$DEFAULT_PORT"; PORT="$ANS"
    valid_port "$PORT" || { bad "invalid port"; continue; }
    if port_in_use "$PORT"; then
      warn "port $PORT is already in use"
      yesno "use it anyway?" n || continue
    fi
    break
  done

  info "detecting this server's address"
  local _a _src _line
  read -r _a _src <<<"$(detect_server_addr)"
  echo; top; sect "THIS IRAN SERVER"
  row "$(printf '%saddresses configured here:%s' "$D" "$N")"
  while read -r _line; do
    [ -n "$_line" ] && row "$(printf '   %s%-8s %s%s' "$D" "${_line%% *}" "${_line##* }" "$N")"
  done <<<"$(local_ipv4s)"
  blank
  case "$_src" in
    interface) kv "will use" "$W$_a$N $D(bound on this server)$N" ;;
    nat:*)     kv "will use" "$W$_a$N"
               row "$(printf '%soutbound traffic leaves via %s - pick that one%s' "$Y" "${_src#nat:}" "$N")"
               row "$(printf '%sonly if that is the address your users reach%s' "$D" "$N")" ;;
    *)         row "$(printf '%scould not detect an address - enter it yourself%s' "$R" "$N")" ;;
  esac
  bot; echo
  ask "public ip of this iran server" "$_a"; PUB_IP="$ANS"
  valid_host "$PUB_IP" || { bad "invalid address"; pause; return; }
  valid_ip4 "$PUB_IP" && ! ip_is_local "$PUB_IP" && \
    warn "$PUB_IP is not configured on this server - make sure it forwards here"

  echo; top; sect "USER PORTS"
  row "$(printf '%sthe ports your users will connect to on THIS server%s' "$D" "$N")"
  row "$(printf '%sone line, comma separated    e.g.  8000,2087,443%s' "$D" "$N")"
  bot; echo
  mkdir -p "$TUN_DIR/$name"; PARTIAL_TUNNEL="$name"
  read_ports_into "$TUN_DIR/$name/ports.list" "$PORT"
  ok "$(grep -c . "$TUN_DIR/$name/ports.list") port(s)"

  TRANSPORT="$DEFAULT_TRANSPORT"; CHANNEL_SIZE="$DEFAULT_CHANNEL"; MUX_CON="$DEFAULT_MUXCON"
  POOL="$DEFAULT_POOL"; AGGRESSIVE=false; ACCEPT_UDP=false; NODELAY=true
  SNIFFER=false; WEB_PORT=0; EDGE_IP=""
  echo
  PROFILE="$(pick_profile)"
  if yesno "change the transport?" n; then
    TRANSPORT="$(pick_transport)"
    yesno "carry udp over tcp (accept_udp)?" n && ACCEPT_UDP=true
  fi
  dim "everything else follows the profile - pin values later in Tuning"
  is_transport "$TRANSPORT" || TRANSPORT="$DEFAULT_TRANSPORT"
  [ "$TRANSPORT" = udp ] && ACCEPT_UDP=false
  RESTART_EVERY="$(pick_restart)"

  SOCKS_ENABLE=false; SOCKS_PORT=""; SOCKS_PUB_PORT=""; SOCKS_USER=""; SOCKS_PASS=""
  if [ "$TRANSPORT" != udp ]; then
    echo; top; sect "SOCKS5 PROXY (optional)"
    row "$(printf '%shand this tunnel out as an outbound proxy as well: apps%s' "$D" "$N")"
    row "$(printf '%stalk socks5 to this server and leave from the kharej ip.%s' "$D" "$N")"
    bot; echo
    if yesno "expose a socks5 proxy through this tunnel?" n; then
      while :; do
        ask "socks port for users on THIS server" "$DEFAULT_SOCKS_PORT"; SOCKS_PUB_PORT="$ANS"
        valid_port "$SOCKS_PUB_PORT" || { bad "invalid port"; continue; }
        [ "$SOCKS_PUB_PORT" = "$PORT" ] && { bad "that is the tunnel port"; continue; }
        if awk -F'\t' -v x="$SOCKS_PUB_PORT" '$1==x{f=1} END{exit !f}' "$TUN_DIR/$name/ports.list" 2>/dev/null; then
          bad "$SOCKS_PUB_PORT is already one of the user ports"; continue
        fi
        if port_in_use "$SOCKS_PUB_PORT"; then
          warn "port $SOCKS_PUB_PORT is already in use"
          yesno "use it anyway?" n || continue
        fi
        break
      done
      ask "socks port on the KHAREJ server" "$DEFAULT_SOCKS_PORT"; SOCKS_PORT="$ANS"
      valid_port "$SOCKS_PORT" || SOCKS_PORT="$DEFAULT_SOCKS_PORT"
      SOCKS_USER="$(gen_socks_user)"; SOCKS_PASS="$(gen_socks_pass)"
      SOCKS_ENABLE=true
      socks_row_set "$TUN_DIR/$name" "$SOCKS_PUB_PORT" "$SOCKS_PORT"
      ok "socks5 will listen on :$SOCKS_PUB_PORT here"
      dim "the kharej side sets its own proxy up from the pair code"
    fi
  fi

  if yesno "enable the built-in web dashboard?" n; then
    ask "dashboard port" "2060"
    valid_port "$ANS" && { WEB_PORT="$ANS"; SNIFFER=true; }
  fi

  valid_profile "$PROFILE" || PROFILE=balanced
  TOKEN="$(gen_token)"
  NAME="$name"; ROLE=server; PEER_IP=""; LOGLEVEL=info

  TLS_CERT=""; TLS_KEY=""
  if is_tls "$TRANSPORT"; then
    choose_cert "$TUN_DIR/$name" || { discard_partial; pause; return; }
  fi
  write_meta "$TUN_DIR/$name"
  PARTIAL_TUNNEL=""
  write_server_config "$TUN_DIR/$name"
  ensure_units
  make_pair_code "$TUN_DIR/$name" > "$TUN_DIR/$name/pair.code"
  chmod 600 "$TUN_DIR/$name/pair.code"

  echo; top; sect "CREATED - $name"; blank
  kv "listen"    "$W:$PORT$N"
  kv "transport" "$W$TRANSPORT$N $D- $(transport_hint "$TRANSPORT")$N"
  kv "ports"     "$W$(pretty_ports "$(ports_csv "$TUN_DIR/$name")")$N"
  [ "$SOCKS_ENABLE" = true ] && kv "socks5" "$W$(socks_uri "$PUB_IP" "$SOCKS_PUB_PORT" "$SOCKS_USER" "$SOCKS_PASS")$N"
  kv "restart"   "$([ "$RESTART_EVERY" = off ] && printf '%soff%s' "$D" "$N" || printf '%severy %s%s' "$G" "$RESTART_EVERY" "$N")"
  [ -n "$TLS_CERT" ] && kv "certificate" "$W$(cert_cn "$TLS_CERT")$N $D- $(cert_days_left "$TLS_CERT")d left$N"
  [ "$WEB_PORT" != 0 ] && kv "dashboard" "${W}http://$PUB_IP:$WEB_PORT$N"
  bot; echo
  start_tunnel "$name"
  set_restart_timer "$name" "$RESTART_EVERY"
  show_pair_code "$name"
  warn "open TCP/$PORT for the kharej server in your firewall"
  warn "also open the user ports above"
  pause
}

# ========================================================== CREATE KHAREJ ==
screen_new_kharej() {
  header "NEW TUNNEL - KHAREJ (client side)"
  [ -x "$BIN_PATH" ] || { bad "core not installed - main menu [1]"; pause; return; }
  top; sect "ROLE CHECK"
  row "$(printf '%sKHAREJ is the [client]. it dials out to iran and%s' "$D" "$N")"
  row "$(printf '%sneeds no inbound port. your panel lives here.%s' "$D" "$N")"
  bot; echo

  local name
  while :; do
    ask "tunnel name"; name="$ANS"
    valid_name "$name" || { bad "letters, digits, - and _ only"; continue; }
    [ -d "$TUN_DIR/$name" ] && { bad "name already exists"; continue; }
    break
  done

  echo; info "paste the pair code from the IRAN server"
  ask "pair code"
  if ! parse_pair_code "$ANS"; then
    bad "invalid or unrecognised pair code"
    echo; yesno "enter the settings manually?" n || { pause; return; }
    ask "iran ip";     PC_IP="$ANS"
    ask "tunnel port" "$DEFAULT_PORT"; PC_PORT="$ANS"
    ask "token";       PC_TOKEN="$ANS"
    PC_TR="$(pick_transport)"; PC_PROFILE="$(pick_profile)"; PC_RESTART=off; PC_PORTS=""
    valid_host "$PC_IP" && valid_port "$PC_PORT" || { bad "invalid ip or port"; pause; return; }
    valid_token "$PC_TOKEN" || { bad "token must be 8-128 chars of A-Z a-z 0-9 + / = . _ @ : -"; pause; return; }
  fi

  echo; top; sect "PAIRED WITH"; blank
  kv "iran"      "$W$PC_IP:$PC_PORT$N"
  kv "transport" "$W$PC_TR$N"
  kv "profile"   "$W$(profile_name "$PC_PROFILE")$N $D$(profile_hint "$PC_PROFILE")$N"
  kv "ports"     "$W$(pretty_ports "$PC_PORTS")$N"
  kv "restart"   "$([ "$PC_RESTART" = off ] && printf '%soff%s' "$D" "$N" || printf '%severy %s%s' "$G" "$PC_RESTART" "$N")"
  bot; echo

  EDGE_IP=""
  case "$PC_TR" in ws|wss|wsmux|wssmux)
    if yesno "connect through a cdn edge ip?" n; then
      ask "edge ip" "188.114.96.0"
      if valid_ip4 "$ANS"; then EDGE_IP="$ANS"; else bad "not a valid ip - ignored"; fi
    fi ;;
  esac
  SNIFFER=false; WEB_PORT=0
  if yesno "enable the built-in web dashboard?" n; then
    ask "dashboard port" "2060"
    valid_port "$ANS" && { WEB_PORT="$ANS"; SNIFFER=true; }
  fi

  mkdir -p "$TUN_DIR/$name"; PARTIAL_TUNNEL="$name"
  : > "$TUN_DIR/$name/ports.list"
  NAME="$name"; ROLE=client; PORT="$PC_PORT"; TOKEN="$PC_TOKEN"; TRANSPORT="$PC_TR"
  POOL="$PC_POOL"; PROFILE="$PC_PROFILE"; PEER_IP="$PC_IP"; PUB_IP=""; LOGLEVEL=info
  CHANNEL_SIZE="$DEFAULT_CHANNEL"; MUX_CON="$DEFAULT_MUXCON"
  AGGRESSIVE=false; ACCEPT_UDP=false; NODELAY=true; RESTART_EVERY="$PC_RESTART"
  TLS_CERT=""; TLS_KEY=""
  SOCKS_ENABLE=false; SOCKS_PORT=""; SOCKS_PUB_PORT=""; SOCKS_USER=""; SOCKS_PASS=""

  write_meta "$TUN_DIR/$name"
  PARTIAL_TUNNEL=""
  write_client_config "$TUN_DIR/$name"
  ensure_units

  echo; top; sect "CREATED - $name"; blank
  kv "dials"     "$W$PEER_IP:$PORT$N"
  kv "transport" "$W$TRANSPORT$N"
  bot; echo
  start_tunnel "$name" || { pause; return; }
  set_restart_timer "$name" "$RESTART_EVERY"
  [ "$RESTART_EVERY" != off ] && ok "scheduled restart armed from the pair code: every $RESTART_EVERY"

  if [ -n "$PC_SPORT" ]; then
    echo; top; sect "SOCKS5 PROXY"
    row "$(printf '%sthe iran side publishes a socks5 proxy and expects it%s' "$D" "$N")"
    row "$(printf '%sto run here on 127.0.0.1:%s%s' "$D" "$PC_SPORT" "$N")"
    bot; echo
    if yesno "set the socks5 proxy up now?" y; then
      SOCKS_PORT="$PC_SPORT"; SOCKS_PUB_PORT="$PC_SPUB"
      SOCKS_USER="$PC_SUSER"; SOCKS_PASS="$PC_SPASS"
      if socks_ensure_provider; then
        socks_env_write "$name"
        meta_set "$name" SOCKS_PORT "$SOCKS_PORT"
        meta_set "$name" SOCKS_PUB_PORT "$SOCKS_PUB_PORT"
        meta_set "$name" SOCKS_USER "$SOCKS_USER"
        meta_set "$name" SOCKS_PASS "$SOCKS_PASS"
        meta_set "$name" SOCKS_ENABLE true
        if socks_up "$name"; then
          ok "socks5 proxy up on 127.0.0.1:$SOCKS_PORT via $(socks_provider_name)"
          [ -n "$SOCKS_PUB_PORT" ] && \
            dim "users: $(socks_uri "$PEER_IP" "$SOCKS_PUB_PORT" "$SOCKS_USER" "$SOCKS_PASS")"
        else
          bad "the socks service did not start"
          dim "journalctl -u eris-socks@$name -n 30"
        fi
      fi
    fi
  fi
  echo
  info "your panel on THIS server must listen on the same ports"
  dim "users connect to  $PEER_IP:<user port>"
  pause
}

# ================================================================== PORTS ==
screen_ports() {
  local name="$1" dir="$TUN_DIR/$1"
  load_meta "$name"
  if [ "$ROLE" != server ]; then
    header "PORTS - $name"
    bad "ports are defined on the IRAN side only"
    dim "the kharej client learns them through the tunnel"
    pause; return
  fi
  while :; do
    load_meta "$name"
    header "PORTS - $name"
    top; sect "USER PORTS"; blank
    if [ ! -s "$dir/ports.list" ]; then row "$(printf '%s(none)%s' "$D" "$N")"
    else
      local i=1 lport target _lbl
      while IFS=$'\t' read -r lport target; do
        [ -z "$lport" ] && continue
        if [ "$SOCKS_ENABLE" = true ] && [ "$lport" = "$SOCKS_PUB_PORT" ]; then
          _lbl="-> socks5 proxy on kharej"
        elif [ "$target" != "-" ]; then _lbl="-> $target"
        else _lbl="-> same port on kharej"; fi
        row "$(printf '%s%2d.%s %s%-8s%s %s%s%s' "$D" "$i" "$N" "$C" "$lport" "$N" "$D" "$_lbl" "$N")"
        i=$((i+1))
      done < "$dir/ports.list"
    fi
    mid
    item 1 "Add port" ""
    item 2 "Remove port" "by row number"
    item 3 "Apply + restart" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) echo; top; sect "ADD PORTS"
         row "$(printf '%sone port, or several separated by commas%s' "$D" "$N")"
         row "$(printf '%sexample:  8000,2087,443%s' "$D" "$N")"
         bot; echo
         ask "port(s)"
         local p added=0 skipped=0 _pa
         IFS=', ' read -r -a _pa <<<"$ANS"
         for p in "${_pa[@]}"; do
           valid_port "$p" || { skipped=$((skipped+1)); continue; }
           [ "$p" = "$PORT" ] && { bad "$p is the tunnel port - skipped"; skipped=$((skipped+1)); continue; }
           if awk -F'\t' -v x="$p" '$1==x{f=1} END{exit !f}' "$dir/ports.list" 2>/dev/null; then
             warn "$p is already in the list"; skipped=$((skipped+1)); continue
           fi
           printf '%s\t-\n' "$p" >> "$dir/ports.list"; added=$((added+1))
         done
         if [ "$added" -gt 0 ]; then
           ok "$added port(s) added - press [3] to apply"
           yesno "point any of them at a different address on kharej?" n && {
             ask "which port"; local wp="$ANS"
             ask "target on kharej (host:port)"
             [ -n "$ANS" ] && awk -F'\t' -v x="$wp" -v t="$ANS" 'BEGIN{OFS="\t"} $1==x{$2=t} {print}' \
               "$dir/ports.list" > "$dir/ports.tmp" && mv -f "$dir/ports.tmp" "$dir/ports.list"
           }
         else bad "nothing added"; fi
         [ "$skipped" -gt 0 ] && dim "$skipped skipped"
         pause ;;
      2) ask "row number"
         [[ "$ANS" =~ ^[0-9]+$ ]] || { bad "invalid"; pause; continue; }
         if sed -i "${ANS}d" "$dir/ports.list" 2>/dev/null; then
           ok "removed - press [3] to apply"
           if [ "$SOCKS_ENABLE" = true ] && ! socks_row_present "$dir" "$SOCKS_PUB_PORT"; then
             meta_set "$name" SOCKS_ENABLE false
             warn "that row carried the socks5 proxy - socks is now off for this tunnel"
           fi
         else bad "failed"; fi
         pause ;;
      3) regen_config "$name" || { bad "config generation failed"; pause; continue; }
         acct_sync "$name" >/dev/null 2>&1
         make_pair_code "$dir" > "$dir/pair.code"
         systemctl restart "backhaul@$name" 2>/dev/null; sleep 2
         [ "$(svc_raw "$name")" = active ] && ok "applied and running" || bad "did not come up"
         warn "ports changed - the kharej side does not need re-pairing"
         pause ;;
      0|_) return ;;
    esac
  done
}

# =========================================================== SOCKS5 SCREEN =
socks_apply_iran() { # <name> - regenerate, re-pair, restart
  regen_config "$1" || return 1
  acct_sync "$1" >/dev/null 2>&1
  load_meta "$1"
  make_pair_code "$TUN_DIR/$1" > "$TUN_DIR/$1/pair.code"
  chmod 600 "$TUN_DIR/$1/pair.code"
  systemctl restart "backhaul@$1" 2>/dev/null; sleep 2
  [ "$(svc_raw "$1")" = active ]
}

screen_socks() {
  local name="$1" dir="$TUN_DIR/$1"
  while :; do
    load_meta "$name"
    header "SOCKS5 PROXY - $name"
    top; sect "HOW IT WORKS"
    row "$(printf '%san app speaks socks5 to the IRAN server, the tunnel%s' "$D" "$N")"
    row "$(printf '%scarries it to KHAREJ and the traffic leaves from there,%s' "$D" "$N")"
    row "$(printf '%sso the exit ip a site sees is the KHAREJ one.%s' "$D" "$N")"
    mid; sect "STATUS"; blank
    if [ "$SOCKS_ENABLE" = true ]; then kv "mode" "$(badge ON "$BG_OK$W")"
    else kv "mode" "$(badge OFF "$BG_WARN$W")"; fi
    if [ "$ROLE" = server ]; then
      kv "users port"  "$([ -n "$SOCKS_PUB_PORT" ] && printf '%s:%s%s' "$W" "$SOCKS_PUB_PORT" "$N" || printf '%s-%s' "$D" "$N")"
      kv "kharej port" "$([ -n "$SOCKS_PORT" ] && printf '%s127.0.0.1:%s%s' "$W" "$SOCKS_PORT" "$N" || printf '%s-%s' "$D" "$N")"
      if [ "$SOCKS_ENABLE" = true ] && ! socks_row_present "$dir" "$SOCKS_PUB_PORT"; then
        row "$(printf '%sthe port mapping is missing - turn socks off and on again%s' "$R" "$N")"
      fi
    else
      kv "listens on" "$([ -n "$SOCKS_PORT" ] && printf '%s127.0.0.1:%s%s' "$W" "$SOCKS_PORT" "$N" || printf '%s-%s' "$D" "$N")"
      kv "provider"   "$W$(socks_provider_name)$N"
      local _sk; _sk="$(socks_raw "$name")"
      kv "service"    "$([ "$_sk" = active ] && badge ACTIVE "$BG_OK$W" || badge "${_sk:-inactive}" "$BG_ERR$W")"
      kv "users reach" "$([ -n "$SOCKS_PUB_PORT" ] && printf '%s%s:%s%s' "$W" "$PEER_IP" "$SOCKS_PUB_PORT" "$N" || printf '%sset on the iran side%s' "$D" "$N")"
    fi
    kv "user"     "$([ -n "$SOCKS_USER" ] && printf '%s%s%s' "$W" "$SOCKS_USER" "$N" || printf '%s-%s' "$D" "$N")"
    kv "password" "$([ -n "$SOCKS_PASS" ] && printf '%s%s%s' "$W" "$SOCKS_PASS" "$N" || printf '%s-%s' "$D" "$N")"
    mid
    item 1 "$([ "$SOCKS_ENABLE" = true ] && echo "Turn off" || echo "Turn on")" ""
    if [ "$ROLE" = server ]; then
      item 2 "Change users port" "the port on THIS server"
      item 3 "Change kharej port" "must match the kharej side"
      item 4 "New credentials" "re-pair kharej afterwards"
    else
      item 2 "Change local port" "must match what iran maps to"
      item 3 "Set credentials" "copy them from the iran side"
      item 4 "Restart proxy service" ""
    fi
    item 5 "Client settings" "what to paste into an app"
    item t "Test the proxy" "shows the exit ip"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) if [ "$SOCKS_ENABLE" = true ]; then
           yesno "turn the socks5 proxy off?" y || { pause; continue; }
           if [ "$ROLE" = server ]; then
             socks_row_clear "$dir" "$SOCKS_PUB_PORT"
             meta_set "$name" SOCKS_ENABLE false
             socks_apply_iran "$name" && ok "socks5 is off" || bad "config apply failed"
           else
             socks_down "$name"; meta_set "$name" SOCKS_ENABLE false; ok "socks5 is off"
           fi
         elif [ "$ROLE" = server ]; then
           [ "$TRANSPORT" = udp ] && { bad "socks5 needs a tcp transport - this tunnel is udp"; pause; continue; }
           local pub kp
           ask "socks port for users on THIS server" "${SOCKS_PUB_PORT:-$DEFAULT_SOCKS_PORT}"; pub="$ANS"
           valid_port "$pub" || { bad "invalid port"; pause; continue; }
           [ "$pub" = "$PORT" ] && { bad "that is the tunnel port"; pause; continue; }
           ask "socks port on the KHAREJ server" "${SOCKS_PORT:-$DEFAULT_SOCKS_PORT}"; kp="$ANS"
           valid_port "$kp" || { bad "invalid port"; pause; continue; }
           [ -n "$SOCKS_USER" ] || SOCKS_USER="$(gen_socks_user)"
           [ -n "$SOCKS_PASS" ] || SOCKS_PASS="$(gen_socks_pass)"
           meta_set "$name" SOCKS_PUB_PORT "$pub"
           meta_set "$name" SOCKS_PORT "$kp"
           meta_set "$name" SOCKS_USER "$SOCKS_USER"
           meta_set "$name" SOCKS_PASS "$SOCKS_PASS"
           meta_set "$name" SOCKS_ENABLE true
           socks_row_set "$dir" "$pub" "$kp"
           if socks_apply_iran "$name"; then
             ok "socks5 published on :$pub"
             warn "re-pair the kharej side so it starts its proxy"
             warn "open TCP/$pub in this server's firewall"
           else bad "config apply failed"; fi
         else
           local kp2
           ask "local socks port (must match what iran maps to)" "${SOCKS_PORT:-$DEFAULT_SOCKS_PORT}"; kp2="$ANS"
           valid_port "$kp2" || { bad "invalid port"; pause; continue; }
           if [ -z "$SOCKS_USER" ]; then
             ask "socks user" "$(gen_socks_user)"; SOCKS_USER="$ANS"
           fi
           valid_socks_user "$SOCKS_USER" || { bad "user: 1-32 chars of A-Z a-z 0-9 _ -"; pause; continue; }
           if [ -z "$SOCKS_PASS" ]; then
             ask "socks password" "$(gen_socks_pass)"; SOCKS_PASS="$ANS"
           fi
           valid_socks_pass "$SOCKS_PASS" || { bad "password: 6-64 chars of A-Z a-z 0-9 . _ + -"; pause; continue; }
           socks_ensure_provider || { pause; continue; }
           SOCKS_PORT="$kp2"
           socks_env_write "$name"
           meta_set "$name" SOCKS_PORT "$kp2"
           meta_set "$name" SOCKS_USER "$SOCKS_USER"
           meta_set "$name" SOCKS_PASS "$SOCKS_PASS"
           meta_set "$name" SOCKS_ENABLE true
           if socks_up "$name"; then ok "socks5 listening on 127.0.0.1:$kp2"
           else bad "the service did not start"; dim "journalctl -u eris-socks@$name -n 30"; fi
         fi
         pause ;;
      2) if [ "$ROLE" = server ]; then
           ask "new socks port for users" "${SOCKS_PUB_PORT:-$DEFAULT_SOCKS_PORT}"
           valid_port "$ANS" || { bad "invalid port"; pause; continue; }
           [ "$ANS" = "$PORT" ] && { bad "that is the tunnel port"; pause; continue; }
           socks_row_clear "$dir" "$SOCKS_PUB_PORT"
           meta_set "$name" SOCKS_PUB_PORT "$ANS"
           [ "$SOCKS_ENABLE" = true ] && socks_row_set "$dir" "$ANS" "$SOCKS_PORT"
           socks_apply_iran "$name" && ok "users now connect to :$ANS" || bad "config apply failed"
         else
           ask "new local socks port" "${SOCKS_PORT:-$DEFAULT_SOCKS_PORT}"
           valid_port "$ANS" || { bad "invalid port"; pause; continue; }
           SOCKS_PORT="$ANS"
           meta_set "$name" SOCKS_PORT "$ANS"
           if [ "$SOCKS_ENABLE" = true ]; then
             socks_env_write "$name"
             socks_up "$name" && ok "listening on 127.0.0.1:$ANS" || bad "the service did not start"
           else ok "saved"; fi
           warn "the iran side must map its public port to 127.0.0.1:$ANS"
         fi
         pause ;;
      3) if [ "$ROLE" = server ]; then
           ask "new socks port on the KHAREJ server" "${SOCKS_PORT:-$DEFAULT_SOCKS_PORT}"
           valid_port "$ANS" || { bad "invalid port"; pause; continue; }
           meta_set "$name" SOCKS_PORT "$ANS"
           [ "$SOCKS_ENABLE" = true ] && socks_row_set "$dir" "$SOCKS_PUB_PORT" "$ANS"
           if socks_apply_iran "$name"; then
             ok "mapped to 127.0.0.1:$ANS on kharej"
             warn "set the same port on the kharej side, or re-pair it"
           else bad "config apply failed"; fi
         else
           ask "socks user" "${SOCKS_USER:-$(gen_socks_user)}"
           valid_socks_user "$ANS" || { bad "user: 1-32 chars of A-Z a-z 0-9 _ -"; pause; continue; }
           SOCKS_USER="$ANS"
           ask "socks password" "${SOCKS_PASS:-$(gen_socks_pass)}"
           valid_socks_pass "$ANS" || { bad "password: 6-64 chars of A-Z a-z 0-9 . _ + -"; pause; continue; }
           SOCKS_PASS="$ANS"
           meta_set "$name" SOCKS_USER "$SOCKS_USER"
           meta_set "$name" SOCKS_PASS "$SOCKS_PASS"
           if [ "$SOCKS_ENABLE" = true ]; then
             socks_env_write "$name"
             socks_up "$name" && ok "credentials applied" || bad "the service did not start"
           else ok "saved"; fi
         fi
         pause ;;
      4) if [ "$ROLE" = server ]; then
           yesno "generate a new user and password?" y || { pause; continue; }
           SOCKS_USER="$(gen_socks_user)"; SOCKS_PASS="$(gen_socks_pass)"
           meta_set "$name" SOCKS_USER "$SOCKS_USER"
           meta_set "$name" SOCKS_PASS "$SOCKS_PASS"
           load_meta "$name"
           make_pair_code "$dir" > "$dir/pair.code"; chmod 600 "$dir/pair.code"
           ok "new credentials stored"
           warn "kharej still uses the old ones - re-pair it or set them there by hand"
         else
           [ "$SOCKS_ENABLE" = true ] || { bad "socks is off"; pause; continue; }
           socks_env_write "$name"
           socks_up "$name" && ok "proxy restarted" || { bad "did not start"; dim "journalctl -u eris-socks@$name -n 30"; }
         fi
         pause ;;
      5) local h p
         [ "$ROLE" = server ] && h="$PUB_IP" || h="$PEER_IP"
         p="$SOCKS_PUB_PORT"
         if [ -z "$p" ] || [ -z "$SOCKS_USER" ] || [ -z "$SOCKS_PASS" ]; then
           bad "nothing to show yet - turn socks on first"; pause; continue
         fi
         echo; top; sect "CLIENT SETTINGS"; blank
         kv "type"     "${W}SOCKS5$N"
         kv "host"     "$W${h:-<iran ip>}$N"
         kv "port"     "$W$p$N"
         kv "user"     "$W$SOCKS_USER$N"
         kv "password" "$W$SOCKS_PASS$N"
         blank
         row "$(printf '%s%s%s' "$W" "$(socks_uri "${h:-<iran-ip>}" "$p" "$SOCKS_USER" "$SOCKS_PASS")" "$N")"
         bot; echo
         dim "tcp only - udp associate is not carried over the tunnel"
         pause ;;
      t|T) local tp
         [ "$ROLE" = server ] && tp="$SOCKS_PUB_PORT" || tp="$SOCKS_PORT"
         if [ -z "$tp" ] || [ -z "$SOCKS_USER" ] || [ -z "$SOCKS_PASS" ]; then
           bad "nothing configured yet"; pause; continue
         fi
         echo
         socks_test 127.0.0.1 "$tp" "$SOCKS_USER" "$SOCKS_PASS"
         [ "$ROLE" = server ] && dim "that went out through the tunnel, so the ip should be the kharej one"
         pause ;;
      0|_) return ;;
    esac
  done
}

# ============================================================== TRANSPORT ==
tune_effective() { # profile first, then whatever the operator pinned
  profile_apply "${PROFILE:-balanced}"
  [ -n "${OV_POOL:-}" ]       && P_POOL="$OV_POOL"
  [ -n "${OV_CHANNEL:-}" ]    && P_CHANNEL="$OV_CHANNEL"
  [ -n "${OV_HEARTBEAT:-}" ]  && P_HEARTBEAT="$OV_HEARTBEAT"
  [ -n "${OV_KEEPALIVE:-}" ]  && P_KEEPALIVE="$OV_KEEPALIVE"
  [ -n "${OV_MUXCON:-}" ]     && P_MUXCON="$OV_MUXCON"
  [ -n "${OV_AGGRESSIVE:-}" ] && P_AGGRESSIVE="$OV_AGGRESSIVE"
  [ -n "${OV_RETRY:-}" ]      && P_RETRY="$OV_RETRY"
  [ -n "${OV_DIAL:-}" ]       && P_DIAL="$OV_DIAL"
  [ -n "${OV_NODELAY:-}" ]    && P_NODELAY="$OV_NODELAY"
  [ -n "${OV_FRAME:-}" ]      && P_FRAME="$OV_FRAME"
  [ -n "${OV_RECVBUF:-}" ]    && P_RECVBUF="$OV_RECVBUF"
  [ -n "${OV_STREAMBUF:-}" ]  && P_STREAMBUF="$OV_STREAMBUF"
  [ -n "${OV_MUXVER:-}" ]     && P_MUXVER="$OV_MUXVER"
  return 0
}
ov_count() {
  local n=0 v
  for v in "$OV_POOL" "$OV_CHANNEL" "$OV_HEARTBEAT" "$OV_KEEPALIVE" "$OV_MUXCON" \
           "$OV_AGGRESSIVE" "$OV_RETRY" "$OV_DIAL" "$OV_NODELAY" \
           "$OV_FRAME" "$OV_RECVBUF" "$OV_STREAMBUF" "$OV_MUXVER"; do
    [ -n "$v" ] && n=$((n+1))
  done
  echo "$n"
}
_mark() { [ -n "$1" ] && printf '%s*%s' "$Y" "$N" || printf ' '; }

# name | meta key | current value | shared with the other side?
tune_table() {
  tune_effective
  row "$(printf '%s%2s %-14s %-12s %-8s %s%s' "$D" "#" "setting" "value" "source" "must match" "$N")"
  blank
  row "$(printf '%s 1%s %-14s %s%-12s%s %-8s' "$Y" "$N" "connection_pool" "$W" "$P_POOL" "$N" "$([ -n "$OV_POOL" ] && echo pinned || echo profile)")"
  row "$(printf '%s 2%s %-14s %s%-12s%s %-8s' "$Y" "$N" "channel_size" "$W" "$P_CHANNEL" "$N" "$([ -n "$OV_CHANNEL" ] && echo pinned || echo profile)")"
  row "$(printf '%s 3%s %-14s %s%-12s%s %-8s' "$Y" "$N" "heartbeat" "$W" "$P_HEARTBEAT" "$N" "$([ -n "$OV_HEARTBEAT" ] && echo pinned || echo profile)")"
  row "$(printf '%s 4%s %-14s %s%-12s%s %-8s' "$Y" "$N" "keepalive" "$W" "$P_KEEPALIVE" "$N" "$([ -n "$OV_KEEPALIVE" ] && echo pinned || echo profile)")"
  row "$(printf '%s 5%s %-14s %s%-12s%s %-8s' "$Y" "$N" "mux_con" "$W" "$P_MUXCON" "$N" "$([ -n "$OV_MUXCON" ] && echo pinned || echo profile)")"
  row "$(printf '%s 6%s %-14s %s%-12s%s %-8s' "$Y" "$N" "aggressive" "$W" "$P_AGGRESSIVE" "$N" "$([ -n "$OV_AGGRESSIVE" ] && echo pinned || echo profile)")"
  row "$(printf '%s 7%s %-14s %s%-12s%s %-8s' "$Y" "$N" "retry_interval" "$W" "$P_RETRY" "$N" "$([ -n "$OV_RETRY" ] && echo pinned || echo profile)")"
  row "$(printf '%s 8%s %-14s %s%-12s%s %-8s' "$Y" "$N" "dial_timeout" "$W" "$P_DIAL" "$N" "$([ -n "$OV_DIAL" ] && echo pinned || echo profile)")"
  row "$(printf '%s 9%s %-14s %s%-12s%s %-8s' "$Y" "$N" "nodelay" "$W" "$P_NODELAY" "$N" "$([ -n "$OV_NODELAY" ] && echo pinned || echo profile)")"
  blank
  row "$(printf '%sthese are negotiated - both servers must agree:%s' "$D" "$N")"
  row "$(printf '%s a%s %-14s %s%-12s%s %-8s %syes%s' "$Y" "$N" "mux_framesize" "$W" "$P_FRAME" "$N" "$([ -n "$OV_FRAME" ] && echo pinned || echo profile)" "$R" "$N")"
  row "$(printf '%s b%s %-14s %s%-12s%s %-8s %syes%s' "$Y" "$N" "mux_recvbuf" "$W" "$P_RECVBUF" "$N" "$([ -n "$OV_RECVBUF" ] && echo pinned || echo profile)" "$R" "$N")"
  row "$(printf '%s c%s %-14s %s%-12s%s %-8s %syes%s' "$Y" "$N" "mux_streambuf" "$W" "$P_STREAMBUF" "$N" "$([ -n "$OV_STREAMBUF" ] && echo pinned || echo profile)" "$R" "$N")"
  row "$(printf '%s d%s %-14s %s%-12s%s %-8s %syes%s' "$Y" "$N" "mux_version" "$W" "$P_MUXVER" "$N" "$([ -n "$OV_MUXVER" ] && echo pinned || echo profile)" "$R" "$N")"
}

ov_set() { # <meta-key> <prompt> <validator> [warn-shared]
  local key="$1" prompt="$2" kind="$3" shared="${4:-}" v
  [ -n "$shared" ] && { echo; warn "this value is negotiated - change it on BOTH servers"; }
  ask "$prompt (blank = follow the profile)"
  v="$ANS"
  if [ -z "$v" ]; then
    sed -i "s|^$key=.*|$key=\"\"|" "$TUN_DIR/$TUNE_NAME/meta.conf"
    ok "$key now follows the profile"; return 0
  fi
  case "$kind" in
    int)  [[ "$v" =~ ^[0-9]+$ ]] || { bad "must be a number"; return 1; } ;;
    bool) case "$v" in true|false) ;; *) bad "must be true or false"; return 1 ;; esac ;;
    frame) [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -ge 4096 ] && [ "$v" -le 65535 ] \
             || { bad "frame size must be between 4096 and 65535"; return 1; } ;;
    muxver) case "$v" in 1|2) ;; *) bad "mux version is 1 or 2" ; return 1 ;; esac ;;
  esac
  sed -i "s|^$key=.*|$key=\"$v\"|" "$TUN_DIR/$TUNE_NAME/meta.conf"
  ok "$key pinned to $v"
}

screen_tuning() {
  local name="$1"; TUNE_NAME="$name"
  while :; do
    load_meta "$name"
    header "TUNING - $name"
    top; sect "TRANSPORT"; blank
    kv "transport" "$W$TRANSPORT$N $D(must match the other server)$N"
    kv "profile"   "$W$(profile_name "${PROFILE:-balanced}")$N $D$(profile_hint "${PROFILE:-balanced}")$N"
    kv "pinned"    "$W$(ov_count)$N $D of 13 values overridden$N"
    mid; sect "EFFECTIVE VALUES"
    tune_table
    mid
    item t "Change transport" "and certificate if needed"
    item p "Change profile" "resets every unpinned value"
    item r "Clear all pins" "go back to pure profile"
    item 0 "Back and apply" ""
    bot; echo; getkey
    case "$KEY" in
      1) ov_set OV_POOL "connection_pool" int ;;
      2) ov_set OV_CHANNEL "channel_size" int ;;
      3) ov_set OV_HEARTBEAT "heartbeat" int ;;
      4) ov_set OV_KEEPALIVE "keepalive_period" int ;;
      5) ov_set OV_MUXCON "mux_con" int ;;
      6) ov_set OV_AGGRESSIVE "aggressive_pool (true/false)" bool ;;
      7) ov_set OV_RETRY "retry_interval" int ;;
      8) ov_set OV_DIAL "dial_timeout" int ;;
      9) ov_set OV_NODELAY "nodelay (true/false)" bool ;;
      a|A) ov_set OV_FRAME "mux_framesize" frame shared ;;
      b|B) ov_set OV_RECVBUF "mux_recievebuffer" int shared ;;
      c|C) ov_set OV_STREAMBUF "mux_streambuffer" int shared ;;
      d|D) ov_set OV_MUXVER "mux_version" muxver shared ;;
      t|T) local nt; nt="$(pick_transport)"
           if [ "$ROLE" = server ] && is_tls "$nt"; then
             choose_cert "$TUN_DIR/$name" || { pause; continue; }
             sed -i "s|^TLS_CERT=.*|TLS_CERT=\"$TLS_CERT\"|; s|^TLS_KEY=.*|TLS_KEY=\"$TLS_KEY\"|" "$TUN_DIR/$name/meta.conf"
           fi
           sed -i "s|^TRANSPORT=.*|TRANSPORT=\"$nt\"|" "$TUN_DIR/$name/meta.conf"
           warn "set transport=$nt on the other server too" ; pause ;;
      p|P) local np; np="$(pick_profile)"
           sed -i "s|^PROFILE=.*|PROFILE=\"$np\"|" "$TUN_DIR/$name/meta.conf"
           ok "profile: $(profile_name "$np")"
           [ "$(ov_count)" -gt 0 ] && warn "$(ov_count) pinned value(s) still override it"
           pause ;;
      r|R) sed -i 's|^\(OV_[A-Z]*\)=.*|\1=""|' "$TUN_DIR/$name/meta.conf"
           ok "all pins cleared - the profile is in charge again"; pause ;;
      0|_)
        regen_config "$name" || { bad "config generation failed"; pause; return; }
        load_meta "$name"
        [ "$ROLE" = server ] && make_pair_code "$TUN_DIR/$name" > "$TUN_DIR/$name/pair.code"
        systemctl restart "backhaul@$name" 2>/dev/null; sleep 2
        echo
        [ "$(svc_raw "$name")" = active ] && ok "applied and running" || bad "did not come up"
        [ "$ROLE" = server ] && show_pair_code "$name"
        pause; return ;;
    esac
  done
}

# ================================================================ MANAGE ===
screen_manage() {
  pick_tunnel || return
  local name="$SELECTED"
  while :; do
    if ! tunnel_complete "$name"; then
      header "TUNNEL - $name"
      top; sect "INCOMPLETE"
      row "$(printf '%sthis tunnel was never finished - no usable config%s' "$D" "$N")"
      blank
      item d "Delete it" ""
      item 0 "Back" ""
      bot; echo; getkey
      case "$KEY" in
        d|D) stop_tunnel_hard "$name"
             set_restart_timer "$name" off
             rm -rf "${TUN_DIR:?}/$name"
             ok "removed"; pause; return ;;
        *) return ;;
      esac
    fi
    load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "use Diagnostics to inspect it, or delete the tunnel"; pause; return; }
    header "TUNNEL - $name"
    local _st; _st="$(svc_raw "$name")"
    top; sect "STATUS"; blank
    kv "state"     "$(case "$_st" in active) badge ACTIVE "$BG_OK$W" ;; failed) badge FAILED "$BG_ERR$W" ;; *) badge "${_st:-?}" "$BG_WARN$W" ;; esac)  $D uptime $(svc_uptime_short "$name")$N"
    kv "role"      "$W$([ "$ROLE" = server ] && echo "IRAN (server)" || echo "KHAREJ (client)")$N"
    [ "$ROLE" = server ] && kv "listen" "$W:$PORT$N" || kv "dials" "$W$PEER_IP:$PORT$N"
    kv "transport" "$W$TRANSPORT$N"
    kv "profile"   "$W$(profile_name "${PROFILE:-balanced}")$N $D$(profile_hint "${PROFILE:-balanced}")$N"
    kv "events/1h" "$W$(drops_since "$name" '1 hour ago')$N"
    local _ti _to; read -r _ti _to <<<"$(tunnel_traffic "$name")"
    [ "${_ti:--1}" -ge 0 ] 2>/dev/null && kv "traffic" "$L4$(human_bytes "$_ti") in$N  $L6$(human_bytes "$_to") out$N"
    kv "restart"   "$([ "$RESTART_EVERY" = off ] && printf '%soff%s' "$D" "$N" || printf '%severy %s%s' "$G" "$RESTART_EVERY" "$N")"
    if [ -n "$TLS_CERT" ]; then
      local _d; _d="$(cert_days_left "$TLS_CERT")"
      kv "certificate" "$W$(cert_cn "$TLS_CERT")$N $([ "${_d:-0}" -lt 15 ] 2>/dev/null && printf '%s' "$R" || printf '%s' "$D")${_d}d left$N"
    fi
    [ "$WEB_PORT" != 0 ] && kv "dashboard" "${W}port $WEB_PORT$N"
    if [ "${SOCKS_ENABLE:-false}" = true ]; then
      if [ "$ROLE" = server ]; then
        kv "socks5" "${W}:$SOCKS_PUB_PORT$N $D-> 127.0.0.1:$SOCKS_PORT on kharej$N"
      else
        local _sk; _sk="$(socks_raw "$name")"
        kv "socks5" "${W}127.0.0.1:$SOCKS_PORT$N  $([ "$_sk" = active ] && badge ACTIVE "$BG_OK$W" || badge "${_sk:-down}" "$BG_ERR$W")"
      fi
    fi
    mid; sect "CONTROL"
    item 1 "Start" ""; item 2 "Stop" ""; item 3 "Restart" ""
    if [ "$ROLE" = server ]; then
      mid; sect "PAIRING"
      item p "Pair code" "paste this on the kharej server"
    fi
    mid; sect "CONFIGURE"
    [ "$ROLE" = server ] && item 4 "Ports" "user-facing ports"
    item 5 "Tuning" "transport, profile, advanced"
    item 6 "Endpoint" "port or peer ip"
    item 7 "Scheduled restart" ""
    item 9 "SOCKS5 proxy" "$([ "${SOCKS_ENABLE:-false}" = true ] && echo "on - port ${SOCKS_PUB_PORT:-$SOCKS_PORT}" || echo "off - tunnel as outbound proxy")"
    mid; sect "INSPECT"
    item 8 "Show config" ""
    item s "Speed test" "latency + throughput"
    item L "Logs + connections" "live sockets and events"
    mid; sect "ADVANCED"
    item e "Edit config by hand" "lost on regeneration"
    item d "Delete tunnel" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) systemctl start "backhaul@$name" 2>/dev/null; sleep 1 ;;
      2) systemctl stop "backhaul@$name" 2>/dev/null; sleep 1 ;;
      3) systemctl restart "backhaul@$name" 2>/dev/null; sleep 2 ;;
      4) if [ "$ROLE" = server ]; then screen_ports "$name"
         else info "user ports are configured on the IRAN server"; pause; fi ;;
      5) screen_tuning "$name" ;;
      6) screen_endpoint "$name" ;;
      9) screen_socks "$name" ;;
      s|S) speed_screen "$name" ;;
      l|L) screen_logs "$name" ;;
      7) echo; top; sect "SCHEDULED RESTART"; blank
         item 1 "off" ""; item 2 "1h" ""; item 3 "6h" ""; item 4 "12h" ""
         bot; echo; getkey
         local ev; case "$KEY" in 2) ev=1h ;; 3) ev=6h ;; 4) ev=12h ;; *) ev=off ;; esac
         sed -i "s|^RESTART_EVERY=.*|RESTART_EVERY=\"$ev\"|" "$TUN_DIR/$name/meta.conf"
         ensure_units; set_restart_timer "$name" "$ev"
         ok "scheduled restart: $ev"; pause ;;
      8) header "CONFIG - $name"; sed 's/^/    /' "$TUN_DIR/$name/config.toml"; pause ;;
      p|P) [ "$ROLE" = server ] && show_pair_code "$name" || info "pair codes come from the IRAN side"
           pause ;;
      e|E) local ed=nano; command -v nano >/dev/null 2>&1 || ed=vi
           "$ed" "$TUN_DIR/$name/config.toml"
           if yesno "restart to apply?" y; then
             systemctl restart "backhaul@$name" 2>/dev/null; sleep 2
             [ "$(svc_raw "$name")" = active ] && ok "running" || bad "did not come up"
           fi
           warn "hand edits are lost when the config is regenerated"
           pause ;;
      d|D) ask "type the tunnel name to confirm"
           if [ "$ANS" = "$name" ]; then
             stop_tunnel_hard "$name"
             set_restart_timer "$name" off
             rm -rf "${TUN_DIR:?}/$name"
             ok "deleted"; pause; return
           else bad "name mismatch"; pause; fi ;;
      0|_) return ;;
    esac
  done
}

screen_endpoint() {
  local name="$1"
  load_meta "$name"
  header "ENDPOINT - $name"
  top; sect "CURRENT"; blank
  kv "role" "$W$ROLE$N"
  kv "port" "$W$PORT$N"
  [ "$ROLE" = client ] && kv "iran ip" "$W$PEER_IP$N" || kv "public ip" "$W$PUB_IP$N"
  mid
  item 1 "Change tunnel port" "apply on both servers"
  item 2 "Change ip" ""
  item 0 "Back" ""
  bot; echo; getkey
  case "$KEY" in
    1) ask "new tunnel port" "$PORT"
       valid_port "$ANS" || { bad "invalid port"; pause; return; }
       sed -i "s|^PORT=.*|PORT=\"$ANS\"|" "$TUN_DIR/$name/meta.conf" ;;
    2) ask "new ip" "$([ "$ROLE" = client ] && echo "$PEER_IP" || echo "$PUB_IP")"
       valid_host "$ANS" || { bad "invalid address"; pause; return; }
       if [ "$ROLE" = client ]; then sed -i "s|^PEER_IP=.*|PEER_IP=\"$ANS\"|" "$TUN_DIR/$name/meta.conf"
       else sed -i "s|^PUB_IP=.*|PUB_IP=\"$ANS\"|" "$TUN_DIR/$name/meta.conf"; fi ;;
    *) return ;;
  esac
  regen_config "$name" || { bad "config generation failed"; pause; return; }
  load_meta "$name"
  [ "$ROLE" = server ] && make_pair_code "$TUN_DIR/$name" > "$TUN_DIR/$name/pair.code"
  systemctl restart "backhaul@$name" 2>/dev/null; sleep 2
  echo
  [ "$(svc_raw "$name")" = active ] && ok "applied and running" || bad "did not come up"
  [ "$ROLE" = server ] && { warn "pair code changed - re-pair the kharej side"; show_pair_code "$name"; }
  pause
}

# =============================================================== DASHBOARD =
screen_dashboard() {
  [ -z "$(tunnel_names)" ] && { header "DASHBOARD"; bad "no tunnels yet"; pause; return; }
  while :; do
    header "LIVE DASHBOARD"
    top; sect "TUNNELS"
    row "$(printf '%s%-9s %-6s %-19s %-8s %-6s%s' "$D" "name" "role" "endpoint" "uptime" "events" "$N")"
    blank
    local n nr ep st col
    while read -r n; do
      [ -z "$n" ] && continue
      load_meta "$n"; st="$(svc_raw "$n")"; nr="$(drops_since "$n" '1 hour ago')"
      [ "$ROLE" = server ] && ep="0.0.0.0:$PORT" || ep="$PEER_IP:$PORT"
      [ "${nr:-0}" -gt 5 ] && col="$R" || col="$G"
      row "$(printf '%s %-9s %s%-6s%s %-19s %-8s %s%-6s%s' \
            "$(dot "$st")" "${n:0:9}" "$D" "$([ "$ROLE" = server ] && echo iran || echo kharej)" "$N" \
            "${ep:0:19}" "$(svc_uptime_short "$n")" "$col" "${nr:-0}" "$N")"
    done <<<"$(tunnel_names)"
    mid; sect "LISTENING"
    local socks ln
    socks="$(ss -tulnp 2>/dev/null | grep -iE 'backhaul|microsocks|eris-gost' | awk '{print $1"  "$5}' | head -n 8)"
    if [ -n "$socks" ]; then while read -r ln; do row "$(printf '%s%s%s' "$D" "$ln" "$N")"; done <<<"$socks"
    else row "$(printf '%s(none)%s' "$D" "$N")"; fi
    mid
    row "$(printf '%sload%s %-21s %sestablished%s %s' "$D" "$N" \
          "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)" "$D" "$N" \
          "$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l)")"
    bot
    printf '\n  %s2s refresh  -  any key to exit%s' "$D" "$N"
    read -rsn1 -t 2 _ && { echo; return; }
  done
}



# ========================================================= LIVE CONNECTIONS =
# `ss -tin` reports per-socket bytes and rtt from the kernel, so this is the
# real thing: who is connected right now, how much each one has moved, and how
# the link feels - not a guess from log lines.
conn_rows() { # <port>  ->  peer<TAB>rtt<TAB>sent<TAB>recv
  command -v ss >/dev/null 2>&1 || return 0
  ss -tinH state established "( sport = :$1 )" 2>/dev/null | awk '
    /^[^\t ]/ { peer=$NF; next }
    {
      rtt=""; snt=""; rcv=""
      for (i=1;i<=NF;i++) {
        if ($i ~ /^rtt:/)            { split($i,a,":"); split(a[2],b,"/"); rtt=b[1] }
        if ($i ~ /^bytes_sent:/)     { split($i,a,":"); snt=a[2] }
        if ($i ~ /^bytes_received:/) { split($i,a,":"); rcv=a[2] }
      }
      if (peer != "") printf "%s\t%s\t%s\t%s\n", peer, (rtt==""?"-":rtt), (snt==""?0:snt), (rcv==""?0:rcv)
      peer=""
    }'
}

screen_connections() {
  local name="$1"
  load_meta "$name"
  if [ "$ROLE" != server ]; then
    header "LIVE CONNECTIONS - $name"
    bad "user connections land on the IRAN side"
    dim "this is the kharej client - it dials out and has no user ports"
    pause; return
  fi
  local -A prev_s prev_r
  local first=1
  while :; do
    header "LIVE CONNECTIONS - $name"
    local lport t peer rtt snt rcv key line
    local total=0 tsent=0 trecv=0 rate_s=0 rate_r=0
    top; sect "ESTABLISHED"
    row "$(printf '%s%-21s %-6s %-9s %-9s %-9s%s' "$D" "peer" "port" "sent" "recv" "rate" "$N")"
    blank
    while IFS=$'\t' read -r lport t; do
      valid_port "$lport" || continue
      while IFS=$'\t' read -r peer rtt snt rcv; do
        [ -n "$peer" ] || continue
        total=$((total+1)); tsent=$((tsent+snt)); trecv=$((trecv+rcv))
        key="${peer}_${lport}"
        local ds=0 dr=0
        if [ "$first" -eq 0 ]; then
          ds=$(( snt - ${prev_s[$key]:-$snt} )); dr=$(( rcv - ${prev_r[$key]:-$rcv} ))
          [ "$ds" -lt 0 ] && ds=0; [ "$dr" -lt 0 ] && dr=0
        fi
        prev_s[$key]="$snt"; prev_r[$key]="$rcv"
        rate_s=$((rate_s+ds)); rate_r=$((rate_r+dr))
        [ "$total" -le 12 ] && row "$(printf '%-21s %s%-6s%s %-9s %-9s %s%-9s%s' \
              "${peer:0:21}" "$D" "$lport" "$N" "$(human_bytes "$snt")" "$(human_bytes "$rcv")" \
              "$L4" "$(human_bytes $(( (ds+dr)/2 )))/s" "$N")"
      done < <(conn_rows "$lport")
    done < "$TUN_DIR/$name/ports.list"
    [ "$total" -eq 0 ] && row "$(printf '%sno user is connected right now%s' "$D" "$N")"
    [ "$total" -gt 12 ] && row "$(printf '%s... and %d more%s' "$D" $((total-12)) "$N")"
    mid; sect "TOTAL"
    kv "clients"  "$W$total$N"
    kv "moved"    "$L4$(human_bytes "$tsent") out$N  $L6$(human_bytes "$trecv") in$N"
    if [ "$first" -eq 0 ]; then
      kv "right now" "$W$(human_bytes $((rate_s/2)))/s out$N  $W$(human_bytes $((rate_r/2)))/s in$N"
    else
      kv "right now" "$D measuring...$N"
    fi
    kv "service"  "$(dot "$(svc_raw "$name")") $(svc_raw "$name")   $D uptime $(svc_uptime_short "$name")$N"
    bot
    first=0
    printf '\n  %s2s refresh  -  any key to exit%s' "$D" "$N"
    read -rsn1 -t 2 _ && { echo; return; }
  done
}

screen_logs() {
  local name="$1"
  while :; do
    header "LOGS - $name"
    top; sect "VIEW"
    item 1 "Live connections" "real sockets, bytes, rate"
    item 2 "Live log" "follow the service"
    item 3 "Last 80 lines" ""
    item 4 "Errors only" "last 24h"
    item 5 "Event summary" "what happened and when"
    item 6 "Why is it dropping" "reads the failure pattern"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) screen_connections "$name" ;;
      2) clear; info "ctrl+c to exit"; journalctl -u "backhaul@$name" -f -n 30 --no-pager; pause ;;
      3) header "LOG - $name"; journalctl -u "backhaul@$name" -n 80 --no-pager -o cat | sed 's/^/    /'; pause ;;
      4) header "ERRORS - $name"
         journalctl -u "backhaul@$name" --since '24 hours ago' --no-pager -o cat 2>/dev/null \
           | grep -iE 'error|fail|refused|timeout|disconnect' | tail -n 40 | sed "s/^/    $R/;s/\$/$N/"
         echo; dim "nothing above means no errors in the last 24h"
         pause ;;
      6) header "WHY IS IT DROPPING - $name"
         local L24 cc mux tok lis
         L24="$(journalctl -u "backhaul@$name" --since '24 hours ago' --no-pager -o cat 2>/dev/null)"
         cc="$(grep -ci 'control channel has been closed by the client' <<<"$L24")"
         mux="$(grep -ciE 'mux|smux|frame' <<<"$L24")"
         tok="$(grep -ciE 'invalid token|authentication|unauthorized' <<<"$L24")"
         lis="$(grep -ci 'listener started successfully' <<<"$L24")"
         top; sect "SIGNALS IN THE LAST 24H"; blank
         kv "control closed" "$W$cc$N"
         kv "listener up"    "$W$lis$N"
         kv "token errors"   "$W$tok$N"
         kv "mux mentions"   "$W$mux$N"
         blank
         if [ "${tok:-0}" -gt 0 ]; then
           row "$(printf '%stoken mismatch - compare Config fingerprint%s' "$R" "$N")"
         elif [ "${cc:-0}" -gt 3 ]; then
           row "$(printf '%sthe control channel comes up and the client closes it%s' "$R" "$N")"
           blank
           row "$(printf '%sthat is a negotiation failure, not a network problem:%s' "$D" "$N")"
           row "$(printf '%s  - transport must be identical on both servers%s' "$D" "$N")"
           row "$(printf '%s  - the core version should match end to end%s' "$D" "$N")"
           row "$(printf '%s  - two clients sharing one token fight over it%s' "$D" "$N")"
           blank
           row "$(printf '%srun Transport on both sides and set the same value%s' "$Y" "$N")"
         elif [ "${lis:-0}" -gt 0 ] && [ "${cc:-0}" -eq 0 ]; then
           row "$(printf '%sno negotiation failures - the link is healthy%s' "$G" "$N")"
         else
           row "$(printf '%snot enough signal yet - let it run a while%s' "$D" "$N")"
         fi
         bot; pause ;;
      5) header "EVENT SUMMARY - $name"
         top; sect "LAST 24 HOURS"; blank
         kv "restarts"     "$W$(journalctl -u "backhaul@$name" --since '24 hours ago' --no-pager 2>/dev/null | grep -c 'Started ')$N"
         kv "reconnects"   "$W$(journalctl -u "backhaul@$name" --since '24 hours ago' --no-pager 2>/dev/null | grep -ciE 'reconnect|connection failed|retry')$N"
         kv "errors"       "$W$(journalctl -u "backhaul@$name" --since '24 hours ago' --no-pager 2>/dev/null | grep -ciE 'error|fail')$N"
         blank
         kv "last hour"    "$W$(drops_since "$name" '1 hour ago') event(s)$N"
         kv "last 10 min"  "$W$(drops_since "$name" '10 min ago') event(s)$N"
         bot
         echo; dim "a steady drip means the path is unstable"
         dim "a burst right after a restart means token or transport mismatch"
         pause ;;
      0|_) return ;;
    esac
  done
}

# ============================================================ SPEED TESTS ===
# Latency is measured by opening a TCP connection to a user port on IRAN. That
# connection travels the whole tunnel to the panel on KHAREJ and back, so the
# time it takes is the real end-to-end round trip - no tooling, no traffic.
tcp_probe_ms() { # <host> <port>
  local h="$1" p="$2" t0 t1
  t0="$(date +%s%N)"
  if timeout 4 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null; then
    t1="$(date +%s%N)"; echo $(( (t1 - t0) / 1000000 ))
  else echo -1; fi
}
rep_bar() { local v="$1" max="$2" w="$3" f
  [ "${max:-0}" -le 0 ] && max=1
  f=$(( v * w / max )); [ "$f" -gt "$w" ] && f="$w"; [ "$f" -lt 0 ] && f=0
  printf '%s%s%s%s' "$L4" "$(rep '#' "$f")" "$D" "$(rep '.' $((w-f)))"
}

# ---- KHAREJ side: a throwaway data source the IRAN side can pull from -------
speed_responder() {
  local port secs
  header "SPEED RESPONDER - KHAREJ"
  top; sect "WHAT THIS DOES"
  row "$(printf '%sopens a temporary port on THIS kharej server that just%s' "$D" "$N")"
  row "$(printf '%ssends zeros. the IRAN side pulls from it through the%s' "$D" "$N")"
  row "$(printf '%stunnel and measures the real throughput.%s' "$D" "$N")"
  blank
  row "$(printf '%sadd the same port on IRAN, then run the speed test there%s' "$D" "$N")"
  bot; echo
  command -v python3 >/dev/null 2>&1 || { bad "python3 is required for the responder"; pause; return; }
  ask "responder port" "19999"; port="$ANS"
  valid_port "$port" || { bad "invalid port"; pause; return; }
  port_in_use_tcp "$port" && { bad "port $port is already in use"; pause; return; }
  ask "keep it open for how many seconds" "120"; secs="${ANS:-120}"
  [[ "$secs" =~ ^[0-9]+$ ]] || secs=120
  echo
  info "listening on 127.0.0.1:$port for ${secs}s - press ctrl+c to stop early"
  dim "on IRAN: add port $port to this tunnel, then Speed test > active"
  echo
  timeout "$secs" python3 - "$port" <<'PYSRV'
import socket, sys, threading
port = int(sys.argv[1])
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port)); srv.listen(16)
chunk = b"\0" * 262144
def serve(c):
    try:
        with c:
            while True: c.sendall(chunk)
    except Exception: pass
while True:
    try:
        c, _ = srv.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()
    except Exception: break
PYSRV
  echo; ok "responder closed"
  pause
}

# ---- IRAN side --------------------------------------------------------------
speed_screen() {
  local name="$1"
  load_meta "$name"
  while :; do
    header "SPEED - $name"
    top; sect "OPTIONS"
    row "$(printf '%spassive reads the live counters and disturbs nothing%s' "$D" "$N")"
    row "$(printf '%sactive pulls real data and needs a responder on kharej%s' "$D" "$N")"
    bot
    top
    item 1 "Latency" "round trip through the tunnel"
    item 2 "Passive throughput" "live user traffic"
    item 3 "Active throughput" "the ceiling - restarts it"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) speed_latency "$name" ;;
      2) speed_passive "$name" ;;
      3) speed_active  "$name" ;;
      0|_) return ;;
    esac
  done
}

speed_latency() {
  local name="$1" port ms i ok_n=0 sum=0 min=999999 max=0 prev=-1 jit=0 jn=0 d
  load_meta "$name"
  [ "$ROLE" = server ] || { bad "run this on the IRAN side"; pause; return; }
  port="$(awk -F'\t' 'NR==1{print $1}' "$TUN_DIR/$name/ports.list" 2>/dev/null)"
  valid_port "$port" || { bad "no user port to probe"; pause; return; }
  header "LATENCY - $name"
  info "probing 127.0.0.1:$port through the tunnel"
  echo
  for ((i=1;i<=10;i++)); do
    ms="$(tcp_probe_ms 127.0.0.1 "$port")"
    if [ "$ms" -ge 0 ]; then
      ok_n=$((ok_n+1)); sum=$((sum+ms))
      [ "$ms" -lt "$min" ] && min="$ms"; [ "$ms" -gt "$max" ] && max="$ms"
      if [ "$prev" -ge 0 ]; then d=$((ms-prev)); [ "$d" -lt 0 ] && d=$((-d)); jit=$((jit+d)); jn=$((jn+1)); fi
      prev="$ms"
      printf '\r  probe %2d/10   %s%s ms%s      ' "$i" "$G" "$ms" "$N"
    else printf '\r  probe %2d/10   %sfailed%s      ' "$i" "$R" "$N"; fi
    sleep 0.3
  done
  echo; echo
  top; sect "RESULT"; blank
  if [ "$ok_n" -eq 0 ]; then
    row "$(printf '%severy probe failed - the tunnel is not passing data%s' "$R" "$N")"
  else
    kv "latency" "$W$((sum/ok_n)) ms$N  $D min $min  max $max$N"
    [ "$jn" -gt 0 ] && kv "jitter" "$W$((jit/jn)) ms$N"
    kv "loss"    "$(if [ "$ok_n" -eq 10 ]; then printf '%s0%%%s' "$G" "$N"; else printf '%s%d%%%s' "$R" $(( (10-ok_n)*10 )) "$N"; fi)"
    kv ""        "$(rep_bar "$((sum/ok_n))" 300 34)$N"
  fi
  bot; pause
}

speed_passive() {
  local name="$1" win i1 o1 i2 o2 din dout
  load_meta "$name"
  header "PASSIVE THROUGHPUT - $name"
  read -r i1 o1 <<<"$(tunnel_traffic "$name")"
  if [ "${i1:--1}" -lt 0 ]; then
    bad "traffic cannot be measured on this side"
    dim "counters live on the IRAN server, where the user ports are"
    pause; return
  fi
  ask "sample for how many seconds" "10"; win="${ANS:-10}"
  [[ "$win" =~ ^[0-9]+$ ]] && [ "$win" -ge 2 ] || win=10
  info "sampling for ${win}s"
  sleep "$win"
  read -r i2 o2 <<<"$(tunnel_traffic "$name")"
  din=$(( (i2 - i1) / win )); dout=$(( (o2 - o1) / win ))
  [ "$din" -lt 0 ] && din=0; [ "$dout" -lt 0 ] && dout=0
  echo; top; sect "RESULT"; blank
  kv "down now" "$W$(human_bytes "$din")/s$N   $D$(( din * 8 / 1000000 )) Mbps$N"
  kv "up now"   "$W$(human_bytes "$dout")/s$N   $D$(( dout * 8 / 1000000 )) Mbps$N"
  kv "total in" "$W$(human_bytes "$i2")$N"
  kv "total out" "$W$(human_bytes "$o2")$N"
  blank
  row "$(printf '%sthis is real user traffic, not a benchmark%s' "$D" "$N")"
  row "$(printf '%scounters reset when the tunnel restarts%s' "$D" "$N")"
  bot; pause
}

speed_active() {
  local name="$1" dir="$TUN_DIR/$1" port secs added=0 t0 t1 bytes rate
  load_meta "$name"
  [ "$ROLE" = server ] || { bad "run this on the IRAN side"; pause; return; }
  header "ACTIVE THROUGHPUT - $name"
  top; sect "BEFORE YOU START"
  row "$(printf '%s1. on the KHAREJ server run Speed responder first%s' "$Y" "$N")"
  row "$(printf '%s2. this adds a temporary port and RESTARTS the tunnel%s' "$Y" "$N")"
  row "$(printf '%s   every connected user drops for a moment%s' "$D" "$N")"
  bot; echo
  yesno "the responder is running on kharej and you accept the restart?" n || return
  ask "responder port" "19999"; port="$ANS"
  valid_port "$port" || { bad "invalid port"; pause; return; }
  ask "measure for how many seconds" "10"; secs="${ANS:-10}"
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 3 ] || secs=10

  if ! awk -F'\t' -v x="$port" '$1==x{f=1} END{exit !f}' "$dir/ports.list" 2>/dev/null; then
    printf '%s\t-\n' "$port" >> "$dir/ports.list"; added=1
    regen_config "$name" && acct_sync "$name" >/dev/null 2>&1
    systemctl restart "backhaul@$name" 2>/dev/null; sleep 3
    ok "temporary port $port added"
  fi

  info "pulling data through the tunnel for ${secs}s"
  bytes="$(timeout $((secs+3)) bash -c '
      exec 3<>/dev/tcp/127.0.0.1/'"$port"' || exit 1
      timeout '"$secs"' cat <&3 2>/dev/null | wc -c' 2>/dev/null)"
  bytes="${bytes:-0}"

  if [ "$added" -eq 1 ]; then
    grep -v -P "^$port\t" "$dir/ports.list" > "$dir/ports.tmp" 2>/dev/null && mv -f "$dir/ports.tmp" "$dir/ports.list"
    regen_config "$name"
    systemctl restart "backhaul@$name" 2>/dev/null; sleep 2
    dim "temporary port removed and the tunnel restored"
  fi

  echo; top; sect "RESULT"; blank
  if [ "${bytes:-0}" -lt 1024 ]; then
    row "$(printf '%sno data came through%s' "$R" "$N")"; blank
    row "$(printf '%s  - is the responder still running on kharej?%s' "$D" "$N")"
    row "$(printf '%s  - does it listen on 127.0.0.1:%s there?%s' "$D" "$port" "$N")"
  else
    rate=$(( bytes / secs ))
    kv "transferred" "$W$(human_bytes "$bytes")$N in ${secs}s"
    kv "throughput"  "$W$(human_bytes "$rate")/s$N   $D$(( rate * 8 / 1000000 )) Mbps$N"
    kv ""            "$(rep_bar $(( rate * 8 / 1000000 )) 200 34)$N"
  fi
  bot; pause
}

# ============================================================ DIAGNOSTICS ==
tcp_probe_ms() {
  local host="$1" port="$2" t0 t1
  t0="$(date +%s%N)"
  if timeout 4 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    t1="$(date +%s%N)"; echo $(( (t1 - t0) / 1000000 ))
  else echo -1; fi
}

link_test() {
  local name="$1" maxs t0 start el d first last=0
  header "LINK TEST - $name"
  load_meta "$name"
  top; sect "HOW TO READ IT"
  row "$(printf '%scounts reconnect events after a fresh start%s' "$D" "$N")"
  row "$(printf '%s   many in the first minute -> token or transport%s' "$D" "$N")"
  row "$(printf '%s   steady drip over time    -> the path is unstable%s' "$D" "$N")"
  bot; echo
  ask "watch for how many seconds" "180"
  maxs="${ANS:-180}"; [[ "$maxs" =~ ^[0-9]+$ ]] || maxs=180
  info "restarting and watching - press any key to stop"
  t0="$(date '+%Y-%m-%d %H:%M:%S')"
  systemctl restart "backhaul@$name" 2>/dev/null
  start="$(date +%s)"; echo
  while :; do
    el=$(( $(date +%s) - start ))
    [ "$el" -ge "$maxs" ] && break
    d="$(drops_since "$name" "$t0")"; d="${d:-0}"; last="$d"
    [ -z "$first" ] && [ "$d" -gt 0 ] && first="$el"
    if [ -z "$first" ]; then printf '\r  %sclean%s   %02d:%02d        ' "$G" "$N" $((el/60)) $((el%60))
    else printf '\r  %sevents %-3s%s %02d:%02d  %sfirst at %ss%s  ' "$Y" "$d" "$N" $((el/60)) $((el%60)) "$D" "$first" "$N"; fi
    read -rsn1 -t 2 _ && { echo; info "stopped early"; break; }
  done
  el=$(( $(date +%s) - start )); echo; echo
  top; sect "RESULT"; blank
  kv "watched"     "$W${el}s$N"
  kv "events"      "$W$last$N"
  kv "first event" "$W$([ -n "$first" ] && echo "${first}s" || echo none)$N"
  blank
  if [ -z "$first" ]; then row "$(printf '%sno reconnect in the window - looks healthy%s' "$G" "$N")"
  elif [ "$last" -gt 10 ]; then
    row "$(printf '%sreconnect loop%s' "$R" "$N")"; blank
    row "$(printf '%s  - token must be identical on both servers%s' "$D" "$N")"
    row "$(printf '%s  - transport must be identical on both servers%s' "$D" "$N")"
    row "$(printf '%s  - is TCP/%s open for the kharej server?%s' "$D" "$PORT" "$N")"
  else
    row "$(printf '%sa few events - usually fine%s' "$Y" "$N")"
  fi
  bot; pause
}

fingerprint_line() {
  local name="$1" th
  load_meta "$name" >/dev/null 2>&1 || return 1
  th="$(printf '%s' "$TOKEN" | sha256sum 2>/dev/null | cut -c1-10)"
  printf 'port=%s transport=%s profile=%s token=%s core=%s' \
    "$PORT" "$TRANSPORT" "${PROFILE:-balanced}" "${th:-?}" "$(core_version_short)"
}
screen_fingerprint() {
  header "CONFIG FINGERPRINT"
  top; sect "MUST MATCH ON BOTH SERVERS"
  row "$(printf '%srun on the other server and compare the two lines%s' "$D" "$N")"
  row "$(printf '%sthe token is hashed - the secret is never printed%s' "$D" "$N")"
  bot; echo
  local n
  while read -r n; do
    [ -z "$n" ] && continue
    load_meta "$n"
    printf '  %s%-10s%s %s(%s)%s\n' "$W" "$n" "$N" "$D" "$([ "$ROLE" = server ] && echo iran || echo kharej)" "$N"
    printf '  %s%s%s\n\n' "$C" "$(fingerprint_line "$n")" "$N"
  done <<<"$(tunnel_names)"
  [ -z "$(tunnel_names)" ] && dim "(no tunnels)"
  warn "port, transport and token must be identical end to end"
  pause
}

health_check() {
  header "HEALTH CHECK"
  [ -x "$BIN_PATH" ] && ok "core: $(core_version_short)" || bad "core binary missing"
  [ -f "$UNIT_FILE" ] && ok "systemd template" || bad "systemd template missing"
  local l; l="$(tunnel_names)"
  [ -z "$l" ] && { echo; warn "no tunnels configured"; return; }
  local n
  while read -r n; do
    [ -z "$n" ] && continue
    echo; printf '  %s%s%s\n' "$D" "$(rep '─' $((UIW+2)))" "$N"
    load_meta "$n"
    printf '  %s%s%s %s(%s)%s\n' "$W" "$n" "$N" "$D" "$([ "$ROLE" = server ] && echo iran || echo kharej)" "$N"
    [ "$(svc_raw "$n")" = active ] && ok "service active" || bad "service not active"
    systemctl is-enabled --quiet "backhaul@$n" 2>/dev/null && ok "enabled on boot" || warn "not enabled on boot"
    if [ "$ROLE" = server ]; then
      ss -tln 2>/dev/null | grep -qE "[:.]$PORT\b" && ok "tunnel port $PORT is listening" || bad "tunnel port $PORT NOT listening"
      local lp t miss=0
      while IFS=$'\t' read -r lp t; do
        [ -z "$lp" ] && continue
        ss -tln 2>/dev/null | grep -qE "[:.]$lp\b" || { bad "user port $lp not listening"; miss=1; }
      done < "$TUN_DIR/$n/ports.list"
      [ "$miss" -eq 0 ] && ok "all user ports listening"
    else
      local ms; ms="$(tcp_probe_ms "$PEER_IP" "$PORT")"
      [ "$ms" -ge 0 ] 2>/dev/null && ok "iran server reachable (${ms}ms)" || bad "cannot reach $PEER_IP:$PORT"
    fi
    if [ -n "$TLS_CERT" ]; then
      local cd; cd="$(cert_days_left "$TLS_CERT")"
      if [ "${cd:--1}" -lt 0 ] 2>/dev/null; then bad "certificate expired or unreadable"
      elif [ "$cd" -lt 15 ]; then warn "certificate expires in ${cd}d"
      else ok "certificate valid for ${cd}d"; fi
    fi
    if [ "${SOCKS_ENABLE:-false}" = true ] && [ "$ROLE" = client ]; then
      [ "$(socks_raw "$n")" = active ] && ok "socks5 proxy active ($(socks_provider_name))" \
        || bad "socks5 proxy not active - journalctl -u eris-socks@$n"
      ss -tln 2>/dev/null | grep -qE "127\.0\.0\.1:$SOCKS_PORT\b" \
        && ok "socks5 listening on 127.0.0.1:$SOCKS_PORT" \
        || bad "socks5 NOT listening on 127.0.0.1:$SOCKS_PORT"
    fi
    local d; d="$(drops_since "$n" '1 hour ago')"
    if [ "${d:-0}" -eq 0 ]; then ok "no reconnect events in the last hour"
    elif [ "${d:-0}" -le 5 ]; then warn "$d event(s) in the last hour"
    else bad "$d events in the last hour - run the link test"; fi
  done <<<"$l"
  echo
}

screen_diag() {
  while :; do
    header "DIAGNOSTICS"
    top; sect "LOGS"; blank
    item 1 "Live log" ""
    item 2 "Last 60 lines" ""
    mid; sect "TESTS"
    item 3 "Health check" "all tunnels"
    item 4 "Link test" "reconnect counter"
    item 5 "Config fingerprint" "compare both servers"
    item 6 "Reach iran server" "kharej side only"
    item r "Speed responder" "run on kharej"
    mid; sect "SYSTEM"
    item l "Toggle debug logs" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) pick_tunnel && { clear; info "ctrl+c to exit"; journalctl -u "backhaul@$SELECTED" -f -n 30 --no-pager; }; pause ;;
      2) pick_tunnel && { header "LOG - $SELECTED"; journalctl -u "backhaul@$SELECTED" -n 60 --no-pager -o cat | sed 's/^/    /'; }; pause ;;
      3) health_check; pause ;;
      4) pick_tunnel && link_test "$SELECTED" ;;
      5) screen_fingerprint ;;
      6) pick_tunnel || continue
         load_meta "$SELECTED"
         [ "$ROLE" != client ] && { bad "run this on the kharej side"; pause; continue; }
         header "REACH - $SELECTED"
         info "probing $PEER_IP:$PORT"
         local i ms okn=0 sum=0
         for i in 1 2 3 4 5; do
           ms="$(tcp_probe_ms "$PEER_IP" "$PORT")"
           if [ "$ms" -ge 0 ]; then okn=$((okn+1)); sum=$((sum+ms)); ok "probe $i: ${ms}ms"
           else bad "probe $i: failed"; fi
           sleep 0.3
         done
         echo
         [ "$okn" -gt 0 ] && ok "average $((sum/okn))ms over $okn/5" || bad "iran server unreachable on $PORT"
         pause ;;
      r|R) speed_responder ;;
      l|L) pick_tunnel || continue
           load_meta "$SELECTED"
           local nl; [ "$LOGLEVEL" = debug ] && nl=info || nl=debug
           sed -i "s|^LOGLEVEL=.*|LOGLEVEL=\"$nl\"|" "$TUN_DIR/$SELECTED/meta.conf"
           regen_config "$SELECTED"; systemctl restart "backhaul@$SELECTED" 2>/dev/null
           ok "log level: $nl"; pause ;;
      0|_) return ;;
    esac
  done
}

# ================================================================= UPDATE ==
screen_update() {
  while :; do
    header "UPDATE"
    top; sect "VERSIONS"; blank
    kv "core"   "$W$(core_version_short)$N"
    kv "script" "${W}v$SCRIPT_VER$N"
    kv "source" "$D$(cat "$UPDATE_URL_FILE" 2>/dev/null || echo 'not set')$N"
    mid
    item 1 "Core" "install / update"
    item 2 "Update script" "from source url"
    item 3 "Set source url" ""
    item 4 "Install as command" "run as: eristun2"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) screen_core ;;
      2) update_script; pause ;;
      3) ask "raw url"; [ -n "$ANS" ] && { ensure_dirs; echo "$ANS" > "$UPDATE_URL_FILE"; ok "saved"; }; pause ;;
      4) install -m 0755 "$SELF_PATH" /usr/local/bin/eristun2 && ok "run: eristun2" || bad "failed"; pause ;;
      0|_) return ;;
    esac
  done
}
update_script() {
  local url tmp nv
  url="$(cat "$UPDATE_URL_FILE" 2>/dev/null)"
  [ -z "$url" ] && { bad "no source url set"; return; }
  tmp="$(mktemp)"
  info "downloading"
  curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$url" || { bad "download failed"; rm -f "$tmp"; return; }
  grep -q 'ERIS-TUNNEL-2-SCRIPT' "$tmp" || { bad "not a Backhaul manager script - aborted"; rm -f "$tmp"; return; }
  bash -n "$tmp" 2>/dev/null || { bad "syntax errors - aborted"; rm -f "$tmp"; return; }
  nv="$(grep -m1 '^SCRIPT_VER=' "$tmp" | cut -d'"' -f2)"
  cp -f "$SELF_PATH" "$SELF_PATH.bak" 2>/dev/null
  install -m 0755 "$tmp" "$SELF_PATH"; rm -f "$tmp"
  ok "updated to v${nv:-?} - backup at $SELF_PATH.bak"
  sleep 1; exec bash "$SELF_PATH"
}

screen_uninstall() {
  header "UNINSTALL"
  warn "removes every tunnel, service and the core binary"
  echo; ask "type UNINSTALL to confirm"
  [ "$ANS" = UNINSTALL ] || { info "cancelled"; pause; return; }
  local n
  for n in $(tunnel_names); do
    stop_tunnel_hard "$n"
    set_restart_timer "$n" off
  done
  rm -f "$UNIT_FILE" "$RS_UNIT" "$RS_TIMER" "$SOCKS_UNIT"; systemctl daemon-reload 2>/dev/null
  rm -f "$BIN_PATH" "$BIN_PATH.bak" "$GOST_BIN"
  rm -rf "$BASE_DIR"
  ok "uninstalled"
  pause; exit 0
}

# =============================================================== MAIN MENU =
main_menu() {
  while :; do
    header
    local tot run
    tot="$(tunnel_count)"
    run="$(systemctl list-units 'backhaul@*' --state=running --no-legend 2>/dev/null | grep -c .)"
    top
    row "$(printf '%s%s%s tunnels   %s%s%s running   %s%s%s' "$W$BD" "$tot" "$N" "$G$BD" "$run" "$N" "$D" \
        "$([ -x "$BIN_PATH" ] && echo 'core ready' || echo 'core missing')" "$N")"
    mid; sect "SETUP"
    item 1 "Core" "install / update backhaul"
    item 2 "New tunnel - IRAN" "server, makes pair code"
    item 3 "New tunnel - KHAREJ" "client, takes pair code"
    mid; sect "OPERATE"
    item 4 "Manage tunnels" "ports, transport, endpoint"
    item 5 "Dashboard" ""
    item 6 "Diagnostics" "logs and tests"
    mid; sect "MAINTENANCE"
    item 7 "Update" ""
    item 8 "Uninstall" ""
    item 0 "Exit" ""
    bot; echo; getkey
    case "$KEY" in
      1) screen_core ;;      2) screen_new_iran ;;   3) screen_new_kharej ;;
      4) screen_manage ;;    5) screen_dashboard ;;  6) screen_diag ;;
      7) screen_update ;;    8) screen_uninstall ;;
      0|q|Q) clear; printf '  %sEris Tunnel 2%s  %s%s%s\n\n' "$C" "$N" "$D" "$DEV_ID" "$N"; exit 0 ;;
    esac
  done
}

need_root
install_deps
ensure_dirs
trap on_interrupt INT TERM
sweep_partials
ensure_units
main_menu
