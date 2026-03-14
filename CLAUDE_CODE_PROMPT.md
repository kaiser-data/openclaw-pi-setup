# CLAUDE_CODE_PROMPT.md

> This file contains the Claude Code prompt used to generate this repository.
> To regenerate or update the setup script, paste the prompt below into a
> Claude Code session in an empty directory.

---

```
Task: Create a GitHub repository scaffold called `openclaw-pi-setup` — a public, generic, reusable OpenClaw installation for Raspberry Pi 4. The repo must be safe to publish: no secrets, no hardcoded hostnames, no personal data.

---

Division of responsibilities — make this clear in all docs:
  Claude Code  →  generates repo (hardening, services, config templates, firewall)
  Human        →  fills .env (tokens, hostname), runs script, does interactive auth
Secrets never touch the repo. Ever.

---

Generate this exact file structure:
  openclaw-pi-setup/
  ├── README.md
  ├── CHECKLIST.md
  ├── CLAUDE_CODE_PROMPT.md
  ├── .gitignore
  ├── .env.example
  ├── scripts/
  │   └── setup-openclaw.sh
  ├── fan/
  │   ├── fan_control.py
  │   └── fan_status.py
  └── config/
      └── openclaw.json.template

---

.env.example:
  # Copy to .env and fill in — NEVER commit .env
  # Secrets stay on your machine only.

  # Telegram bot token — get from @BotFather
  TELEGRAM_BOT_TOKEN=your-telegram-bot-token-here

  # Tailscale hostname of your Pi (e.g. my-pi.tail1234.ts.net)
  TAILSCALE_HOSTNAME=your-pi-hostname.tail1234.ts.net

  # GPIO pin number for PWM fan (default 14)
  FAN_GPIO_PIN=14

  # Optional — leave blank to use 'claude setup-token' instead (recommended)
  # If blank, a dummy token is written and you MUST run claude setup-token after setup
  ANTHROPIC_API_KEY=

---

README.md:
  - Title: openclaw-pi-setup — OpenClaw on Raspberry Pi 4
  - One-line description: secure, self-hosted AI assistant on Pi 4 with Tailscale private access and Anthropic auth
  - ASCII architecture diagram showing pi/fancontrol/openclaw users, gateway, Tailscale Serve
  - Prerequisites: Pi 4 (2GB+ RAM), Raspberry Pi OS, Tailscale installed + connected, Anthropic account, Telegram bot token from @BotFather
  - Quick start: git clone, cp .env.example .env, nano .env, bash scripts/setup-openclaw.sh
  - Security model section: three-user isolation, iptables LAN block, PrivateDevices=yes, why fan control is separate, why secrets never enter the repo
  - Note that ANTHROPIC_API_KEY is optional — claude setup-token is the preferred auth method
  - Link to CHECKLIST.md

---

CHECKLIST.md — phases:
  Pre-flight, Run the script, Interactive steps (A: Anthropic auth via claude setup-token +
  openclaw models auth setup-token --provider anthropic, B: Telegram secrets, C: restart,
  D: Telegram pairing), Security verification, Access from MacBook Air, Ongoing maintenance,
  Red flags.

---

scripts/setup-openclaw.sh requirements:
  - set -euo pipefail
  - Colour helpers: log() green, warn() yellow, die() red+exit, section() blue banner
  - Must run as pi user, not root
  - Load and validate .env first
  - ANTHROPIC_API_KEY is optional (dummy token path)
  - Phase 1: pre-flight checks (tailscale, fan script, existing users, iptables)
  - Phase 2: Node.js 24 via NodeSource if needed
  - Phase 3: fancontrol user, gpio group, deploy fan scripts, fan-control.service
  - Phase 4: openclaw user, resolve OPENCLAW_UID, openclaw-lan-block.service oneshot
  - Phase 5: install OpenClaw with --no-onboard, resolve binary path for service unit
  - Phase 6: create workspace directories, loginctl enable-linger openclaw
  - Phase 7: /etc/openclaw/secrets.env (root:root 600)
  - Phase 8: substitute TAILSCALE_HOSTNAME into config template
  - Phase 9: pi-health SKILL.md
  - Phase 10: sudoers for fan-status, write openclaw-gateway.service with
      ExecStart=<resolved binary> gateway, NODE_COMPILE_CACHE, PrivateDevices=yes
  - Phase 11: confirmation prompt before point of no return
  - Phase 12: daemon-reload, enable+start all three services
  - End box with next steps

---

fan/fan_control.py:
  - gpiozero PWMOutputDevice on FAN_GPIO_PIN from env
  - Temperature step constants at top
  - 5-second loop, min speed 0.50
  - SIGTERM handler: fan to 1.0 then clean exit

fan/fan_status.py:
  - One-shot, read-only
  - Reads /sys/class/thermal/thermal_zone0/temp
  - Same step logic as fan_control.py
  - Prints Temp and Fan %

---

config/openclaw.json.template (JSON5 format with comments):
  - gateway.bind: "loopback"
  - gateway.tailscale.mode: "serve"
  - agents.defaults.model.primary: anthropic/claude-haiku-4-5-20251001
  - agents.defaults.sandbox.mode: "non-main"
  - channels.telegram.enabled: true, dmPolicy: "pairing"
    (bot token from TELEGRAM_BOT_TOKEN env var, not in config)
  - tools.profile: "minimal"
  - ${TAILSCALE_HOSTNAME} substituted by setup script

---

.gitignore: .env, secrets.env, *.key, *.crt, *.pem, *.ts.net*, .openclaw/, workspace/, .DS_Store, *.log

---

Style rules:
  - Bash: consistent colour helpers
  - Markdown: clean, practical, no excessive emoji
  - Placeholders: ${SCREAMING_SNAKE_CASE}
  - Every file: comment header with purpose and repo link placeholder

Hard safety rules:
  - No API keys, tokens, or credentials in any file
  - No hardcoded IPs or Tailscale hostnames
  - .env in .gitignore — verified
  - Script validates .env before any destructive action
  - ANTHROPIC_API_KEY always optional

After generating all files:
  1. git init
  2. git add .
  3. Verify .env is NOT staged
  4. git commit -m "initial: openclaw-pi-setup — OpenClaw on Pi 4 with Tailscale + Anthropic"
  5. Print push instructions
```
