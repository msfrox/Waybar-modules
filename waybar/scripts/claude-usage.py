#!/usr/bin/env python3
"""Claude Code plan usage, drawn as a dial for Waybar's `image` module.

Waybar's custom modules are text-only, so the previous version of this badge was
a single quarter-filled circle glyph (○◔◑◕●) carrying whichever of the two usage
windows happened to be higher. That throws away the more interesting half of the
picture: the 5-hour block and the 7-day window move on completely different time
scales, and knowing only the larger of the two tells you nothing about which one
is about to bite.

So this renders both, as one dial:

    outer ring   the 7-day window, swept clockwise from 12 o'clock
    inner pie    the current 5-hour block, quantised to 10% steps

and hands the PNG to Waybar's `image` module, whose script protocol is

    $path\\n$tooltip

There is no class line in that protocol, which is fine - the colour is baked
into the image, where it can differ per ring instead of applying to the whole
module.

PNG rather than SVG on purpose: Waybar loads images through GdkPixbuf, and SVG
support there depends on librsvg's pixbuf loader being installed, which is not
something a config file can assume. pycairo is a hard dependency either way.

Usage data comes from the same undocumented OAuth endpoint that `claude`'s own
/usage panel uses, read with the token in ~/.claude/.credentials.json and
refreshed through the stored refresh token when it has expired.
"""

import json
import math
import os
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone

import cairo

HOME = os.path.expanduser("~")
CRED = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude")),
                    ".credentials.json")
PALETTE = os.path.join(HOME, ".config/ml4w/colors/colors.json")
SETTINGS = os.path.join(HOME, ".config/waybar-control-center/claude-usage.json")
CACHE_DIR = os.path.join(HOME, ".cache/waybar-control-center")
STATE = os.path.join(CACHE_DIR, "claude-usage-state.json")
IMAGE = os.path.join(CACHE_DIR, "claude-usage.png")

UA = "claude-code/2.0.0 (external, cli)"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

# Rendered at 64px and downscaled by Waybar to its configured `size`, which
# keeps the arcs smooth without needing to know the output scale here.
CANVAS = 64

DEFAULTS = {
    # Mirrors the option set of the COSMIC YapCap applet, which is where the
    # shape of this came from.
    "usage_amount_format": "used",      # used | remaining
    "reset_time_format": "relative",    # relative | absolute
    "refresh_interval_seconds": 300,
    "show_percent": False,              # draw the block % inside the dial
}


# --------------------------------------------------------------------------
# config / palette
# --------------------------------------------------------------------------

def load_settings():
    settings = dict(DEFAULTS)
    try:
        with open(SETTINGS) as f:
            settings.update(json.load(f))
    except Exception:
        pass
    return settings


def save_settings(pairs):
    """Apply `--set key=value ...` and persist.

    The settings panel is QML, which would otherwise have to hand-assemble this
    JSON and shell-quote it. Keeping the write here means there is exactly one
    piece of code that knows the file's shape, and it is the one that also
    reads it.
    """
    settings = load_settings()
    for pair in pairs:
        key, _, value = pair.partition("=")
        if key not in DEFAULTS:
            continue
        default = DEFAULTS[key]
        if isinstance(default, bool):
            settings[key] = value.lower() in ("1", "true", "yes")
        elif isinstance(default, int):
            try:
                settings[key] = int(value)
            except ValueError:
                continue
        else:
            settings[key] = value

    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(SETTINGS))
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2)
    os.replace(tmp, SETTINGS)
    return settings


def hex_to_rgb(value, fallback=(0.5, 0.5, 0.5)):
    try:
        value = value.lstrip("#")
        return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except Exception:
        return fallback


def load_palette():
    """Matugen's palette, so the dial follows the wallpaper like everything else."""
    colors = {}
    try:
        with open(PALETTE) as f:
            colors = json.load(f)
    except Exception:
        pass
    return {
        "ok": hex_to_rgb(colors.get("primary", "#85d2e7"), (0.52, 0.82, 0.90)),
        "warn": hex_to_rgb(colors.get("tertiary", "#dcc48c"), (0.86, 0.77, 0.55)),
        "crit": hex_to_rgb(colors.get("error", "#ffb4ab"), (1.0, 0.71, 0.67)),
        "track": hex_to_rgb(colors.get("on_surface", "#dee3e5"), (0.87, 0.89, 0.90)),
    }


def level_color(pct, palette):
    if pct >= 90:
        return palette["crit"]
    if pct >= 70:
        return palette["warn"]
    return palette["ok"]


# --------------------------------------------------------------------------
# usage endpoint
# --------------------------------------------------------------------------

def fetch_usage(token):
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": UA,
        },
    )
    return json.load(urllib.request.urlopen(req, timeout=10))


def refresh_token(creds):
    o = creds["claudeAiOauth"]
    body = json.dumps({
        "grant_type": "refresh_token",
        "refresh_token": o["refreshToken"],
        "client_id": OAUTH_CLIENT_ID,
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/oauth/token",
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": UA,
                 "Accept": "application/json"},
    )
    tok = json.load(urllib.request.urlopen(req, timeout=10))
    o["accessToken"] = tok["access_token"]
    if tok.get("refresh_token"):
        o["refreshToken"] = tok["refresh_token"]
    if tok.get("expires_in"):
        o["expiresAt"] = int(time.time() * 1000) + tok["expires_in"] * 1000

    # Written atomically: a truncated credentials file logs you out of the CLI.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CRED))
    with os.fdopen(fd, "w") as f:
        json.dump(creds, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, CRED)
    return o["accessToken"]


def get_usage():
    with open(CRED) as f:
        creds = json.load(f)
    token = creds["claudeAiOauth"]["accessToken"]
    try:
        return fetch_usage(token)
    except Exception:
        return fetch_usage(refresh_token(creds))


# --------------------------------------------------------------------------
# state cache
#
# Waybar's `interval` is fixed in the bar config, so honouring a user-set
# refresh interval means polling on a short fixed tick here and only actually
# hitting the network when the cached reading has aged past it. It also gives
# the Quickshell popup a file to read instead of making its own request.
# --------------------------------------------------------------------------

def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return None


def write_state(state):
    os.makedirs(CACHE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CACHE_DIR)
    with os.fdopen(fd, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE)


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def arc(ctx, cx, cy, radius, width, fraction, color, alpha=1.0):
    """A clockwise arc starting at 12 o'clock. fraction is 0..1."""
    if fraction <= 0:
        return
    ctx.set_source_rgba(*color, alpha)
    ctx.set_line_width(width)
    ctx.set_line_cap(cairo.LINE_CAP_BUTT)
    start = -math.pi / 2
    ctx.arc(cx, cy, radius, start, start + 2 * math.pi * min(fraction, 1.0))
    ctx.stroke()


def wedge(ctx, cx, cy, radius, fraction, color, alpha=1.0):
    """A filled pie slice from 12 o'clock, clockwise. fraction is 0..1."""
    if fraction <= 0:
        return
    ctx.set_source_rgba(*color, alpha)
    start = -math.pi / 2
    ctx.move_to(cx, cy)
    ctx.arc(cx, cy, radius, start, start + 2 * math.pi * min(fraction, 1.0))
    ctx.close_path()
    ctx.fill()


def render(week_pct, block_pct, palette, show_percent):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, CANVAS, CANVAS)
    ctx = cairo.Context(surface)
    cx = cy = CANVAS / 2

    ring_r, ring_w = 27.0, 7.0
    pie_r = ring_r - ring_w / 2 - 4.0

    # Outer ring - the 7-day window.
    arc(ctx, cx, cy, ring_r, ring_w, 1.0, palette["track"], 0.18)
    arc(ctx, cx, cy, ring_r, ring_w, week_pct / 100, level_color(week_pct, palette))

    # Inner pie - the current 5-hour block, in 10% steps. Rounding here rather
    # than in the tooltip is deliberate: the dial is a glanceable indicator and
    # a continuously creeping wedge reads as noise, while the exact figure is
    # one hover away.
    stepped = round(block_pct / 10) * 10
    ctx.set_source_rgba(*palette["track"], 0.12)
    ctx.arc(cx, cy, pie_r, 0, 2 * math.pi)
    ctx.fill()
    wedge(ctx, cx, cy, pie_r, stepped / 100, level_color(block_pct, palette), 0.95)

    if show_percent:
        # Punched out of the wedge rather than drawn over it, so it stays
        # legible whatever the fill is doing underneath.
        label = str(int(round(block_pct)))
        ctx.select_font_face("Fira Sans", cairo.FONT_SLANT_NORMAL,
                             cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(20)
        _, _, tw, th, _, _ = ctx.text_extents(label)
        ctx.set_operator(cairo.OPERATOR_CLEAR)
        ctx.move_to(cx - tw / 2, cy + th / 2)
        ctx.show_text(label)
        ctx.set_operator(cairo.OPERATOR_OVER)

    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = IMAGE + ".tmp"
    surface.write_to_png(tmp)
    # Atomic, so Waybar never reads a half-written PNG and blanks the module.
    os.replace(tmp, IMAGE)


# --------------------------------------------------------------------------
# formatting
# --------------------------------------------------------------------------

def fmt_duration(seconds):
    seconds = max(0, int(seconds))
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {mins}m"
    return f"{mins}m"


def fmt_reset(iso, settings):
    when = datetime.fromisoformat(iso)
    if settings["reset_time_format"] == "absolute":
        return when.astimezone().strftime("%a %H:%M")
    return fmt_duration((when - datetime.now(timezone.utc)).total_seconds())


def bar(pct, width=10):
    filled = round(min(100.0, max(0.0, pct)) / 100 * width)
    return "█" * filled + "░" * (width - filled)


def hint(error):
    """Turn the raw failure into the thing you actually have to do about it.

    An empty dial with a stack trace in the tooltip is only marginally better
    than an empty dial, and these three cases cover essentially every failure
    this script has.
    """
    text = str(error)
    if "invalid_grant" in text or "400" in text:
        # Both the access token and the refresh token have expired, which
        # happens after a long enough gap between Claude Code sessions. Nothing
        # here can recover it - the refresh token is the recovery mechanism.
        # `claude` alone just starts a session against the dead credentials and
        # does not re-authenticate; /login is what actually replaces them.
        return "Both tokens have expired. Run `claude /login` in a terminal to sign in again."
    if "429" in text:
        return "Rate limited by the usage endpoint. It will recover on its own."
    if "No such file" in text or "credentials" in text:
        return "~/.claude/.credentials.json is missing. Run `claude /login` in a terminal."
    return "Check ~/.claude/.credentials.json and network access."


def main():
    if "--set" in sys.argv:
        save_settings(sys.argv[sys.argv.index("--set") + 1:])

    settings = load_settings()
    palette = load_palette()

    state = read_state()
    force = "--refresh" in sys.argv

    if state is None:
        stale = True
    else:
        age = time.time() - state["fetched_at"]
        # A reading that failed is retried on the next tick rather than being
        # held for the full refresh interval - otherwise one transient 429 or a
        # token refresh mid-session freezes the dial for five minutes. Still
        # backed off to a minute so a persistent failure is not a hot loop
        # against a rate-limited endpoint.
        stale = age >= (60 if state.get("error") else settings["refresh_interval_seconds"])

    if force or stale:
        try:
            data = get_usage()
            five = data.get("five_hour") or {}
            seven = data.get("seven_day") or {}
            state = {
                "fetched_at": time.time(),
                "block_pct": round(five.get("utilization") or 0),
                "week_pct": round(seven.get("utilization") or 0),
                "block_resets_at": five.get("resets_at"),
                "week_resets_at": seven.get("resets_at"),
                "error": None,
                "error_hint": None,
            }
            write_state(state)
        except Exception as exc:
            # Keep serving the last good reading rather than blanking the dial;
            # the tooltip is where the failure gets reported.
            state = state or {"fetched_at": time.time(), "block_pct": 0,
                              "week_pct": 0, "block_resets_at": None,
                              "week_resets_at": None}
            state["error"] = str(exc)
            # Stored, not just formatted into the tooltip, so the Quickshell
            # panel shows the same actionable line without duplicating the
            # mapping.
            state["error_hint"] = hint(exc)
            write_state(state)

    block_pct = state["block_pct"]
    week_pct = state["week_pct"]

    render(week_pct, block_pct, palette, settings["show_percent"])

    shown_block = block_pct if settings["usage_amount_format"] == "used" else 100 - block_pct
    shown_week = week_pct if settings["usage_amount_format"] == "used" else 100 - week_pct
    word = "used" if settings["usage_amount_format"] == "used" else "left"

    if state.get("error"):
        tooltip = f"Claude usage unavailable\n{state['error']}\n\n{hint(state['error'])}"
    else:
        lines = [
            "󰚩 Claude Code Usage",
            "━━━━━━━━━━━━━━━━━━━━",
            f"5h block : {bar(shown_block)} {shown_block}% {word}",
        ]
        if state.get("block_resets_at"):
            lines.append(f"           resets {fmt_reset(state['block_resets_at'], settings)}")
        lines.append(f"7-day    : {bar(shown_week)} {shown_week}% {word}")
        if state.get("week_resets_at"):
            lines.append(f"           resets {fmt_reset(state['week_resets_at'], settings)}")
        lines += ["", "Ring: 7-day  ·  Fill: 5h block",
                  "Left-click: panel | Right-click: refresh"]
        tooltip = "\n".join(lines)

    print(IMAGE)
    print(tooltip.replace("\n", "\\n"))


if __name__ == "__main__":
    main()
