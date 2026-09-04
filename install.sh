#!/usr/bin/env bash
#
# omakeylight installer — grants unprivileged write access to the keyboard
# backlight's auto-off delay, and links the CLI into ~/.local/bin.
#
# Brightness needs none of this: brightnessctl reaches it through
# systemd-logind. Only the timeout attribute is root-only by default.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RULE_SRC="$REPO_DIR/udev/99-omakeylight.rules"
RULE_DST="/etc/udev/rules.d/99-omakeylight.rules"
BIN_DIR="$HOME/.local/bin"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
ok()   { printf '  ✓ %s\n' "$*"; }

# Prefer sudo when there is a terminal to type a password into; fall back to
# pkexec for GUI/agent contexts where no TTY exists.
run_privileged() {
  if [[ -t 0 && -t 1 ]] && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  else
    warn "need root to install the udev rule, but neither sudo nor pkexec is usable"
    return 1
  fi
}

say "omakeylight"

# --- 1. detect the hardware -------------------------------------------------

if ! device=$("$REPO_DIR/bin/omakeylight-ctl" device 2>/dev/null); then
  warn "no keyboard backlight found under /sys/class/leds"
  warn "the bar widget will stay hidden on this machine"
  exit 1
fi
ok "found $device"

# --- 2. link the CLI --------------------------------------------------------

mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/bin/omakeylight-ctl" "$BIN_DIR/omakeylight-ctl"
ok "linked omakeylight-ctl into $BIN_DIR"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH" ;;
esac

# --- 3. udev rule for the timeout ------------------------------------------

if [[ ! -e /sys/class/leds/$device/stop_timeout ]]; then
  ok "this driver exposes no adjustable timeout — brightness only, nothing to install"
  exit 0
fi

if [[ -w /sys/class/leds/$device/stop_timeout ]]; then
  ok "timeout is already writable"
else
  if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
    warn "you are not in the 'wheel' group; the rule grants access to wheel"
    warn "either join wheel, or edit the group in $RULE_SRC before installing"
  fi
  say "Installing $RULE_DST (needs root)"
  run_privileged install -m 0644 "$RULE_SRC" "$RULE_DST"
  run_privileged udevadm control --reload-rules
  run_privileged udevadm trigger --subsystem-match=leds --action=change
  sleep 1
  if [[ -w /sys/class/leds/$device/stop_timeout ]]; then
    ok "timeout is now writable without root"
  else
    warn "rule installed, but the attribute is still read-only — a reboot may be needed"
  fi
fi

# --- 4. learn which delays this driver accepts ------------------------------

# Probing writes to the hardware, so it happens once, here, rather than every
# time the bar widget polls. The result is cached under ~/.cache/omakeylight.
if [[ -w /sys/class/leds/$device/stop_timeout ]]; then
  if delays=$("$REPO_DIR/bin/omakeylight-ctl" probe 2>/dev/null); then
    ok "supported delays: $delays"
  else
    warn "could not probe supported delays; the widget will offer the default list"
  fi
fi

# --- 5. report --------------------------------------------------------------

echo
"$REPO_DIR/bin/omakeylight-ctl" status | sed 's/^/  /'
echo
say "Add the widget to your bar:"
echo "  omarchy plugin enable omakeylight.keylight --section right"
