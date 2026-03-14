#!/usr/bin/env bash
# setup-openclaw.sh — Full automated setup for OpenClaw on Raspberry Pi 4
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
#
# Run as the 'pi' user (not root). Requires .env to be filled in first.
# See .env.example for the template and CHECKLIST.md for interactive steps.

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗] FATAL:${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${RESET}"; }

# ── Safety: must not run as root ─────────────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
  die "Do not run this script as root. Run as the 'pi' user: bash scripts/setup-openclaw.sh"
fi

if [[ "$(whoami)" != "pi" ]]; then
  warn "Expected to run as user 'pi', got '$(whoami)'. Continuing, but verify this is intentional."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── Load and validate .env ────────────────────────────────────────────────────
section "Loading .env"

ENV_FILE="$REPO_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  die ".env not found. Copy .env.example to .env and fill in your values:\n  cp .env.example .env && chmod 600 .env && nano .env"
fi

# Enforce strict permissions — .env must not be world- or group-readable
ENV_PERMS=$(stat -c "%a" "$ENV_FILE")
if [[ "$ENV_PERMS" != "600" ]]; then
  warn ".env permissions are ${ENV_PERMS} — tightening to 600 (owner read/write only)."
  chmod 600 "$ENV_FILE"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Validate required variables
MISSING=()
[[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] && MISSING+=("TELEGRAM_BOT_TOKEN")
[[ -z "${TAILSCALE_HOSTNAME:-}" ]] && MISSING+=("TAILSCALE_HOSTNAME")
[[ -z "${FAN_GPIO_PIN:-}" ]]       && MISSING+=("FAN_GPIO_PIN")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  die "Missing required variables in .env: ${MISSING[*]}\nEdit .env and fill them in."
fi

# ANTHROPIC_API_KEY is optional — dummy token used if blank
ANTHROPIC_KEY_PROVIDED=true
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  ANTHROPIC_KEY_PROVIDED=false
  ANTHROPIC_API_KEY="DUMMY_REPLACE_VIA_CLAUDE_SETUP_TOKEN"
  warn "ANTHROPIC_API_KEY is blank — dummy token will be written. You MUST run 'claude setup-token' then 'openclaw models auth setup-token --provider anthropic' after setup."
fi

log ".env loaded and validated."
log "  TAILSCALE_HOSTNAME : ${TAILSCALE_HOSTNAME}"
log "  FAN_GPIO_PIN       : ${FAN_GPIO_PIN}"
log "  ANTHROPIC_API_KEY  : $([ "$ANTHROPIC_KEY_PROVIDED" = true ] && echo 'provided' || echo 'BLANK — dummy token will be used')"

# ── Phase 1: Pre-flight checks ────────────────────────────────────────────────
section "Phase 1 — Pre-flight checks"

# Tailscale connected?
if tailscale status &>/dev/null; then
  log "Tailscale is connected."
else
  warn "Tailscale does not appear to be connected. Continuing, but Serve will not work until Tailscale is up."
fi

# fan_control.py exists?
if [[ -f /usr/local/bin/fan_control.py ]]; then
  warn "fan_control.py already exists at /usr/local/bin/fan_control.py — will overwrite."
else
  log "fan_control.py not yet deployed — will install."
fi

# Leftover openclaw user?
if id -u openclaw &>/dev/null; then
  warn "User 'openclaw' already exists — creation will be skipped (idempotent)."
fi

# Leftover fancontrol user?
if id -u fancontrol &>/dev/null; then
  warn "User 'fancontrol' already exists — creation will be skipped (idempotent)."
fi

# Leftover iptables DROP rules?
if sudo iptables -L OUTPUT 2>/dev/null | grep -q "DROP"; then
  warn "Existing DROP rules found in iptables OUTPUT chain. Review before proceeding."
fi

# ── Phase 2: Node.js 24 ───────────────────────────────────────────────────────
section "Phase 2 — Node.js 24"

CURRENT_NODE_MAJOR=0
if command -v node &>/dev/null; then
  CURRENT_NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
fi

if [[ "$CURRENT_NODE_MAJOR" -ge 24 ]]; then
  warn "Node.js $(node --version) already installed (>=24) — skipping upgrade."
else
  log "Installing Node.js 24 via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo apt-get install -y nodejs
  log "Node.js $(node --version) installed."
fi

# ── Phase 3: fancontrol user + fan service ────────────────────────────────────
section "Phase 3 — fancontrol user + fan service"

if ! id -u fancontrol &>/dev/null; then
  log "Creating system user 'fancontrol'..."
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin fancontrol
else
  warn "User 'fancontrol' already exists — skipping creation."
fi

# Add fancontrol to gpio group
if getent group gpio &>/dev/null; then
  sudo usermod -aG gpio fancontrol
  log "Added fancontrol to gpio group."
else
  warn "gpio group not found — fancontrol may not have GPIO access. Install python3-gpiozero or rpi-lgpio."
fi

log "Deploying fan scripts..."
sudo cp "$REPO_DIR/fan/fan_control.py" /usr/local/bin/fan_control.py
sudo cp "$REPO_DIR/fan/fan_status.py"  /usr/local/bin/fan_status.py
sudo chmod 755 /usr/local/bin/fan_control.py /usr/local/bin/fan_status.py

# fan-status wrapper — safe to call as any user via sudoers
sudo tee /usr/local/bin/fan-status > /dev/null << 'EOF'
#!/usr/bin/env bash
# fan-status — read-only fan/temp wrapper, safe for sudoers
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
exec python3 /usr/local/bin/fan_status.py
EOF
sudo chmod 755 /usr/local/bin/fan-status

# fan-control.service systemd unit
sudo tee /etc/systemd/system/fan-control.service > /dev/null << EOF
# fan-control.service — PWM fan daemon
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
[Unit]
Description=OpenClaw Fan Controller
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=fancontrol
Environment=FAN_GPIO_PIN=${FAN_GPIO_PIN}
ExecStart=/usr/bin/python3 /usr/local/bin/fan_control.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log "fan-control service unit written."

# ── Phase 4: openclaw user + LAN block ───────────────────────────────────────
section "Phase 4 — openclaw user + LAN block"

if ! id -u openclaw &>/dev/null; then
  log "Creating system user 'openclaw'..."
  sudo useradd --system --create-home --home-dir /home/openclaw --shell /usr/sbin/nologin openclaw
else
  warn "User 'openclaw' already exists — skipping creation."
fi

OPENCLAW_UID=$(id -u openclaw)
log "openclaw UID: ${OPENCLAW_UID}"

# openclaw-lan-block.service — iptables oneshot
sudo tee /etc/systemd/system/openclaw-lan-block.service > /dev/null << EOF
# openclaw-lan-block.service — Blocks openclaw from reaching the LAN
# Applied at boot as a oneshot; survives service restarts.
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
[Unit]
Description=OpenClaw LAN Firewall Block
Before=openclaw-gateway.service
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables  -A OUTPUT -m owner --uid-owner ${OPENCLAW_UID} -d 192.168.0.0/24 -j DROP
ExecStart=/sbin/ip6tables -A OUTPUT -m owner --uid-owner ${OPENCLAW_UID} -d fc00::/7      -j DROP
ExecStop=/sbin/iptables   -D OUTPUT -m owner --uid-owner ${OPENCLAW_UID} -d 192.168.0.0/24 -j DROP
ExecStop=/sbin/ip6tables  -D OUTPUT -m owner --uid-owner ${OPENCLAW_UID} -d fc00::/7       -j DROP

[Install]
WantedBy=multi-user.target
EOF

log "openclaw-lan-block service unit written."

# ── Phase 5: Install OpenClaw ─────────────────────────────────────────────────
section "Phase 5 — Install OpenClaw"

if sudo -u openclaw -i bash -c 'command -v openclaw &>/dev/null'; then
  warn "OpenClaw already installed for user openclaw — skipping install."
  sudo -u openclaw -i bash -c 'openclaw --version' || true
else
  log "Installing OpenClaw as user openclaw..."
  sudo -u openclaw -i bash -c 'curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard'
  log "OpenClaw installed: $(sudo -u openclaw -i bash -c 'openclaw --version' 2>&1 || echo 'version unknown')"
fi

# Resolve binary path for use in the systemd unit
OPENCLAW_BIN=$(sudo -u openclaw -i bash -c 'command -v openclaw 2>/dev/null || echo ""')
if [[ -z "$OPENCLAW_BIN" ]]; then
  die "Cannot find openclaw binary for user openclaw. Installation may have failed."
fi
log "openclaw binary: ${OPENCLAW_BIN}"

# ── Phase 6: Directories and workspace ───────────────────────────────────────
section "Phase 6 — Directories and workspace"

for DIR in \
  /home/openclaw/.openclaw \
  /home/openclaw/workspace \
  /home/openclaw/workspace/skills \
  /home/openclaw/workspace/skills/pi-health; do
  sudo mkdir -p "$DIR"
done

sudo chown -R openclaw:openclaw /home/openclaw/.openclaw /home/openclaw/workspace
log "Workspace directories created."

# Enable lingering so the openclaw user's services survive logout
sudo loginctl enable-linger openclaw
log "Lingering enabled for openclaw."

# ── Phase 7: Secrets file ─────────────────────────────────────────────────────
section "Phase 7 — Secrets file"

sudo mkdir -p /etc/openclaw

sudo tee /etc/openclaw/secrets.env > /dev/null << EOF
# OpenClaw secrets — root:root 600 — never commit this file
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
EOF

sudo chmod 600 /etc/openclaw/secrets.env
sudo chown root:root /etc/openclaw/secrets.env
log "Secrets file written: /etc/openclaw/secrets.env (root:root 600)"

if [[ "$ANTHROPIC_KEY_PROVIDED" = false ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
  echo -e "${YELLOW}${BOLD}│  ACTION REQUIRED: Anthropic API key is a dummy      │${RESET}"
  echo -e "${YELLOW}${BOLD}│                                                     │${RESET}"
  echo -e "${YELLOW}${BOLD}│  After setup, run both of these as openclaw:        │${RESET}"
  echo -e "${YELLOW}${BOLD}│    sudo -u openclaw -i claude setup-token           │${RESET}"
  echo -e "${YELLOW}${BOLD}│    sudo -u openclaw -i openclaw models auth \       │${RESET}"
  echo -e "${YELLOW}${BOLD}│      setup-token --provider anthropic               │${RESET}"
  echo -e "${YELLOW}${BOLD}│                                                     │${RESET}"
  echo -e "${YELLOW}${BOLD}│  OpenClaw will NOT work until this is done.         │${RESET}"
  echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
  echo ""
fi

# ── Phase 8: OpenClaw config ──────────────────────────────────────────────────
section "Phase 8 — OpenClaw config"

TEMPLATE="$REPO_DIR/config/openclaw.json.template"
if [[ ! -f "$TEMPLATE" ]]; then
  die "Config template not found: $TEMPLATE"
fi

# Substitute TAILSCALE_HOSTNAME placeholder
sudo bash -c "sed 's|\${TAILSCALE_HOSTNAME}|${TAILSCALE_HOSTNAME}|g' '$TEMPLATE' > /home/openclaw/.openclaw/openclaw.json"
sudo chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
log "Config written: /home/openclaw/.openclaw/openclaw.json"

# ── Phase 9: Pi health skill ──────────────────────────────────────────────────
section "Phase 9 — Pi health skill"

sudo tee /home/openclaw/workspace/skills/pi-health/SKILL.md > /dev/null << 'EOF'
# Pi Health Skill
Use this skill when the user asks about Pi temperature, fan speed, or system health.
Run: sudo /usr/local/bin/fan-status
Report the temperature and fan speed clearly.
Never attempt to modify fan speed or access GPIO directly.
If temperature exceeds 70°C, warn the user proactively.
EOF

sudo chown -R openclaw:openclaw /home/openclaw/workspace/skills/pi-health
log "Pi health skill written."

# ── Phase 10: Sudoers ─────────────────────────────────────────────────────────
section "Phase 10 — Sudoers"

sudo tee /etc/sudoers.d/openclaw-fan > /dev/null << 'EOF'
# Allow openclaw to run the read-only fan-status wrapper only
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
openclaw ALL=(ALL) NOPASSWD: /usr/local/bin/fan-status
EOF

sudo chmod 440 /etc/sudoers.d/openclaw-fan
log "Sudoers rule written: /etc/sudoers.d/openclaw-fan"

# openclaw-gateway.service systemd unit (written here, before the confirmation prompt)
# Service name matches the convention used by 'openclaw gateway install'.
sudo tee /etc/systemd/system/openclaw-gateway.service > /dev/null << EOF
# openclaw-gateway.service — OpenClaw AI assistant gateway daemon
# https://github.com/YOUR_USERNAME/openclaw-pi-setup
[Unit]
Description=OpenClaw AI Gateway
After=network-online.target openclaw-lan-block.service
Wants=network-online.target
Requires=openclaw-lan-block.service

[Service]
Type=simple
User=openclaw
WorkingDirectory=/home/openclaw/workspace
EnvironmentFile=/etc/openclaw/secrets.env
Environment=OPENCLAW_CONFIG_PATH=/home/openclaw/.openclaw/openclaw.json
Environment=NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
ExecStart=${OPENCLAW_BIN} gateway
Restart=always
RestartSec=10
TimeoutStartSec=90
StandardOutput=journal
StandardError=journal

# Security hardening
PrivateDevices=yes
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/home/openclaw /var/tmp/openclaw-compile-cache

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /var/tmp/openclaw-compile-cache
sudo chown openclaw:openclaw /var/tmp/openclaw-compile-cache
log "openclaw-gateway service unit written."

# ── Phase 11: Pause before point of no return ─────────────────────────────────
section "Phase 11 — Confirmation"

echo ""
echo -e "${BOLD}Summary of what will now be enabled and started:${RESET}"
echo "  • fan-control.service         (PWM fan daemon, User=fancontrol)"
echo "  • openclaw-lan-block.service  (iptables DROP for openclaw UID=${OPENCLAW_UID})"
echo "  • openclaw-gateway.service    (OpenClaw AI gateway, User=openclaw)"
echo ""
echo -e "${BOLD}Config:${RESET}"
echo "  • TAILSCALE_HOSTNAME : ${TAILSCALE_HOSTNAME}"
echo "  • FAN_GPIO_PIN       : ${FAN_GPIO_PIN}"
echo "  • API key            : $([ "$ANTHROPIC_KEY_PROVIDED" = true ] && echo 'provided' || echo 'DUMMY — claude setup-token required after')"
echo ""

read -rp "$(echo -e "${YELLOW}Continue with service installation? [y/N]${RESET} ")" CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
  log "Aborted. No services have been started. Re-run when ready."
  exit 0
fi

# ── Phase 12: Enable and start services ───────────────────────────────────────
section "Phase 12 — Enable and start services"

sudo systemctl daemon-reload

for SVC in fan-control openclaw-lan-block openclaw-gateway; do
  log "Enabling and starting ${SVC}..."
  sudo systemctl enable "$SVC"
  sudo systemctl start  "$SVC" || warn "${SVC} failed to start — check: sudo journalctl -u ${SVC}"
  sudo systemctl status "$SVC" --no-pager -l || true
  echo ""
done

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
echo -e "${GREEN}${BOLD}│  openclaw-pi-setup complete                         │${RESET}"
echo -e "${GREEN}${BOLD}├─────────────────────────────────────────────────────┤${RESET}"
echo -e "${GREEN}${BOLD}│  Next: follow CHECKLIST.md                          │${RESET}"
echo -e "${GREEN}${BOLD}│                                                     │${RESET}"
if [[ "$ANTHROPIC_KEY_PROVIDED" = false ]]; then
echo -e "${YELLOW}${BOLD}│  REQUIRED — run as openclaw:                        │${RESET}"
echo -e "${YELLOW}${BOLD}│    sudo -u openclaw -i claude setup-token           │${RESET}"
echo -e "${YELLOW}${BOLD}│    sudo -u openclaw -i openclaw models auth \       │${RESET}"
echo -e "${YELLOW}${BOLD}│      setup-token --provider anthropic               │${RESET}"
echo -e "${GREEN}${BOLD}│                                                     │${RESET}"
fi
echo -e "${GREEN}${BOLD}│  Access UI (once on Tailscale):                     │${RESET}"
echo -e "${GREEN}${BOLD}│    https://${TAILSCALE_HOSTNAME}${RESET}"
echo -e "${GREEN}${BOLD}│                                                     │${RESET}"
echo -e "${GREEN}${BOLD}│  Health check:                                      │${RESET}"
echo -e "${GREEN}${BOLD}│    sudo -u openclaw openclaw gateway status         │${RESET}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
echo ""
