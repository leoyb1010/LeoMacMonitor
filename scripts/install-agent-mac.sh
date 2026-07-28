#!/bin/sh
#
#  File:      install-agent-mac.sh
#  Created:   2026-07-22
#  Updated:   2026-07-24
#  Developer: Leo Yuan
#  Overview:  One-line installer for the headless LeoMacMonitor Mac agent (leomac-agent-mac). Fetches
#             the universal binary from the latest GitHub release, installs it under the user's own
#             ~/.local/bin, and registers a LaunchAgent that serves this Mac's metrics on :7799 over
#             TLS + mDNS. Ends by printing ONE pairing link to paste into another Mac's LeoMacMonitor
#             ("Add machine…"). For headless Mac minis / Studios; on a Mac you actually use, the
#             app's Settings → "Share this Mac" toggle is simpler.
#  Notes:     POSIX sh. NO SUDO by default: a LaunchAgent runs in the user's own session, so root
#             buys nothing — which also lets `ssh box 'curl … | sh'` finish unattended. Set
#             LEOMAC_BIN=/usr/local/bin/leomac-agent-mac for a system-wide install; the script
#             escalates only when the chosen directory isn't writable. Other overrides: LEOMAC_PORT
#             (7799), LEOMAC_REPO (leoyuan/LeoMacMonitor), LEOMAC_LOCAL_BIN (install a local binary —
#             release-less testing / offline). LaunchAgent = per-user session; for a truly login-less
#             box, load it as a LaunchDaemon instead. Re-installs unload the agent BEFORE replacing
#             the binary — overwriting a live executable aborts the running process.
#
set -eu

REPO="${LEOMAC_REPO:-leoyb1010/LeoMacMonitor}"
BIN="${LEOMAC_BIN:-$HOME/.local/bin/leomac-agent-mac}"
PORT="${LEOMAC_PORT:-7799}"
LABEL="com.leoyuan.leomac-agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[ "$(uname -s)" = "Darwin" ] || { echo "This installer is for macOS. Use install-agent.sh on Linux."; exit 1; }

# --- uninstall: stop + unregister the agent and remove everything it created (issue #34) ---
if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "uninstall" ]; then
  echo "▸ Removing the LeoMacMonitor Mac agent…"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  rm -f "$BIN"
  # Token + self-signed cert + the private keychain that prompted for a password.
  rm -rf "$HOME/Library/Application Support/LeoMacMonitor/agent"
  rm -f /tmp/leomac-agent-mac.log
  echo "✓ Uninstalled. (The LeoMacMonitor app, if installed, is untouched.)"
  echo "  On the viewer Mac, right-click this machine in the Fleet sidebar → Remove machine."
  exit 0
fi

# Escalate only when the chosen directory isn't ours (i.e. the caller opted into a system path).
BINDIR="$(dirname "$BIN")"
mkdir -p "$BINDIR" 2>/dev/null || true
if [ -w "$BINDIR" ]; then SUDO=""; else SUDO="sudo"; fi

# --- stop any running agent BEFORE swapping its binary (overwriting a live executable aborts it) ---
launchctl unload "$PLIST" 2>/dev/null || true

# --- obtain the binary (local file or latest release) ---
if [ -n "${LEOMAC_LOCAL_BIN:-}" ]; then
  echo "▸ Installing local binary: $LEOMAC_LOCAL_BIN"
  $SUDO install -m 0755 "$LEOMAC_LOCAL_BIN" "$BIN"
else
  URL="https://github.com/$REPO/releases/latest/download/leomac-agent-mac"
  echo "▸ Downloading leomac-agent-mac (universal) from $URL …"
  tmp="$(mktemp)"
  curl -fsSL "$URL" -o "$tmp"
  $SUDO install -m 0755 "$tmp" "$BIN"
  rm -f "$tmp"
fi
echo "  installed: $BIN ($("$BIN" --version))"

# --- LaunchAgent (auto-start, restart on crash) ---
echo "▸ Registering LaunchAgent (port: $PORT)…"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>--serve</string>
    <string>:$PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>/tmp/leomac-agent-mac.log</string>
</dict>
</plist>
PLIST

launchctl load "$PLIST"

echo "✓ leomac-agent-mac is running on :$PORT and will auto-start at login."
sleep 1
echo
echo "──────────────────────────────────────────────────────────────────"
echo "  Paste this ONE line into LeoMacMonitor → Add machine… on your Mac:"
echo
echo "      $("$BIN" --pair-url --serve ":$PORT")"
echo
echo "  It carries this Mac's name, address and pairing token — one paste"
echo "  and it joins your Fleet, encrypted. (Over Tailscale/VPN, swap the"
echo "  host for that network's address.)"
echo "──────────────────────────────────────────────────────────────────"
