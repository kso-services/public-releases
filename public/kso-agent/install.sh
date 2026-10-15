#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# KSO Agent Installer (distribution)
# Downloads the kso-agent binary from the public releases repository
# and installs it as a systemd service.
#
# Usage:
#   curl -fsSL https://cdn.kso-services.com/kso-agent/install.sh | sudo sh -s -- --token <AGENT_TOKEN>
#   # or:
#   export token=<AGENT_TOKEN>
#   curl -fsSL https://cdn.kso-services.com/kso-agent/install.sh | sudo -E sh
# ──────────────────────────────────────────────

# Public releases repository (binary source)
RELEASES_REPO="kso-services/public-releases"
BINARY_NAME="kso-agent"

BINARY_DST="/usr/local/bin/kso-agent"
CONFIG_DIR="/etc/kso-agent"
ENV_FILE="${CONFIG_DIR}/kso-agent.env"
SERVICE_DST="/etc/systemd/system/kso-agent.service"

# Agent token: --token <value> or TOKEN/token env var
AGENT_TOKEN=""
# API WebSocket URL (override via env)
API_WSS_URL="${API_WSS_URL:-wss://supervision-api.kso-services.com/ws/agent}"

# ── Parse arguments ──
while [ $# -gt 0 ]; do
  case "$1" in
    --token)
      AGENT_TOKEN="${2:-}"
      shift 2
      ;;
    --token=*)
      AGENT_TOKEN="${1#*=}"
      shift
      ;;
    *)
      echo "[kso] ERROR: unknown argument '$1'"
      echo "[kso] Usage: install-agent.sh --token <AGENT_TOKEN>"
      exit 1
      ;;
  esac
done

# Fallback to TOKEN/token env var (accept both cases)
if [ -z "$AGENT_TOKEN" ]; then
  AGENT_TOKEN="${TOKEN:-${token:-}}"
fi

echo "[kso] Installing KSO Agent..."

if [ -z "$AGENT_TOKEN" ]; then
  echo "[kso] ERROR: Agent token is required."
  echo "[kso] Usage: install-agent.sh --token <AGENT_TOKEN>"
  echo "[kso] Generate a token from the KSO supervision UI (server detail page)."
  exit 1
fi

# 1. Create kso-agent user
if ! id -u kso-agent &>/dev/null; then
  echo "[kso] Creating kso-agent user..."
  useradd --system --no-create-home --shell /usr/sbin/nologin kso-agent
fi

# 2. Download the binary (latest release) from the public repo
BINARY_URL="https://github.com/${RELEASES_REPO}/releases/latest/download/${BINARY_NAME}"
CHECKSUM_URL="${BINARY_URL}.sha256"

TMP_BIN="$(mktemp)"
echo "[kso] Downloading ${BINARY_URL}..."
if command -v curl &>/dev/null; then
  curl -fsSL "$BINARY_URL" -o "$TMP_BIN"
elif command -v wget &>/dev/null; then
  wget -qO "$TMP_BIN" "$BINARY_URL"
else
  echo "[kso] ERROR: neither curl nor wget is available."
  exit 1
fi

# Best-effort checksum verification
TMP_SUM="$(mktemp)"
if command -v curl &>/dev/null; then
  curl -fsSL "$CHECKSUM_URL" -o "$TMP_SUM" 2>/dev/null || true
elif command -v wget &>/dev/null; then
  wget -qO "$TMP_SUM" "$CHECKSUM_URL" 2>/dev/null || true
fi

if [ -s "$TMP_SUM" ]; then
  EXPECTED="$(awk '{print $1}' "$TMP_SUM")"
  ACTUAL="$(sha256sum "$TMP_BIN" | awk '{print $1}')"
  if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "[kso] ERROR: checksum mismatch (expected $EXPECTED, got $ACTUAL)."
    rm -f "$TMP_BIN" "$TMP_SUM"
    exit 1
  fi
  echo "[kso] Checksum verified."
else
  echo "[kso] WARNING: could not fetch checksum, skipping verification."
fi
rm -f "$TMP_SUM"

# 3. Install binary
echo "[kso] Installing binary to $BINARY_DST..."
mv "$TMP_BIN" "$BINARY_DST"
chmod 755 "$BINARY_DST"

# 4. Create config directory and write env file
mkdir -p "$CONFIG_DIR"
echo "[kso] Writing agent token to $ENV_FILE..."
cat > "$ENV_FILE" <<EOF
API_WSS_URL=${API_WSS_URL}
API_AGENT_TOKEN=${AGENT_TOKEN}
EOF
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# 5. Install systemd service (inline unit, works for piped installs)
echo "[kso] Installing systemd service..."
cat > "$SERVICE_DST" <<'EOF'
[Unit]
Description=KSO Agent — Remote maintenance agent
After=network.target

[Service]
Type=simple
User=kso-agent
Group=kso-agent
ExecStart=/usr/local/bin/kso-agent
Restart=always
RestartSec=5
Environment=API_WSS_URL=wss://supervision-api.kso-services.com/ws/agent
EnvironmentFile=-/etc/kso-agent/kso-agent.env

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# 6. Enable and start
echo "[kso] Enabling and starting kso-agent service..."
systemctl enable kso-agent
systemctl start kso-agent

echo "[kso] KSO Agent installed successfully!"
echo "[kso] Check status with: systemctl status kso-agent"
echo "[kso] View logs with: journalctl -u kso-agent -f"
