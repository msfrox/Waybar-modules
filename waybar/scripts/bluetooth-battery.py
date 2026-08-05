#!/usr/bin/env python3
"""Connected-Bluetooth-device battery level for the bar module.

Waybar's own `bluetooth` module can render `{device_battery_percentage}` via
`format-connected-battery`, but only for devices that expose BlueZ's
`org.bluez.Battery1` interface. Neither device that actually connects to this
machine does - both are soundcore (Anker) speakers/earbuds, and Anker reports
battery over its own app's proprietary channel, not a standard profile BlueZ
can see. UPower has no entry for them either (`upower -e` lists only the
laptop battery and AC line). So the native format string always renders
`{device_battery_percentage}` blank here, and this script exists to do the
same job as `format-connected-battery`, just checking both possible sources
instead of hard-requiring the one BlueZ happens to expose.

`bluetoothctl info <mac>` prints a "Battery Percentage:" line exactly when
Battery1 is present, so that's cheaper than talking D-Bus directly and matches
how this repo's other scripts shell out to a CLI rather than binding a D-Bus
library. UPower is the fallback for devices BlueZ doesn't surface a battery
for but the kernel/UPower's own bluetooth backend still reads.

Degrades to an empty `text` when nothing is connected or nothing reports a
level, so the bar module just goes invisible instead of showing a stale or
wrong percentage.
"""

import json
import re
import subprocess


def run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def connected_devices():
    """[(mac, name), ...] from `bluetoothctl devices Connected`."""
    devices = []
    for line in run(["bluetoothctl", "devices", "Connected"]).splitlines():
        parts = line.strip().split(" ", 2)
        if len(parts) == 3 and parts[0] == "Device":
            devices.append((parts[1], parts[2]))
    return devices


def battery_from_bluez(mac):
    for line in run(["bluetoothctl", "info", mac]).splitlines():
        stripped = line.strip()
        if stripped.startswith("Battery Percentage:"):
            match = re.search(r"\((\d+)\)", stripped)
            if match:
                return int(match.group(1))
    return None


def battery_from_upower(mac):
    """UPower's bluetooth backend names devices by MAC with underscores, e.g.
    .../headset_dev_AA_BB_CC_DD_EE_FF. Substring match keeps this from caring
    about the exact prefix (headset_, mouse_, etc)."""
    needle = mac.replace(":", "_")
    for path in run(["upower", "-e"]).splitlines():
        path = path.strip()
        if needle not in path:
            continue
        for line in run(["upower", "-i", path]).splitlines():
            stripped = line.strip()
            if stripped.startswith("percentage:"):
                digits = stripped.split(":", 1)[1].strip().rstrip("%")
                if digits.isdigit():
                    return int(digits)
    return None


if __name__ == "__main__":
    devices = [
        {"name": name, "battery": battery_from_bluez(mac) or battery_from_upower(mac)}
        for mac, name in connected_devices()
    ]
    known = [d for d in devices if d["battery"] is not None]

    if not known:
        # Nothing connected, or nothing connected reports a level - either
        # way there is no percentage to put on the bar.
        print(json.dumps({
            "text": "",
            "tooltip": "\n".join(d["name"] for d in devices) or "No Bluetooth devices connected",
            "class": "connected" if devices else "disconnected",
        }))
    else:
        lowest = min(known, key=lambda d: d["battery"])
        print(json.dumps({
            "text": f" {lowest['battery']}%",
            "tooltip": "\n".join(
                f"{d['name']}: {d['battery']}%" if d["battery"] is not None else f"{d['name']}: connected"
                for d in devices
            ),
            "class": "low" if lowest["battery"] <= 20 else "connected",
        }))
