# openclaw-pi-setup — Run OpenClaw on a Raspberry Pi 4

A one-script setup that turns a Raspberry Pi 4 into a secure, always-on AI assistant you can reach from anywhere via Telegram or a private web UI — without paying for cloud hosting.

![CI](https://img.shields.io/badge/CI-passing-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## Why this setup?

A Raspberry Pi 4 costs about €50–80 one-time. Running an AI assistant on a cloud VPS costs €5–15/month. This pays for itself in a few months — and you keep full control.

**What you get:**

- **Always-on AI assistant** — OpenClaw runs as a background service on your Pi. It starts automatically on boot and restarts itself if it crashes.
- **Private access from anywhere** — Tailscale creates an encrypted tunnel between your Pi and your other devices. Nobody else can reach it. No port forwarding needed.
- **Chat via Telegram** — Message your own bot from your phone. The bot only responds to approved users (you).
- **Web UI** — Open `https://your-pi-hostname` in a browser on any of your Tailscale devices for a full chat interface.
- **Smart fan control** — A separate service monitors the CPU temperature and adjusts the fan speed automatically, keeping the Pi cool under load.
- **Locked down by default** — The AI process runs as an isolated system user. It cannot reach your local network (router, NAS, other devices), cannot touch hardware, and cannot write outside its own directory.

---

## How it works

The setup script creates three separate system users, each with minimal permissions:

```
┌─────────────────────────────────────────────────┐
│  pi user        — that's you: admin, SSH, sudo  │
│  fancontrol     — only allowed to control fan   │
│  openclaw       — only allowed to reach internet│
└─────────────────────────────────────────────────┘
```

The `openclaw` user runs the AI process. A firewall rule (iptables) blocks it from touching anything on your local network — it can only reach the internet (Anthropic API and Telegram). Your router, NAS, and other devices are invisible to it.

Fan control is intentionally separate: GPIO hardware access is a security risk. The `fancontrol` user owns that privilege. OpenClaw can only read the temperature via a narrow read-only wrapper.

```
Your phone / MacBook
       │
       │  (Tailscale encrypted tunnel)
       ▼
Pi — openclaw gateway (localhost only)
       │
       ├── Anthropic API (Claude models, outbound)
       ├── Telegram bot (outbound)
       └── Fan status (read-only, no hardware access)
```

---

## What you need before starting

- **Raspberry Pi 4** with at least 2GB RAM (4GB recommended)
- **Raspberry Pi OS** installed (64-bit, Lite or Desktop)
- **Tailscale** installed on the Pi and on your Mac/phone — [tailscale.com](https://tailscale.com) (free for personal use)
- **Anthropic account** — [console.anthropic.com](https://console.anthropic.com) (you can use a Claude subscription instead of an API key)
- **Telegram bot token** — create a bot in 30 seconds via [@BotFather](https://t.me/BotFather) on Telegram

---

## Quick start

```bash
# 1. Clone this repo onto your Pi
git clone https://github.com/kaiser-data/openclaw-pi-setup
cd openclaw-pi-setup

# 2. Create your secrets file (never committed to git)
cp .env.example .env
chmod 600 .env        # make it unreadable to other users
nano .env             # fill in your values (see below)

# 3. Run the setup script
bash scripts/setup-openclaw.sh
```

**What to fill in `.env`:**

| Variable | What it is | Example |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Token from @BotFather | `123456:ABCdef...` |
| `TAILSCALE_HOSTNAME` | Your Pi's Tailscale address | `pi-claw-agent.tail1234.ts.net` |
| `FAN_GPIO_PIN` | GPIO pin your fan is on | `14` |
| `ANTHROPIC_API_KEY` | Optional — leave blank to use `claude setup-token` instead | _(leave empty)_ |

> Not sure of your Tailscale hostname? Run `tailscale status` on the Pi — it's the first hostname listed.

After the script finishes, follow **[CHECKLIST.md](CHECKLIST.md)** for the two manual steps that can't be automated: approving your Anthropic account and pairing your Telegram bot.

---

## What the script does (overview)

The script runs automatically and asks for confirmation before making any permanent changes:

1. Checks prerequisites (Tailscale connected, Node.js version, clean state)
2. Upgrades Node.js to v24 if needed
3. Creates the `fancontrol` user and deploys the fan speed daemon
4. Creates the `openclaw` user and sets up the firewall rule that blocks LAN access
5. Downloads and installs OpenClaw
6. Creates the workspace and config from your `.env` values
7. Stores your secrets securely in `/etc/openclaw/secrets.env` (readable by root only)
8. Asks you to confirm before enabling anything
9. Starts all three services and prints their status

---

## Security model (plain English)

**Your secrets never enter this repository.** The `.env` file is in `.gitignore`. Tokens are stored in `/etc/openclaw/secrets.env` on your Pi with `chmod 600` (only root can read it). They are injected into the service at runtime — never written to config files.

**The AI can't reach your home network.** An iptables firewall rule drops all outbound traffic from the `openclaw` user to `192.168.0.0/24`. It can reach `api.anthropic.com` and Telegram, nothing else local.

**The AI can't touch your hardware.** The systemd unit sets `PrivateDevices=yes`, blocking access to `/dev/*` at the kernel level. The fan controller is a completely separate process owned by a different user.

**Only you can message the bot.** Telegram `dmPolicy` is set to `"pairing"` — any new user who messages the bot gets a code. You approve it on the Pi. Anyone else is ignored.

**Anthropic API key is optional.** You can authenticate using `claude setup-token` (a browser-based login flow) instead of pasting an API key into any file. This is the recommended approach.

---

## Files in this repo

| File | What it does |
|---|---|
| `.env.example` | Template for your secrets — copy to `.env`, fill in, never commit |
| `scripts/setup-openclaw.sh` | The main setup script |
| `fan/fan_control.py` | Fan speed daemon (runs as `fancontrol` user) |
| `fan/fan_status.py` | Read-only temperature reporter |
| `config/openclaw.json.template` | OpenClaw config template (hostname substituted at setup) |
| `CHECKLIST.md` | Step-by-step guide for the manual steps after the script |
| `CLAUDE_CODE_PROMPT.md` | The prompt used to generate this repo with Claude Code |

---

## After setup

Follow [CHECKLIST.md](CHECKLIST.md) — it walks you through:

1. Approving your Anthropic account (one-time browser login)
2. Pairing your Telegram bot
3. Verifying the security rules are working
4. Accessing the web UI from your Mac
