#!/bin/sh
set -eu

# ──────────────────────────────────────────────
# KSO Agent Uninstaller (distribution)
# Stops and removes the kso-agent systemd service and all files
# created by install.sh.
#
# POSIX-compatible (works with: curl ... | sh)
#
# Usage:
#   curl -fsSL https://cdn.kso-services.com/uninstall-agent.sh | sudo sh
# ──────────────────────────────────────────────

BINARY_DST="/usr/local/bin/kso-agent"
CONFIG_DIR="/etc/kso-agent"
SERVICE_NAME="kso-agent"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}.service"
AGENT_USER="kso-agent"

# ── Require root ──
if [ "$(id -u)" -ne 0 ]; then
  echo "[kso] ERROR: this script must be run as root (use sudo)."
  exit 1
fi

echo "[kso] Uninstalling KSO Agent..."

# 1. Stop the service if it is running
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
  echo "[kso] Stopping ${SERVICE_NAME} service..."
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
fi

# 2. Disable the service (ignore errors if already disabled/absent)
if command -v systemctl >/dev/null 2>&1; then
  echo "[kso] Disabling ${SERVICE_NAME} service..."
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
fi

# 3. Remove the systemd unit and reload
if [ -f "$SERVICE_DST" ]; then
  echo "[kso] Removing systemd unit $SERVICE_DST..."
  rm -f "$SERVICE_DST"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true
fi

# 4. Kill any leftover hand-launched process
if command -v pkill >/dev/null 2>&1; then
  pkill -f "$BINARY_DST" 2>/dev/null || true
fi

# 5. Remove the binary
if [ -f "$BINARY_DST" ]; then
  echo "[kso] Removing binary $BINARY_DST..."
  rm -f "$BINARY_DST"
fi

# 6. Remove the config directory (contains the agent token)
if [ -d "$CONFIG_DIR" ]; then
  echo "[kso] Removing config directory $CONFIG_DIR..."
  rm -rf "$CONFIG_DIR"
fi

# 7. Remove the system user (and its private group if empty)
if id -u "$AGENT_USER" >/dev/null 2>&1; then
  echo "[kso] Removing ${AGENT_USER} user..."
  userdel "$AGENT_USER" 2>/dev/null || true
fi

echo "[kso] KSO Agent uninstalled successfully!"
echo "[kso] Verify with: systemctl status kso-agent"
