#!/bin/sh
set -eu

# ──────────────────────────────────────────────
# KSO Agent Installer (distribution)
# Downloads the kso-agent binary from the public releases repository
# and installs it as a systemd service.
#
# POSIX-compatible (works with: curl ... | sh)
#
# Usage:
#   curl -fsSL https://cdn.kso-services.com/install-agent.sh | sudo sh -s -- --token <AGENT_TOKEN>
#   # or:
#   export token=<AGENT_TOKEN>
#   curl -fsSL https://cdn.kso-services.com/install-agent.sh | sudo -E sh
# ──────────────────────────────────────────────

# Public releases repository (binary source)
RELEASES_REPO="kso-services/public-releases"
BINARY_NAME="kso-agent"

BINARY_DST="/usr/local/bin/kso-agent"
CONFIG_DIR="/etc/kso-agent"
ENV_FILE="${CONFIG_DIR}/kso-agent.env"
SERVICE_DST="/etc/systemd/system/kso-agent.service"
SUDOERS_DST="/etc/sudoers.d/kso-agent"

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
if ! id -u kso-agent >/dev/null 2>&1; then
  echo "[kso] Creating kso-agent user..."
  useradd --system --no-create-home --shell /usr/sbin/nologin kso-agent
fi

# 1b. Grant the agent the minimal privileges it needs (LVM + service restart).
# The agent runs as the unprivileged kso-agent user and prefixes these
# commands with sudo (see src/handlers.js).
echo "[kso] Installing sudoers rules to $SUDOERS_DST..."
mkdir -p /etc/sudoers.d
cat > "$SUDOERS_DST" <<'EOF'
kso-agent ALL=(root) NOPASSWD: /usr/sbin/lvs
kso-agent ALL=(root) NOPASSWD: /usr/sbin/vgs
kso-agent ALL=(root) NOPASSWD: /usr/sbin/lvextend
kso-agent ALL=(root) NOPASSWD: /bin/systemctl restart *
EOF
chmod 0440 "$SUDOERS_DST"
visudo -cf "$SUDOERS_DST"

# ── Helpers ──
# Download a URL to a destination file (curl preferred, wget fallback).
download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    echo "[kso] ERROR: neither curl nor wget is available." >&2
    exit 1
  fi
}

# 2. Download the binary (latest release) from the public repo
BINARY_URL="https://github.com/${RELEASES_REPO}/releases/latest/download/${BINARY_NAME}"
CHECKSUM_URL="${BINARY_URL}.sha256"
SIGNATURE_URL="${BINARY_URL}.sig"

TMP_BIN="$(mktemp)"
echo "[kso] Downloading ${BINARY_URL}..."
download "$BINARY_URL" "$TMP_BIN"

# 2a. Checksum verification (fail-closed: abort if the checksum is missing or
# does not match).
TMP_SUM="$(mktemp)"
if ! download "$CHECKSUM_URL" "$TMP_SUM"; then
  echo "[kso] ERROR: could not download checksum ${CHECKSUM_URL}." >&2
  rm -f "$TMP_BIN" "$TMP_SUM"
  exit 1
fi

EXPECTED="$(awk '{print $1}' "$TMP_SUM")"
ACTUAL="$(sha256sum "$TMP_BIN" | awk '{print $1}')"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "[kso] ERROR: checksum verification failed (expected '$EXPECTED', got '$ACTUAL')." >&2
  rm -f "$TMP_BIN" "$TMP_SUM"
  exit 1
fi
rm -f "$TMP_SUM"
echo "[kso] Checksum verified."

# 2b. Cryptographic signature verification (GPG, fail-closed). The public key
# below is the KSO Agent release signing key; the matching private key only
# ever lives in the CI secret and is never shipped.
if ! command -v gpg >/dev/null 2>&1; then
  echo "[kso] ERROR: gpg is required to verify the agent binary signature." >&2
  rm -f "$TMP_BIN"
  exit 1
fi

TMP_SIG="$(mktemp)"
if ! download "$SIGNATURE_URL" "$TMP_SIG"; then
  echo "[kso] ERROR: could not download signature ${SIGNATURE_URL}." >&2
  rm -f "$TMP_BIN" "$TMP_SIG"
  exit 1
fi

GPG_HOME="$(mktemp -d)"
chmod 700 "$GPG_HOME"
cleanup_signature() {
  rm -rf "$GPG_HOME"
  rm -f "$TMP_SIG"
}
trap cleanup_signature EXIT
export GNUPGHOME="$GPG_HOME"

cat > "${GPG_HOME}/signing-key.asc" <<'GPG_KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGrTAW4BEAC+iz166ZHYnJ27xBdYIkQY9ZplCirJicT4c8NI3MUPS5QskD0y
+rAL+XdKjYDxGqGhG+4VcJQ3cYsHY0bXcO4xSQ5hWqOl2CBQhLhI5/b17b1wk43M
ifvoBzx4X08QByeyzsmayJ3mfrGSIrlvCqHSosB+aMgXcVUM4PNPjTh0EdmugMpj
W+ZrkVXX376+hrsxV7+ncf/m0G1y0I2Zo5O9+qfnd6mKplo4fmbZ4i+9EsDUPgpC
A/QICCw5idy6ymcLdos7l0AjuNnFEW+Z5wLX2vUrXWSVsMAoqBYhww6YXdGbfuMt
zqLLzutZ6XoaIqcHQCxakvLjxWFwhIC0wunOs6JGzBhUUBzKf0oohn+dejTTGTMZ
fJttjg9e7yGGXYHCZUL6IP0U5GiTcHQZinzRUIFeVxyt1u0qMl2qdigyxrl10teZ
nQ3sAs0H4ql/Ed8KKUhqLhyE/pooxd/4Bcx4DQFNBByFn2G7A3/YFCEZ8tNGw539
q8+bUShNSJMLfefk88OoqFvHjj9teraU8/llkVpleaHzaxpaZ9a7BzUu4bGOISsT
icbNNQbWP6ycu9MTck4ymUqvNBtklbsggwIWjI7sPxUsGYJSi7n5J1Jl8+6spHn9
EOL76IfOFOUwyTOMDgr57VoAO3125CPb2AMqqcqpIXKS/XBccAbpmZmuywARAQAB
tCNrc28tYWdlbnQgPGV0b3ViYUBrc28tc2VydmljZXMuY29tPokCUQQTAQoAOxYh
BOVZUjcJBDQL32COnyg26w/ockdUBQJq0wFuAhsDBQsJCAcCAiICBhUKCQgLAgQW
AgMBAh4HAheAAAoJECg26w/ockdUc5YP/36sj4t4CN6uxzhoatyhn70PzarY9VEr
ZP6NPyJ5h+QbnjKoKseH8KN0+yuxX3HJmjXC5ND9eo33wvjMeN0QAn/gbVEDT46a
o5mN77V/9I5KmuWhF33Gc8wKZsq/Dh/NYmQJ3PJLDG0hfPGh+MAFOWAMBLRuCalu
gL/F0W0UZD1mxTliEgrI3bGgDAW3PU4ioAlGdlWBFMXsZK5wukSh8i9wCOcbf9qR
w4Y0jtoKIDaTR1Ql3QNaTIT6J+8tG+Ia3yn6AwibdCbY1PSEZIvxyCUNuov0qOSB
L4V+iz2aiW7Ka6mjjiakkYfkL4DDjjreOUQIADyo1iIsnDzoMVbA7SChSmsb3Vb7
870N9wrJK/UdiVbVATtS5I0bOEIQL8ofdYohSoecdrnb29MxxN+hhxmKBkvtfS6P
QxIKfl4fgN6Tj7ZThrrBnwrkYq9Jv1Tm+XPgqymUYXd2ETuk90NYyd8Vg034Mo1o
/dNSSHcDpAJ5f6qa+HiVw7VGDUV/PBqCheYaytj06WxHbadQXD05/ZHFF/AUlvo/
jbEkJPfHs8TsRoPGkuDV5iPDPLcj44MIm0XiqSRPhU5vDIoZj23JDkv3vZDh4hq8
fn5PFSjR1GrL8hs16mKFXV1slB0w4yV2eOJOmCY3+wolxgOfavGt3daMa7Xr8Fx2
Z/pJYRhHsKMo
=+CtV
-----END PGP PUBLIC KEY BLOCK-----
GPG_KEY

gpg --batch --quiet --import "${GPG_HOME}/signing-key.asc" 2>/dev/null
if ! gpg --batch --quiet --verify "$TMP_SIG" "$TMP_BIN" 2>/dev/null; then
  echo "[kso] ERROR: signature verification failed for ${BINARY_NAME}." >&2
  rm -f "$TMP_BIN"
  exit 1
fi
echo "[kso] Signature verified."

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
KSO_APP_ENV=production
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
