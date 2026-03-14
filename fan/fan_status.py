#!/usr/bin/env python3
"""
fan_status.py — Read-only fan and temperature reporter for OpenClaw on Pi 4
https://github.com/YOUR_USERNAME/openclaw-pi-setup

One-shot: reads CPU temperature, calculates expected fan speed using the same
step logic as fan_control.py, and prints both. Safe to run as any user — no
GPIO access required.

Called via the /usr/local/bin/fan-status wrapper under sudoers so the 'openclaw'
user can query status without touching hardware directly.
"""

import sys

# ── Temperature/speed step logic (mirrors fan_control.py) ────────────────────

TEMP_STEP_1_C: float = 35.0
TEMP_STEP_2_C: float = 45.0
TEMP_STEP_3_C: float = 55.0
TEMP_STEP_4_C: float = 65.0
TEMP_STEP_5_C: float = 70.0

FAN_SPEED_MIN: float    = 0.50
FAN_SPEED_LOW: float    = 0.60
FAN_SPEED_MEDIUM: float = 0.70
FAN_SPEED_HIGH: float   = 0.85
FAN_SPEED_MAX: float    = 1.00

THERMAL_PATH = "/sys/class/thermal/thermal_zone0/temp"


def read_temp_c() -> float:
    with open(THERMAL_PATH) as f:
        return int(f.read().strip()) / 1000.0


def target_speed(temp: float) -> float:
    if temp >= TEMP_STEP_5_C:
        return FAN_SPEED_MAX
    elif temp >= TEMP_STEP_4_C:
        return FAN_SPEED_HIGH
    elif temp >= TEMP_STEP_3_C:
        return FAN_SPEED_MEDIUM
    elif temp >= TEMP_STEP_2_C:
        return FAN_SPEED_LOW
    else:
        return FAN_SPEED_MIN


def main() -> None:
    try:
        temp = read_temp_c()
    except OSError as exc:
        print(f"Error: could not read temperature from {THERMAL_PATH}: {exc}", file=sys.stderr)
        sys.exit(1)

    speed = target_speed(temp)
    print(f"Temp: {temp:.1f}°C")
    print(f"Fan:  {int(speed * 100)}%")


if __name__ == "__main__":
    main()
