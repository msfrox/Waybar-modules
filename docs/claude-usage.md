# Claude usage dial

A two-window usage indicator for the bar, plus a panel carrying the display options.

```
outer ring   7-day window, swept clockwise from 12 o'clock
inner pie    current 5-hour block, quantised to 10% steps
```

## Why a rendered image

The previous badge was one quarter-filled circle glyph (`○◔◑◕●`) showing whichever of the
two usage windows happened to be higher. That is close to the least useful summary of
them: the 5-hour block and the 7-day window move on completely different time scales, and
the *smaller* one is frequently the one about to matter.

Waybar's `custom` modules are text-only, and no glyph set expresses two independent
percentages. Waybar's **`image`** module can render an arbitrary file, and its script
protocol is:

```
$path\n$tooltip
```

There is no class line — which is fine, because the colour is baked into the image, where
each ring can carry its own level instead of one class colouring the whole module.

> [!note] PNG, not SVG
> Waybar loads images through GdkPixbuf, whose SVG support depends on librsvg's pixbuf
> loader being installed. A config file cannot assume that. `pycairo` is a hard dependency
> either way, so the dial is drawn and written as PNG, atomically, so Waybar never reads a
> half-written file and blanks the module.

The 5-hour fill is rounded to 10% on purpose. The dial is a glanceable indicator and a
continuously creeping wedge reads as noise; the exact figure is one hover away.

## Files

| Path | Role |
|---|---|
| `waybar/scripts/claude-usage.py` | fetch, cache, render, tooltip, settings |
| `~/.cache/waybar-control-center/claude-usage-state.json` | last good reading |
| `~/.cache/waybar-control-center/claude-usage.png` | the dial |
| `~/.config/waybar-control-center/claude-usage.json` | settings |

The script owns all four. The Quickshell panel reads the state file and writes settings
through `claude-usage.py --set key=value` — two processes hand-editing the same JSON would
be a race for no benefit.

## Refresh

Waybar's `interval` is fixed in the bar config, so honouring a user-set refresh interval
means polling on a short fixed tick (60s) and only hitting the network once the cached
reading has aged past the configured interval. A reading that **failed** is retried after
60s rather than held for the full interval — otherwise one transient 429, or a token
refresh landing mid-session, freezes the dial for five minutes.

## Panel options

A port of the option set the COSMIC [YapCap](https://github.com/TopiCsarno/YapCap) applet
exposes, which is where the idea came from:

| Option | Values |
|---|---|
| Show | Used · Remaining |
| Reset times | Relative · Absolute |
| Refresh every | 1m · 5m · 10m · 30m |
| Dial label | None · Session % |

Plus a refresh action and a link to the full `ccusage weekly --breakdown`.

The usage bars in the panel always fill in the **used** direction whichever way the number
is phrased — a bar that empties as you consume quota reads backwards.

## Where the numbers come from

`https://api.anthropic.com/api/oauth/usage` — the same undocumented endpoint `claude`'s own
`/usage` panel uses — authenticated with the token in `~/.claude/.credentials.json`, and
refreshed through the stored refresh token when the access token has expired.

> [!warning] The failure mode this design exists to avoid
> An earlier version read a cache file written by a statusline plugin. That cache only
> updated when the plugin's statusline command fired, which never happens in headless
> sessions — so the badge showed valid-looking, permanently stale numbers with no error.
> Nothing here depends on any other process having run.

Failures are reported with the fix rather than a status code:

| Failure | What it means |
|---|---|
| `invalid_grant` / 400 | Both tokens have expired. Run `claude` in a terminal once to log in again — the refresh token *is* the recovery mechanism, so retrying cannot help. |
| 429 | Rate limited by the endpoint. Recovers on its own. |
| missing credentials | Log in with `claude` once. |

The hint is stored in the state file, not just formatted into the tooltip, so the panel
shows the same line without duplicating the mapping.

## Bar height

The old text badge had the tallest label on the bar, and Waybar measures the bar from its
tallest child — so that module's `font-size` silently set the whole bar's height, and
Hyprland's reserved area with it. An image has a fixed box, so that coupling is gone.
Check with:

```bash
hyprctl monitors -j | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['reserved'])"
```
