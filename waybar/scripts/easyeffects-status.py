#!/usr/bin/env python3
"""EasyEffects state for the audio panel, as one JSON blob.

EasyEffects is a PipeWire filter chain, so it shows up in the panel's device
list as a plain virtual sink named "Easy Effects Sink" with no hint that it is
an effects processor or which preset it is running. Everything interesting about
it is only reachable through its own CLI.

  easyeffects -p                     list presets, grouped by Output:/Input:
  easyeffects -a output              the last loaded preset of that type
  easyeffects -b 3                   global bypass state: 1 on, 2 off

Degrades to nulls when EasyEffects is not installed, so the panel only has to
check for null.
"""

import json
import shutil
import subprocess


def run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def presets():
    """`-p` prints two numbered lists under 'Output presets:' / 'Input presets:'."""
    output, inputs = [], []
    target = None
    for line in run(["easyeffects", "-p"]).splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        lowered = stripped.lower()
        if lowered.startswith("output preset"):
            target = output
            continue
        if lowered.startswith("input preset"):
            target = inputs
            continue
        if target is None:
            continue
        # Rows are "<index>\t<name>"; the name can contain spaces, so split on
        # the tab rather than on whitespace. Requiring the numbered form also
        # filters out the "No input presets." message, which EasyEffects prints
        # in place of the section header rather than under it.
        index, tab, name = stripped.partition("\t")
        if not tab or not index.strip().isdigit():
            continue
        name = name.strip()
        if name:
            target.append(name)
    return output, inputs


if __name__ == "__main__":
    if not shutil.which("easyeffects"):
        print(json.dumps({"available": False}))
        raise SystemExit(0)

    output_presets, input_presets = presets()
    bypass = run(["easyeffects", "-b", "3"]).strip()

    print(json.dumps({
        "available": True,
        # `--gapplication-service` is how it runs as a background processor; if
        # nothing is running, the filter chain is not in the graph at all.
        "running": bool(run(["pgrep", "-x", "easyeffects"]).strip()),
        "output_preset": run(["easyeffects", "-a", "output"]).strip() or None,
        "input_preset": run(["easyeffects", "-a", "input"]).strip() or None,
        "output_presets": output_presets,
        "input_presets": input_presets,
        # -b reports 1 for enabled, 2 for disabled. Anything else means the
        # query failed, which is not the same as "effects are on".
        "bypassed": True if bypass == "1" else False if bypass == "2" else None,
    }))
