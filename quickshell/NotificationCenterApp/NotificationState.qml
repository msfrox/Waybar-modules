pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification daemon.
//
// Only one process on the bus can own org.freedesktop.Notifications, so taking
// this over means swaync has to go — see ~/.config/hypr/shehan/notifications.lua
// for the kill, and docs/notifications.md for why.
//
// Everything notification-shaped hangs off this one singleton: the panel reads
// `list`, the toasts read `toasts`, the Control Center reads `count` and `dnd`.
// It is a singleton rather than state inside the panel because the toasts have
// to keep firing while the panel is closed and unmapped.
Singleton {
    id: root

    // --- STORE ---------------------------------------------------------------
    // The server owns the objects; `trackedNotifications` is its live model and
    // the only thing keeping a Notification alive. Reversed here because the
    // server appends and the panel wants newest first.
    readonly property list<var> list: [...server.trackedNotifications.values].reverse()
    readonly property int count: server.trackedNotifications.values.length

    // Notifications currently showing as a toast. Separate from `list`: a toast
    // disappearing must not clear the panel entry, and a panel entry dismissed
    // by hand must take its toast with it.
    property list<var> toasts: []

    // Arrival times, keyed by notification id. A Notification carries no
    // timestamp of its own, so the "5m ago" line has to be recorded here as
    // they land. Entries are dropped in dropStale() when their notification goes.
    property var arrivals: ({})

    // Ticks the relative timestamps in the panel. One timer for the whole list
    // rather than one per row.
    property int clockTick: 0

    function ageTextFor(n: var): string {
        root.clockTick // re-evaluate on every tick
        const at = root.arrivals[n.id]
        if (at === undefined) return ""
        const secs = Math.floor((Date.now() - at) / 1000)
        if (secs < 60) return "now"
        if (secs < 3600) return Math.floor(secs / 60) + "m ago"
        if (secs < 86400) return Math.floor(secs / 3600) + "h ago"
        return Math.floor(secs / 86400) + "d ago"
    }

    // --- DO NOT DISTURB ------------------------------------------------------
    // DND suppresses the toast, it does not drop the notification — the panel
    // still fills up, which is the behaviour swaync had and the one that makes
    // DND safe to leave on.
    property bool dnd: false

    function toggleDnd(): void {
        root.dnd = !root.dnd
        if (root.dnd) root.toasts = []
        settings.dnd = root.dnd
        settingsFile.writeAdapter()
    }

    // --- ACTIONS -------------------------------------------------------------
    function clearAll(): void {
        // dismiss() mutates trackedNotifications, so iterate over a copy.
        for (const n of [...server.trackedNotifications.values]) n.dismiss()
        root.toasts = []
    }

    function dismiss(n: var): void {
        root.dropToast(n)
        n.dismiss()
    }

    function togglePanel(): void {
        Quickshell.execDetached(["qs", "ipc", "call", "notifications", "toggle"])
    }

    // --- TOASTS --------------------------------------------------------------
    // Timeouts mirror the values that were in ~/.config/swaync/config.json, so
    // the swap is not felt: 2s low, 4s normal, 6s critical. A notification that
    // asks for its own timeout gets it; 0 means "until dismissed".
    function timeoutFor(n: var): int {
        if (n.expireTimeout > 0) return n.expireTimeout
        if (n.expireTimeout === 0) return 0
        if (n.urgency === NotificationUrgency.Critical) return 6000
        if (n.urgency === NotificationUrgency.Low) return 2000
        return 4000
    }

    function dropToast(n: var): void {
        root.toasts = root.toasts.filter(t => t !== n)
        // A transient notification is an OSD, not a message — it was only ever
        // meant to be the popup, so it leaves the panel with its toast.
        if (n.transient && n.tracked) n.dismiss()
    }

    NotificationServer {
        id: server

        // Survive a QML hot-reload without dropping what is already on screen.
        keepOnReload: true

        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        imageSupported: true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: (notification) => {
            // Nothing keeps a Notification alive unless it is tracked — an
            // untracked one is destroyed the moment this handler returns, and
            // any reference kept to it dangles. So track everything, including
            // transients, and let dropToast() clear those again.
            notification.tracked = true
            root.arrivals[notification.id] = Date.now()

            if (root.dnd) {
                if (notification.transient) notification.dismiss()
                return
            }
            root.toasts = [...root.toasts, notification]
        }
    }

    // --- PERSISTENCE ---------------------------------------------------------
    // Only DND is persisted. The notification list deliberately is not: a list
    // restored from before a reboot is noise, and swaync did not keep one either.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/waybar-control-center/notifications.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.dnd = settings.dnd

        // No settings file yet is the normal first-run case, not an error.
        onLoadFailed: (error) => { root.dnd = false }

        JsonAdapter {
            id: settings
            property bool dnd: false
        }
    }

    // Drives the "5m ago" line, and garbage-collects arrival times for
    // notifications that are gone. Cheap enough to leave running.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.clockTick++
            const live = {}
            for (const n of server.trackedNotifications.values) {
                if (root.arrivals[n.id] !== undefined) live[n.id] = root.arrivals[n.id]
            }
            root.arrivals = live
        }
    }

    IpcHandler {
        target: "notification-state"
        function toggleDnd(): void { root.toggleDnd() }
        function dnd(): bool { return root.dnd }
        function count(): int { return root.count }
        function clearAll(): void { root.clearAll() }
    }
}
