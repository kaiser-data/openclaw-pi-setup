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
as-openclaw claude setup-token

# Step 2: register that token with OpenClaw (will prompt you to paste it)
as-openclaw openclaw models auth paste-token --provider anthropic

# Verify it worked
as-openclaw openclaw models status
```

> `as-openclaw` is a helper installed by the setup script. It runs any command
> as the `openclaw` user with the correct environment.

`claude setup-token` prints a URL. Open it in a browser, log in with your Anthropic account,
approve access, and copy the long-lived token it gives you. Then paste it when
`paste-token` prompts you.

Note: if you prefer a plain API key, set `ANTHROPIC_API_KEY` in
`/etc/openclaw/secrets.env` (mode 600) and restart the gateway instead.

### Step B — Verify Telegram token

```bash
sudo nano /etc/openclaw/secrets.env
# Confirm TELEGRAM_BOT_TOKEN is correctly set
```

### Step C — Restart and verify

```bash
sudo systemctl restart openclaw-gateway
sleep 5
sudo systemctl status openclaw-gateway   # must show: active (running)
```

If it shows `active (running)` but then fails shortly after, check the logs:

```bash
sudo journalctl -u openclaw-gateway -n 30 --no-pager
```

Common issues seen during real installs:

| Error in log | Fix |
|---|---|
| `Unable to create fallback OpenClaw temp dir` | `/tmp` not writable — check `ReadWritePaths` in service override includes `/tmp` |
| `Gateway start blocked: set gateway.mode=local` | Run `as-openclaw openclaw config set gateway.mode local` then restart |
| `Invalid config … Unrecognized key` | Run `as-openclaw openclaw doctor --fix` then restart |

### Step D — Pair your Telegram bot

1. Open Telegram and send any message to your bot.
2. The bot replies with a pairing code.
3. Back on the Pi, approve it:

```bash
as-openclaw openclaw pairing list telegram
as-openclaw openclaw pairing approve telegram <code>
```

---

## Phase 4 — Security verification (do not skip)

```bash
# LAN block is active
sudo iptables -L OUTPUT | grep DROP

# openclaw cannot reach LAN (must fail/timeout)
as-openclaw curl -m 3 http://192.168.0.1

# openclaw CAN reach internet (must connect)
as-openclaw curl -m 5 https://api.anthropic.com

# fan control service is running
sudo systemctl status fan-control

# openclaw cannot touch fan controller directly (must be denied)
as-openclaw python3 /usr/local/bin/fan_control.py

# fan status read-only wrapper works (must print temp and fan speed)
as-openclaw sudo /usr/local/bin/fan-status

# OpenClaw gateway status
as-openclaw openclaw gateway status

# Model and auth verification
as-openclaw openclaw models status
```

All checks must pass before you proceed.

---

## Phase 5 — Access from your MacBook Air

1. Ensure Tailscale is running on your Mac.
2. Open in browser: `https://${TAILSCALE_HOSTNAME}`
3. You should see the OpenClaw Control UI.

If it does not load, check:
- `sudo systemctl status openclaw-gateway` on the Pi
- `tailscale status` on both devices
- Tailscale Serve is configured (the script sets this up)

---

## Ongoing Maintenance

| Task | Command |
|---|---|
| View OpenClaw logs | `sudo journalctl -u openclaw-gateway -f` |
| View fan logs | `sudo journalctl -u fan-control -f` |
| Update OpenClaw | `as-openclaw openclaw update --channel stable` |
| Renew Anthropic token | `as-openclaw claude setup-token` then `as-openclaw openclaw models auth paste-token --provider anthropic` |
| Gateway status | `as-openclaw openclaw gateway status` |
| Model/auth status | `as-openclaw openclaw models status` |
| Health check | `as-openclaw openclaw doctor` |
| Token usage | Send `/status` to your Telegram bot |
| Compact session | Send `/compact` to your Telegram bot |
| Verify iptables survived reboot | `sudo iptables -L OUTPUT \| grep DROP` |

---

## Red Flags — Stop and Investigate

Stop and investigate if you observe any of the following:

- `openclaw` process using >500MB RAM consistently
- `fan-control` service shown as inactive or failed
- `as-openclaw openclaw doctor` reporting auth errors
- DROP rule missing from iptables OUTPUT after reboot
- Bot responding with model errors (run `as-openclaw claude setup-token` again)
- `/etc/openclaw/secrets.env` permissions are not 600
