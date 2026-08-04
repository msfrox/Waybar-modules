# Patches to ML4W's own Quickshell files

These files ship with the [ML4W dotfiles](https://github.com/mylinuxforwork/dotfiles),
so this repo does not carry copies of them — replacing them wholesale would fight the
next ML4W update. The changes are small and listed here instead.

Paths are relative to `~/.config/quickshell/`.

---

## `CustomTheme/Theme.qml` — load the Matugen palette at startup

**Symptom:** every Quickshell window (calendar, power menu, sidebar, statusbar) comes up
in a palette that has nothing to do with the wallpaper — on this machine a maroon card on
a teal bar — and only corrects itself after the next wallpaper change.

**Cause:** `Theme.qml` holds a hardcoded fallback palette and a `Process` that reads the
real one from `~/.config/ml4w/colors/colors.json`. That process is never started at
startup: `Component.onCompleted: reloadTheme()` is commented out and the `Process` has no
`running: true`. The only thing that ever runs it is the Matugen post-hook
(`qs ipc call theme-manager reload`, fired from `ml4w-wallpaper` and
`ml4w/listeners/gtk-theme-switcher.sh`) — and that fires on *change*, not on login.

**Fix:** uncomment the last line.

```qml
    // Load the JSON colors automatically when Quickshell starts.
    Component.onCompleted: reloadTheme()
}
```

Verify:

```bash
python3 -c "import json;d=json.load(open('$HOME/.config/ml4w/colors/colors.json'));print(d['primary'])"
```

should match what the calendar actually draws with.

---

## `CalendarApp/CalendarWindow.qml` — move the popup to the bottom-right

The stock window is anchored top-centre, which is wrong once the bar itself is at the
bottom. Two edits.

```qml
    // was: anchors { top: true }
    anchors {
        bottom: true
        right: true
    }
```

```qml
    // The window is 380x380 but the visible card is inset 20px all round for its
    // drop shadow, so a 45px bottom margin leaves the card ~10px clear of the
    // 55px bar, and a 0px right margin sits it 20px in from the screen edge.
    property real currentBottomMargin: isOpen ? 45 : -820

    margins {
        bottom: root.currentBottomMargin
        right: 0
    }

    Behavior on currentBottomMargin {   // was: on currentTopMargin
```

The off-screen value stays large and negative (`-820`) so the slide-out clears the
screen regardless of the card's height.

Adjust `45` to `<your bar's reserved height> - 10`. Read the real number with:

```bash
hyprctl monitors -j | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['reserved'])"
```

The fourth element is the bottom reservation.
