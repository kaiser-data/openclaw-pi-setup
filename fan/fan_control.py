#!/usr/bin/env python3
"""
fan_control.py — PWM fan daemon for OpenClaw on Raspberry Pi 4
https://github.com/YOUR_USERNAME/openclaw-pi-setup

Runs as the 'fancontrol' system user. Reads CPU temperature every 5 seconds
and adjusts fan speed via PWMOutputDevice on the configured GPIO pin.

Configuration:
  Set FAN_GPIO_PIN in the environment (default: 14).
  The systemd unit (fan-control.service) sets this from .env.

Minimum speed is 0.50 (50%) to prevent stall at low RPM.
On SIGTERM, fan is set to 100% as a safety measure before exit.
"""

import os
import signal
import sys
import time

from gpiozero import PWMOutputDevice

# ── Configuration ─────────────────────────────────────────────────────────────

FAN_GPIO_PIN: int = int(os.environ.get("FAN_GPIO_PIN", 14))

# Temperature thresholds (°C) and corresponding fan speeds (0.0–1.0)
# Adjust these to suit your enclosure and cooling needs.
TEMP_STEP_1_C: float = 35.0   # Below this: minimum speed
TEMP_STEP_2_C: float = 45.0   # Warm: low speed
TEMP_STEP_3_C: float = 55.0   # Getting hot: medium speed
TEMP_STEP_4_C: float = 65.0   # Hot: high speed
TEMP_STEP_5_C: float = 70.0   # Very hot: full speed

FAN_SPEED_MIN: float    = 0.50  # Always spinning — prevents stall
FAN_SPEED_LOW: float    = 0.60
FAN_SPEED_MEDIUM: float = 0.70
FAN_SPEED_HIGH: float   = 0.85
FAN_SPEED_MAX: float    = 1.00

POLL_INTERVAL_S: float = 5.0   # Seconds between temperature reads

# ── Helpers ───────────────────────────────────────────────────────────────────

THERMAL_PATH = "/sys/class/thermal/thermal_zone0/temp"


def read_temp_c() -> float:
    """Read CPU temperature from sysfs. Returns degrees Celsius."""
    with open(THERMAL_PATH) as f:
        return int(f.read().strip()) / 1000.0


def target_speed(temp: float) -> float:
    """Map temperature to a fan duty cycle."""
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


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    fan = PWMOutputDevice(FAN_GPIO_PIN, initial_value=FAN_SPEED_MIN)

    def handle_sigterm(signum, frame):
        """On shutdown, spin fan to 100% as a safety measure, then exit cleanly."""
        print("SIGTERM received — setting fan to 100% and exiting.", flush=True)
        fan.value = FAN_SPEED_MAX
        time.sleep(1)
        fan.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_sigterm)

    print(f"fan_control started on GPIO {FAN_GPIO_PIN}", flush=True)

    while True:
        try:
            temp = read_temp_c()
            speed = target_speed(temp)
            fan.value = speed
            print(f"Temp: {temp:.1f}°C  Fan: {int(speed * 100)}%", flush=True)
        except Exception as exc:
            print(f"Error reading temperature: {exc}", flush=True)

        time.sleep(POLL_INTERVAL_S)


if __name__ == "__main__":
    main()
