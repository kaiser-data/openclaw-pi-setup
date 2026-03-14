# CHECKLIST.md — OpenClaw Pi Setup Operator Walkthrough

Work through each phase in order. Do not skip the security verification.

---

## Phase 1 — Pre-flight (before running the script)

SSH into your Pi and verify the environment is clean:

```bash
# Node.js — 22.x is fine, script will upgrade to 24
node --version

# iptables OUTPUT chain — should be clean (no DROP rules yet)
sudo iptables -L OUTPUT

# openclaw user — should not exist yet
cat /etc/passwd | grep openclaw

# fan_control.py — should already be deployed if fan is set up
ls /usr/local/bin/fan_control.py

# Tailscale — Pi and Mac both must be connected
tailscale status
```

If `fan_control.py` is missing, the script will deploy it from `fan/fan_control.py`.
If `openclaw` user exists, the script will warn and skip creation (idempotent).

---

## Phase 2 — Run the script

```bash
bash scripts/setup-openclaw.sh
```

The script will pause before applying services and ask for confirmation.
Read the summary carefully before typing `y`.

---

## Phase 3 — Interactive steps (human must complete these)

These steps cannot be automated. They require browser interaction or secret entry.

### Step A — Anthropic authentication

If `ANTHROPIC_API_KEY` was left blank in `.env`, a dummy token was written.
You must run both of these commands:

```bash
# Step 1: get a subscription token via the Claude CLI browser flow
sudo -u openclaw -i claude setup-token

# Step 2: register that token with OpenClaw
sudo -u openclaw -i openclaw models auth setup-token --provider anthropic

# Verify it worked
sudo -u openclaw openclaw models status
```

`claude setup-token` prints a URL. Open it in a browser, log in with your Anthropic account,
approve access, and paste the token back into the terminal. Both steps are required.

Note: if you prefer an API key over the subscription token, set `ANTHROPIC_API_KEY` in
`/etc/openclaw/secrets.env` instead and restart the service.

### Step B — Verify Telegram token

```bash
sudo nano /etc/openclaw/secrets.env
# Confirm TELEGRAM_BOT_TOKEN is correctly set
```

### Step C — Restart and verify

```bash
sudo systemctl restart openclaw-gateway
sudo systemctl status openclaw-gateway   # must show: active (running)
```

### Step D — Pair your Telegram bot

1. Open Telegram and send any message to your bot.
2. The bot replies with a pairing code.
3. Back on the Pi, approve it:

```bash
sudo -u openclaw openclaw pairing list telegram
sudo -u openclaw openclaw pairing approve telegram <code>
```

---

## Phase 4 — Security verification (do not skip)

```bash
# LAN block is active
sudo iptables -L OUTPUT | grep DROP

# openclaw cannot reach LAN (must fail/timeout)
sudo -u openclaw curl -m 3 http://192.168.0.1

# openclaw CAN reach internet (must connect)
sudo -u openclaw curl -m 5 https://api.anthropic.com

# fan control service is running
sudo systemctl status fan-control

# openclaw cannot touch fan controller directly (must be denied)
sudo -u openclaw python3 /usr/local/bin/fan_control.py

# fan status read-only wrapper works (must print temp and fan speed)
sudo -u openclaw sudo /usr/local/bin/fan-status

# OpenClaw gateway status
sudo -u openclaw openclaw gateway status

# Model and auth verification
sudo -u openclaw openclaw models status
```

All checks must pass before you proceed.

---

## Phase 5 — Access from your MacBook Air

1. Ensure Tailscale is running on your Mac.
2. Open in browser: `https://${TAILSCALE_HOSTNAME}`
3. You should see the OpenClaw Control UI.

If it does not load, check:
- `sudo systemctl status openclaw` on the Pi
- `tailscale status` on both devices
- Tailscale Serve is configured (the script sets this up)

---

## Ongoing Maintenance

| Task | Command |
|---|---|
| View OpenClaw logs | `sudo journalctl -u openclaw-gateway -f` |
| View fan logs | `sudo journalctl -u fan-control -f` |
| Update OpenClaw | `sudo -u openclaw openclaw update --channel stable` |
| Renew Anthropic token | `sudo -u openclaw -i claude setup-token` then `sudo -u openclaw -i openclaw models auth setup-token --provider anthropic` |
| Gateway status | `sudo -u openclaw openclaw gateway status` |
| Model/auth status | `sudo -u openclaw openclaw models status` |
| Health check | `sudo -u openclaw openclaw doctor` |
| Token usage | Send `/status` to your Telegram bot |
| Compact session | Send `/compact` to your Telegram bot |
| Verify iptables survived reboot | `sudo iptables -L OUTPUT \| grep DROP` |

---

## Red Flags — Stop and Investigate

Stop and investigate if you observe any of the following:

- `openclaw` process using >500MB RAM consistently
- `fan-control` service shown as inactive or failed
- `openclaw doctor` reporting auth errors
- DROP rule missing from iptables OUTPUT after reboot
- Bot responding with model errors (check `claude setup-token` was completed)
- `/etc/openclaw/secrets.env` permissions are not 600
