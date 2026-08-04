#!/usr/bin/env python3
"""Connection details for the Quickshell network panel, as one JSON blob.

Quickshell.Networking covers what NetworkManager exposes over its object model -
SSID, signal, security, IP - but not link rate or channel frequency, and it has
no idea Tailscale exists. Rather than scattering `Process` blocks through the
QML, the panel runs this once per refresh and reads one object.

Everything here degrades to nulls: a machine with no Tailscale, no wifi, or no
active connection still gets valid JSON, so the QML only ever has to check for
null and never for a failed command.
"""

import json
import re
import shutil
import subprocess


def run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=8)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def wifi_details():
    """The active access point, from `nmcli -t` (colon-separated, script-stable)."""
    if not shutil.which("nmcli"):
        return None

    # `--rescan no` matters: a bare `nmcli dev wifi` kicks off a fresh scan and
    # blocks for several seconds while the radio sweeps, which is far too slow
    # for something a panel calls on every refresh. The cached scan is exactly
    # what the panel's own network list is already showing anyway.
    active = None
    for line in run(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,RATE,FREQ,SECURITY",
                     "dev", "wifi", "list", "--rescan", "no"]).splitlines():
        # SSIDs can contain colons; nmcli escapes them as "\:", so split on
        # unescaped separators only.
        parts = [p.replace("\\:", ":") for p in re.split(r"(?<!\\):", line)]
        if len(parts) >= 6 and parts[0] == "yes":
            active = {
                "ssid": parts[1],
                "signal": int(parts[2]) if parts[2].isdigit() else None,
                "rate": parts[3] or None,
                "frequency": parts[4] or None,
                "security": parts[5] or None,
            }
            break

    if active is None:
        return None

    # Find the interface carrying it, then its addressing.
    iface = None
    for line in run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]).splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and parts[1] == "wifi" and parts[2] == "connected":
            iface = parts[0]
            break

    if iface:
        active["interface"] = iface
        for line in run(["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS",
                         "device", "show", iface]).splitlines():
            key, _, value = line.partition(":")
            if key.startswith("IP4.ADDRESS") and "address" not in active:
                active["address"] = value
            elif key == "IP4.GATEWAY" and value:
                active["gateway"] = value
            elif key.startswith("IP4.DNS") and "dns" not in active:
                active["dns"] = value

    return active


def tailscale_details():
    if not shutil.which("tailscale"):
        return None

    raw = run(["tailscale", "status", "--json"])
    if not raw:
        return {"state": "Unavailable"}

    try:
        data = json.loads(raw)
    except Exception:
        return {"state": "Unavailable"}

    self_node = data.get("Self") or {}
    peers = (data.get("Peer") or {}).values()

    exit_node = None
    for peer in peers:
        if peer.get("ExitNode"):
            exit_node = (peer.get("DNSName") or "").rstrip(".").split(".")[0]
            break

    return {
        "state": data.get("BackendState"),
        # DNSName comes back fully qualified with a trailing dot; the short
        # hostname is what anyone actually recognises.
        "hostname": (self_node.get("DNSName") or "").rstrip(".").split(".")[0] or None,
        "ip": (self_node.get("TailscaleIPs") or [None])[0],
        "tailnet": (data.get("CurrentTailnet") or {}).get("Name"),
        "magic_dns": data.get("MagicDNSSuffix"),
        "online": self_node.get("Online"),
        "exit_node": exit_node,
        "peers_total": len(peers),
        "peers_online": sum(1 for p in peers if p.get("Online")),
    }


if __name__ == "__main__":
    print(json.dumps({"wifi": wifi_details(), "tailscale": tailscale_details()}))
