"""Turning a (key, value, spec) into an Adwaita preference row.

This is the piece that makes the Waybar page work without a hand-written form
per module. Libadwaita already ships a row per primitive type — SwitchRow,
SpinRow, EntryRow, ComboRow — so "choose a control from the value's type" is a
dispatch table, not a widget toolkit.

Every row calls `on_change(key, new_value)` and nothing else. Persistence is the
caller's problem, which keeps this module free of any knowledge of which file it
is editing.
"""

from __future__ import annotations

from typing import Any, Callable

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .schema import Field, infer_kind  # noqa: E402

OnChange = Callable[[str, Any], None]


def humanise(key: str) -> str:
    """`refresh_interval_seconds` / `on-click` -> `Refresh interval seconds`."""
    text = key.replace("_", " ").replace("-", " ").strip()
    return text[:1].upper() + text[1:] if text else key


def build_row(key: str, value: Any, spec: Field | None, on_change: OnChange) -> Gtk.Widget:
    kind = spec.kind if spec and spec.kind != "auto" else infer_kind(value)
    title = spec.label if spec else humanise(key)
    subtitle = spec.help if spec else key

    if kind == "bool":
        row = Adw.SwitchRow(title=title, subtitle=subtitle)
        row.set_active(bool(value))
        row.connect("notify::active", lambda r, _p: on_change(key, r.get_active()))
        return row

    if kind in ("int", "float"):
        lo = spec.minimum if spec else 0
        hi = spec.maximum if spec else 10_000
        step = spec.step if spec else 1
        # A described field can legitimately sit outside its own advertised range
        # if it was hand-edited; widen rather than silently clamping the value.
        numeric = float(value) if isinstance(value, (int, float)) else lo
        lo = min(lo, numeric)
        hi = max(hi, numeric)
        row = Adw.SpinRow.new_with_range(lo, hi, step)
        row.set_title(title)
        row.set_subtitle(f"{subtitle} ({spec.unit})" if spec and spec.unit else subtitle)
        row.set_digits(0 if kind == "int" else 2)
        row.set_value(numeric)
        row.connect(
            "notify::value",
            lambda r, _p: on_change(
                key, int(r.get_value()) if kind == "int" else r.get_value()
            ),
        )
        return row

    if kind == "choice" and spec and spec.choices:
        labels = [label for label, _ in spec.choices]
        values = [val for _, val in spec.choices]
        row = Adw.ComboRow(title=title, subtitle=subtitle)
        row.set_model(Gtk.StringList.new(labels))
        if value in values:
            row.set_selected(values.index(value))
        row.connect(
            "notify::selected",
            lambda r, _p: on_change(key, values[r.get_selected()]),
        )
        return row

    if kind == "text":
        row = Adw.EntryRow(title=title)
        row.set_text(str(value))
        # `apply` rather than every keystroke: this writes a file another process
        # is watching, and a write per character would have the panel reloading
        # mid-word.
        row.set_show_apply_button(True)
        row.connect("apply", lambda r: on_change(key, r.get_text()))
        return row

    # Unknown shape — a nested object, a list of objects. Shown so the key is not
    # invisible, but not editable: guessing a widget here risks writing the wrong
    # structure back into a file this project may not own.
    row = Adw.ActionRow(title=title, subtitle=_preview(value))
    row.add_css_class("dim-label")
    return row


def _preview(value: Any) -> str:
    text = repr(value)
    return text if len(text) <= 80 else text[:77] + "..."
