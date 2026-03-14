# openclaw-pi-setup — OpenClaw on Raspberry Pi 4

Secure, self-hosted AI assistant on Pi 4 with Tailscale private access and Anthropic auth.

![CI](https://img.shields.io/badge/CI-passing-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue)

## Architecture

```
┌─────────────────────────────────────────────────┐
│  pi user        — admin, SSH, sudo              │
│  fancontrol     — owns GPIO, runs fan daemon    │
│  openclaw       — isolated, LAN-blocked         │
└─────────────────────────────────────────────────┘
       │
       ▼
openclaw gateway (127.0.0.1:18789)
       │
       └── Tailscale Serve (tailnet-only HTTPS)
               ├── Anthropic API (outbound)
               ├── Telegram bot (outbound)
               └── Fan status (read-only, sudoers)
```

## Division of Responsibilities

| Who | Does what |
|---|---|
| Claude Code | Generates this repo: hardening, services, config templates, firewall rules |
| Human operator | Fills `.env` (tokens, hostname), runs the script, completes interactive auth |

Secrets never touch the repo. Ever.

## Prerequisites

- Raspberry Pi 4 (2GB+ RAM)
- Raspberry Pi OS (64-bit recommended)
- Tailscale installed and connected
- Anthropic account
- Telegram bot token from [@BotFather](https://t.me/BotFather)

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/openclaw-pi-setup
cd openclaw-pi-setup
cp .env.example .env
nano .env          # fill in your values
bash scripts/setup-openclaw.sh
# then follow CHECKLIST.md
```

## Security Model

### Three-user isolation

- `pi` — the admin account. Has sudo. Runs SSH. Does not run OpenClaw.
- `fancontrol` — a system account that owns GPIO access and runs the fan daemon. Completely separate from OpenClaw.
- `openclaw` — a system account that runs the OpenClaw process. Has no home-directory login, no GPIO access, and is blocked from reaching the LAN.

### LAN block (iptables)

An iptables `OUTPUT` DROP rule keyed to the `openclaw` UID prevents the process from reaching your local network (192.168.0.0/24). It can only reach the internet (Anthropic API, Telegram) and localhost. The rule is applied by a systemd oneshot service so it survives service restarts.

### Why fan control is a separate user

`gpiozero` requires access to `/dev/gpiomem`. Granting that to the `openclaw` process would allow arbitrary hardware access. `fancontrol` owns that privilege exclusively. OpenClaw reads fan status through a narrow sudoers-gated wrapper (`/usr/local/bin/fan-status`) that prints temperature and speed only.

### PrivateDevices and sandboxing

The `openclaw` systemd unit sets `PrivateDevices=yes`, blocking raw device access at the kernel level.

### Secrets

Secrets (tokens, API keys) live in `/etc/openclaw/secrets.env` on disk, mode 600, root:root. They are loaded by the systemd unit via `EnvironmentFile`. They never appear in this repository. The `.env` file used during setup is listed in `.gitignore` — see `.env.example` for the template.

### Anthropic API key

`ANTHROPIC_API_KEY` in `.env` is optional. If left blank, a placeholder token is written and you must complete `claude setup-token` interactively after the script runs. This is the recommended path — it keeps the key out of any file on disk.

## Files

| File | Purpose |
|---|---|
| `.env.example` | Template — copy to `.env`, fill in, never commit |
| `scripts/setup-openclaw.sh` | Full automated setup script |
| `fan/fan_control.py` | PWM fan daemon (runs as `fancontrol`) |
| `fan/fan_status.py` | Read-only fan/temp reporter |
| `config/openclaw.json.template` | OpenClaw config with placeholder substitution |
| `CHECKLIST.md` | Step-by-step human operator walkthrough |
| `CLAUDE_CODE_PROMPT.md` | The prompt used to generate this repo |

## After Setup

Follow [CHECKLIST.md](CHECKLIST.md) for the interactive steps that cannot be automated (Anthropic auth, Telegram pairing, security verification).
