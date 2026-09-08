#!/usr/bin/env bash
# ==============================================================================
#  ERIS TUNNEL 2 - installer
#  curl -fsSL https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/install.sh | bash
# ==============================================================================
set -u

RAW="https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/eris-tunnel-2.sh"
DEST="/usr/local/bin/eristun2"
BASE_DIR="/etc/eris-tunnel-2"

R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; C=$'\e[38;5;81m'; D=$'\e[38;5;244m'; N=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$1" >&2; }
info() { printf '  %s·%s %s\n' "$C" "$N" "$1"; }

echo
printf '  %sERIS TUNNEL 2%s  installer\n' "$C" "$N"
echo

# --- root -------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  bad "must run as root - try again with sudo"
  exit 1
fi

# --- dependencies -----------------------------------------------------------
need_pkgs=""
for c in curl tar; do
  command -v "$c" >/dev/null 2>&1 || need_pkgs="$need_pkgs $c"
done
if [ -n "$need_pkgs" ]; then
  info "installing:$need_pkgs"
  if   command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq $need_pkgs
  elif command -v dnf     >/dev/null 2>&1; then dnf install -y -q $need_pkgs
  elif command -v yum     >/dev/null 2>&1; then yum install -y -q $need_pkgs
  elif command -v apk     >/dev/null 2>&1; then apk add --no-cache $need_pkgs
  else bad "install these manually:$need_pkgs"; exit 1; fi
fi

# --- download ---------------------------------------------------------------
tmp="$(mktemp)" || { bad "cannot create temp file"; exit 1; }
trap 'rm -f "$tmp"' EXIT

info "downloading manager"
if ! curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$RAW"; then
  bad "download failed - check the server's connectivity to raw.githubusercontent.com"
  exit 1
fi

# --- verify -----------------------------------------------------------------
# Strip any CR that a Windows editor may have introduced upstream.
sed -i 's/\r$//' "$tmp"

grep -q 'ERIS-TUNNEL-2-SCRIPT' "$tmp" || { bad "downloaded file is not the manager"; exit 1; }
bash -n "$tmp" 2>/dev/null || { bad "downloaded file has syntax errors"; exit 1; }

ver="$(grep -m1 '^SCRIPT_VER=' "$tmp" | cut -d'"' -f2)"

# --- install ----------------------------------------------------------------
mkdir -p "$BASE_DIR" && chmod 700 "$BASE_DIR"
[ -f "$DEST" ] && cp -f "$DEST" "$DEST.bak" 2>/dev/null
install -m 0755 "$tmp" "$DEST" || { bad "could not write $DEST"; exit 1; }
echo "$RAW" > "$BASE_DIR/update.url"

ok "installed v${ver:-?} to $DEST"
echo
printf '  %srun it with:%s  eristun2\n' "$D" "$N"
echo

# --- launch -----------------------------------------------------------------
# stdin is the curl pipe here; the manager reattaches it to the terminal itself.
if [ -r /dev/tty ]; then
  exec "$DEST" </dev/tty
fi
