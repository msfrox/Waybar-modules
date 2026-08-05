// Control Center - a full-height panel that slides in from the right.
//
// The bar had accumulated things that only work as a hover-out drawer: a
// hardware group, a tools group, a tray drawer. Those are fine as a shortcut
// and bad as a home - they are invisible until you know they are there, they
// vanish when the pointer leaves, and each one costs permanent width on a bar
// that also wants to show a taskbar.
//
// So this is the home, and the bar keeps only what is worth a permanent glance.
// The point of the first version is the FRAME, not the contents: a right-anchored
// full-height surface, a scrollable column, and a Section component that further
// modules drop into without touching anything else here.
//
// Migration is deliberately incremental - a module stays on the bar until its
// equivalent here is at least as good.
//
// Window chrome is duplicated from AudioWindow on purpose; see the note at the
// top of BluetoothWindow.qml.

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.CustomTheme
import qs.NotificationCenterApp

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore

    implicitWidth: 460
    color: "transparent"

    // Bottom-anchored and content-sized rather than full height: a panel pinned
    // to both vertical edges is mostly empty space on a 2560px-tall screen, and
    // it reads as a second desktop rather than as something the bar opened.
    // The cap is a last-resort guard against running off the top of the
    // screen, not a scroll threshold - there is no scroll view any more.
    // Pushed up from the body rather than read down into it: referencing the
    // scroll column's id from here is a forward reference the root's
    // implicitHeight binding evaluates before that object exists, which throws
    // "ReferenceError: body is not defined" and leaves the window unsized.
    //
    // 160 = the card's 20px shadow inset top and bottom, its 20px inner padding
    // top and bottom, the header row, and the divider under it.
    property real bodyHeight: 0
    implicitHeight: Math.min(root.bodyHeight + 160, 2400)

    anchors {
        right: true
        bottom: true
    }

    property bool isOpen: false
    property bool showWindow: false
    visible: showWindow

    onIsOpenChanged: {
        if (isOpen) {
            showWindow = true
            refresh()
            reloadBrightness()
        }
    }

    // Slides in from the right edge. Same 45px bottom margin as the popups, so
    // its lower edge lines up with theirs above the 55px bar.
    property real currentRightMargin: isOpen ? 0 : -520

    margins {
        bottom: 45
        right: root.currentRightMargin
    }

    Behavior on currentRightMargin {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutQuint
            onRunningChanged: if (!running && !root.isOpen) root.showWindow = false
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen && root.showWindow
        onCleared: if (root.isOpen) root.isOpen = false
    }

    Shortcut {
        sequence: "Escape"
        onActivated: if (root.isOpen) root.isOpen = false
    }

    IpcHandler {
        target: "control-center"
        function toggle(): void { root.isOpen = !root.isOpen }
        function open(): void { root.isOpen = true }
        function close(): void { root.isOpen = false }
        function isOpen(): bool { return root.isOpen }
    }

    // --- SYSTEM STATS ---
    property var stats: ({})

    Process {
        id: statsProc
        command: [Quickshell.env("HOME") + "/.config/waybar/scripts/system-stats.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.stats = JSON.parse(this.text) } catch (e) {}
            }
        }
    }

    function refresh() {
        if (!statsProc.running) statsProc.running = true
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.isOpen
        onTriggered: root.refresh()
    }

    // --- BRIGHTNESS ---
    // Off the 2-second stats tick: reading the external monitor is a DDC/CI
    // round-trip over I2C, which is slow and does not like being hammered. Read
    // on open, and after a drag settles.
    property var brightness: ({})

    Process {
        id: brightnessProc
        command: [Quickshell.env("HOME") + "/.config/waybar/scripts/brightness.py", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.brightness = JSON.parse(this.text) } catch (e) {}
            }
        }
    }

    function reloadBrightness() {
        if (!brightnessProc.running) brightnessProc.running = true
    }

    Process { id: brightnessSet }

    // Debounced: a drag emits a value on every pixel, and each external write is
    // a DDC round-trip. Only the value the slider settles on is actually sent.
    Timer {
        id: brightnessDebounce
        interval: 120
        repeat: false
        property string target: ""
        property int value: 0
        onTriggered: {
            brightnessSet.command = [
                Quickshell.env("HOME") + "/.config/waybar/scripts/brightness.py",
                "set", target, String(value)]
            brightnessSet.running = true
        }
    }

    function setBrightness(target, value) {
        brightnessDebounce.target = target
        brightnessDebounce.value = value
        brightnessDebounce.restart()
    }

    // --- PENDING UPDATES ---
    // Kept off the stats tick on purpose: this hits the package databases and
    // takes seconds, so it runs on open and then only every 30 minutes - the
    // same cadence the bar module used.
    property int updateCount: 0

    Process {
        id: updatesProc
        command: [Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-check-system-updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)
                    root.updateCount = parseInt(payload.text) || 0
                } catch (e) {
                    root.updateCount = 0
                }
            }
        }
    }

    Timer {
        interval: 1800000
        repeat: true
        triggeredOnStart: true
        running: root.isOpen
        onTriggered: if (!updatesProc.running) updatesProc.running = true
    }

    // Runs a shell command and closes the panel - the shape every quick action
    // that hands off to another window takes.
    function launch(command) {
        Quickshell.execDetached(["bash", "-c", command])
        root.isOpen = false
    }

    // Runs a shell command and stays open, then re-reads state so the tile's
    // active styling catches up with what just happened.
    Process { id: toggleProc; onExited: root.refresh() }

    function toggleAction(command) {
        toggleProc.command = ["bash", "-c", command]
        toggleProc.running = true
    }

    // --- FORMATTING ---
    function humanBytes(bytes) {
        if (bytes === null || bytes === undefined) return "—"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = bytes, i = 0
        while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ }
        return (value >= 10 || i === 0 ? Math.round(value) : value.toFixed(1)) + " " + units[i]
    }

    function humanRate(bytesPerSecond) {
        if (bytesPerSecond === null || bytesPerSecond === undefined) return "—"
        return humanBytes(bytesPerSecond) + "/s"
    }

    function humanUptime(seconds) {
        if (!seconds) return "—"
        const days = Math.floor(seconds / 86400)
        const hours = Math.floor((seconds % 86400) / 3600)
        const mins = Math.floor((seconds % 3600) / 60)
        if (days > 0) return days + "d " + hours + "h"
        if (hours > 0) return hours + "h " + mins + "m"
        return mins + "m"
    }

    // stats.tools is undefined until the first read, and every tile binds to it
    // - one accessor beats repeating the guard at a dozen call sites.
    function tool(key) {
        return root.stats.tools ? root.stats.tools[key] : undefined
    }

    function loadColor(percent) {
        if (percent >= 90) return Theme.error
        if (percent >= 70) return Theme.tertiary
        return Theme.primary
    }

    // --- SECTION COLLAPSE STATE ---
    // Keyed by title rather than index: sections get reordered in this file
    // far more often than the persisted file gets touched, and a title
    // survives a reorder where an index wouldn't.
    property var collapseState: ({})

    function setSectionCollapsed(title, collapsed) {
        const next = Object.assign({}, root.collapseState)
        next[title] = collapsed
        root.collapseState = next
        collapseSettings.collapsed = next
        collapseFile.writeAdapter()
    }

    FileView {
        id: collapseFile
        path: Quickshell.env("HOME") + "/.config/waybar-control-center/control-center.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.collapseState = collapseSettings.collapsed

        // No file yet is the normal first-run case, not an error - every
        // section just keeps its collapsed: false default below.
        onLoadFailed: (error) => {}

        JsonAdapter {
            id: collapseSettings
            property var collapsed: ({})
        }
    }

    // --- SHARED PIECES ---
    component Glyph: Text {
        font.family: "Material Icons Round"
        font.pixelSize: 20
        color: Theme.primary
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    // The unit every future module plugs into: a titled, collapsible block.
    // Anything added to `content` inherits the panel's spacing and its
    // collapse behaviour for free.
    component Section: ColumnLayout {
        id: section
        required property string title
        property string glyph: ""
        // Bound rather than a plain default, so a title missing from
        // collapseState - a brand new section, or a first run with no file
        // yet - falls through to false instead of coming up collapsed.
        property bool collapsed: root.collapseState.hasOwnProperty(section.title)
                                  ? root.collapseState[section.title] : false
        default property alias content: holder.data

        Layout.fillWidth: true
        spacing: 6

        // The header is wrapped in a plain Item so the click target can use
        // anchors: a MouseArea placed directly in a Layout is layout-managed,
        // and anchoring it is undefined behaviour that Qt warns about.
        Item {
            Layout.fillWidth: true
            implicitHeight: 24

            RowLayout {
                anchors.fill: parent
                spacing: 8

                Glyph {
                    text: section.glyph
                    font.pixelSize: 16
                    visible: section.glyph !== ""
                }

                Text {
                    Layout.fillWidth: true
                    text: section.title
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                    color: Theme.outline
                }

                Glyph {
                    text: section.collapsed ? "expand_more" : "expand_less"
                    font.pixelSize: 18
                    color: Theme.outline
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Through setSectionCollapsed rather than a direct toggle -
                // assigning section.collapsed here would break the binding
                // above, so a later file reload could never reach it again.
                onClicked: root.setSectionCollapsed(section.title, !section.collapsed)
            }
        }

        ColumnLayout {
            id: holder
            Layout.fillWidth: true
            spacing: 6
            visible: !section.collapsed
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 1
            color: Theme.primary
            opacity: 0.25
        }
    }

    // A labelled usage bar - CPU, memory, disk all read the same way.
    component StatBar: ColumnLayout {
        id: statRoot
        required property string label
        required property real percent
        property string detail: ""

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: statRoot.label
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.on_surface
            }

            Text {
                text: statRoot.detail
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.outline
                rightPadding: 8
            }

            Text {
                text: Math.round(statRoot.percent) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: root.loadColor(statRoot.percent)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.2)

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, statRoot.percent / 100))
                height: parent.height
                radius: 3
                color: root.loadColor(statRoot.percent)
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    // A quick action. `active` gives it the accent fill, which is what makes a
    // toggle readable at a glance without a separate state label.
    component ToolTile: Rectangle {
        id: tile
        required property string glyph
        required property string label
        property string detail: ""
        property string hint: ""
        property bool active: false
        signal triggered

        // The tile shows `detail` (the current state) rather than `label`, so
        // without this there is nowhere the tile says what it *is*.
        ToolTip.visible: tileMouse.containsMouse && tile.hint !== ""
        ToolTip.text: tile.hint
        ToolTip.delay: 400

        Layout.fillWidth: true
        implicitHeight: 56
        radius: 8
        color: active ? Theme.primary
                      : tileMouse.containsMouse
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        : Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.07)
        Behavior on color { ColorAnimation { duration: 150 } }
        clip: true

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            Glyph {
                Layout.alignment: Qt.AlignHCenter
                text: tile.glyph
                font.pixelSize: 18
                color: tile.active ? Theme.on_primary : Theme.primary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.detail !== "" ? tile.detail : tile.label
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: tile.active ? Theme.on_primary : Theme.on_surface
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.triggered()
        }
    }

    // Icon + slider + percentage, for the two brightness controls.
    component BrightnessRow: RowLayout {
        id: brow
        required property string glyph
        required property string label
        required property int percent
        property string hint: ""
        signal moved(int value)

        Layout.fillWidth: true
        spacing: 12

        Glyph {
            text: brow.glyph
            font.pixelSize: 18

            ToolTip.visible: browHover.containsMouse && brow.hint !== ""
            ToolTip.text: brow.hint
            ToolTip.delay: 400

            MouseArea {
                id: browHover
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
        }

        Slider {
            id: brightSlider
            Layout.fillWidth: true
            from: 1
            to: 100
            // Taken on change rather than bound, so a live reading arriving
            // mid-drag does not fight the handle.
            value: brow.percent
            onMoved: brow.moved(Math.round(value))

            background: Rectangle {
                x: brightSlider.leftPadding
                y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                implicitHeight: 6
                width: brightSlider.availableWidth
                height: implicitHeight
                radius: 3
                color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.2)

                Rectangle {
                    width: brightSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 3
                    color: Theme.primary
                }
            }

            handle: Rectangle {
                x: brightSlider.leftPadding + brightSlider.visualPosition * (brightSlider.availableWidth - width)
                y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                implicitWidth: 16
                implicitHeight: 16
                radius: 100
                color: brightSlider.pressed ? Theme.background : Theme.primary
                border.color: Theme.primary
                border.width: 2
            }
        }

        Text {
            text: brow.percent + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.on_surface
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 38
        }
    }

    component InfoPill: Rectangle {
        id: pill
        required property string glyph
        required property string value
        required property string caption

        Layout.fillWidth: true
        implicitHeight: 48
        radius: 8
        color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.07)
        clip: true

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5

                Glyph { text: pill.glyph; font.pixelSize: 14 }

                Text {
                    text: pill.value
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.on_surface
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pill.caption
                font.family: Theme.fontFamily
                font.pixelSize: 9
                color: Theme.outline
            }
        }
    }

    // A small selectable pill - the Mpris player switcher. There is no
    // existing "selected" style to reuse here (DeviceRow's radio-dot list
    // lives in AudioWindow.qml and is full-width, which a row of these isn't),
    // so this is a filled-vs-outlined pill instead, in the same accent-fill
    // language ToolTile already uses for its active state.
    component PlayerChip: Rectangle {
        id: chip
        required property string label
        required property bool active
        signal picked

        implicitHeight: 22
        implicitWidth: Math.min(chipText.implicitWidth, 90) + 18
        radius: 11
        color: chip.active ? Theme.primary
                            : chipMouse.containsMouse
                              ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                              : Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.07)
        border.width: chip.active ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            id: chipText
            anchors.fill: parent
            anchors.margins: 9
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: chip.label
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: chip.active ? Theme.on_primary : Theme.on_surface
            elide: Text.ElideRight
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    // ==========================================
    // PANEL
    // ==========================================
    Item {
        anchors.fill: parent
        anchors.margins: 20

        RectangularShadow {
            anchors.fill: mainBgRect
            radius: mainBgRect.radius
            blur: 15
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
        }

        // One rectangle: translucent fill, solid hairline border. A gradient
        // is a FILL, not a border, so it painted the whole card and the
        // "translucent" inner rectangle composited against that opaque
        // gradient rather than against the wallpaper - never actually
        // see-through. Blur comes from the "quickshell-frosted-glass" layer
        // rule in ~/.config/hypr/shehan/theming.lua.
        Rectangle {
            id: mainBgRect
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.30)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: Qt.formatDateTime(clock.now, "dddd")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.primary
                    }

                    Text {
                        text: Qt.formatDateTime(clock.now, "d MMMM yyyy  ·  HH:mm")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.outline
                    }
                }

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 6
                    color: powerMouse.containsMouse
                           ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18)
                           : "transparent"

                    ToolTip.visible: powerMouse.containsMouse
                    ToolTip.text: "Lock, suspend, log out, reboot or shut down"
                    ToolTip.delay: 400

                    Glyph {
                        anchors.centerIn: parent
                        text: "power_settings_new"
                        font.pixelSize: 18
                        color: powerMouse.containsMouse ? Theme.error : Theme.primary
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isOpen = false
                            Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"])
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.primary
                opacity: 0.3
            }

            // --- SCROLLING BODY ---
            // No ScrollView: the panel grows to fit its sections instead of
            // capping and scrolling. A control centre you have to scroll defeats
            // the point - everything in it is meant to be one glance away - and
            // the window is sized from this column's implicitHeight anyway, so
            // the two would only ever fight each other.
            ColumnLayout {
                    id: body
                    Layout.fillWidth: true
                    spacing: 12

                    onImplicitHeightChanged: root.bodyHeight = implicitHeight
                    Component.onCompleted: root.bodyHeight = implicitHeight

                    // ---------- SYSTEM ----------
                    Section {
                        title: "System"
                        glyph: "monitoring"

                        StatBar {
                            label: "CPU"
                            percent: root.stats.cpu || 0
                            detail: (root.stats.cores || "?") + " cores"
                                    + (root.stats.load ? "  ·  load " + root.stats.load[0] : "")
                        }

                        StatBar {
                            label: "Memory"
                            percent: root.stats.memory ? root.stats.memory.percent : 0
                            detail: root.stats.memory
                                    ? root.humanBytes(root.stats.memory.used) + " / "
                                      + root.humanBytes(root.stats.memory.total)
                                    : ""
                        }

                        StatBar {
                            label: "Disk"
                            percent: root.stats.disk ? root.stats.disk.percent : 0
                            detail: root.stats.disk
                                    ? root.humanBytes(root.stats.disk.used) + " / "
                                      + root.humanBytes(root.stats.disk.total)
                                    : ""
                        }

                        StatBar {
                            // Coerced: before the first stats read `memory` is
                            // undefined, and `undefined && ...` is undefined,
                            // which is not assignable to a bool.
                            visible: !!(root.stats.memory && root.stats.memory.swap_total > 0)
                            label: "Swap"
                            percent: root.stats.memory ? root.stats.memory.swap_percent : 0
                            detail: root.stats.memory
                                    ? root.humanBytes(root.stats.memory.swap_used) : ""
                        }

                        // Three per row. Four across ~380px left each about 90px
                        // and "118 KB/s" plus its icon ran into its neighbour;
                        // three is the most that still fits a rate string.
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            // Three wide: Down and Up still land side by side on
                            // the first row, and the two fans fill the second
                            // instead of leaving a hole.
                            columns: 3
                            rowSpacing: 6
                            columnSpacing: 6

                            InfoPill {
                                glyph: "download"
                                value: root.stats.network ? root.humanRate(root.stats.network.rx_rate) : "—"
                                caption: "Down"
                            }

                            InfoPill {
                                glyph: "upload"
                                value: root.stats.network ? root.humanRate(root.stats.network.tx_rate) : "—"
                                caption: "Up"
                            }

                            InfoPill {
                                glyph: "device_thermostat"
                                value: root.stats.temperature ? root.stats.temperature + "°C" : "—"
                                caption: "Temp"
                            }

                            InfoPill {
                                glyph: "schedule"
                                value: root.humanUptime(root.stats.uptime)
                                caption: "Uptime"
                            }

                            // One pill per physical fan. lm-sensors reports both
                            // on this machine; a laptop with one gets one pill
                            // and a fanless one gets none.
                            Repeater {
                                model: root.stats.fans || []

                                InfoPill {
                                    required property var modelData
                                    // "toys" is a pinwheel - Material Icons Round has no fan glyph
                                    glyph: "toys"
                                    value: modelData.rpm + " rpm"
                                    caption: modelData.label
                                }
                            }
                        }
                    }

                    // ---------- DISPLAY ----------
                    Section {
                        title: "Display"
                        glyph: "brightness_6"

                        BrightnessRow {
                            visible: !!(root.brightness.internal)
                            glyph: "brightness_low"
                            label: "Internal"
                            hint: "Laptop panel backlight"
                            percent: root.brightness.internal
                                     ? root.brightness.internal.percent : 0
                            onMoved: value => root.setBrightness("internal", value)
                        }

                        BrightnessRow {
                            visible: !!(root.brightness.external)
                            glyph: "desktop_windows"
                            label: "External"
                            hint: "External monitor over DDC/CI — slower to respond than the panel"
                            percent: root.brightness.external
                                     && root.brightness.external.percent !== null
                                     ? root.brightness.external.percent : 0
                            onMoved: value => root.setBrightness("external", value)
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.brightness.internal && !root.brightness.external
                            text: "No controllable displays found"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.outline
                        }
                    }

                    // ---------- QUICK ACTIONS ----------
                    // These were the bar's group/tools drawer.
                    Section {
                        title: "Quick actions"
                        glyph: "bolt"

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: 6
                            columnSpacing: 6

                            // The first four are the toggles a notification
                            // panel's own buttons-grid usually carries, so the
                            // Control Center is a superset of the panel
                            // whose button it replaced on the bar.
                            ToolTile {
                                glyph: root.tool("wifi_enabled") ? "wifi" : "wifi_off"
                                label: "Wi-Fi"
                                detail: root.tool("wifi_enabled") ? "Wi-Fi" : "Wi-Fi off"
                                active: !!root.tool("wifi_enabled")
                                hint: "Toggle the Wi-Fi radio"
                                onTriggered: root.toggleAction(
                                    "nmcli radio wifi " + (root.tool("wifi_enabled") ? "off" : "on"))
                            }

                            ToolTile {
                                glyph: root.tool("bluetooth_enabled") ? "bluetooth" : "bluetooth_disabled"
                                label: "Bluetooth"
                                detail: root.tool("bluetooth_enabled") ? "Bluetooth" : "BT off"
                                active: !!root.tool("bluetooth_enabled")
                                hint: "Toggle the Bluetooth radio (rfkill)"
                                onTriggered: root.toggleAction("rfkill toggle bluetooth")
                            }

                            ToolTile {
                                glyph: root.tool("muted") ? "volume_off" : "volume_up"
                                label: "Mute"
                                detail: root.tool("muted") ? "Muted" : "Sound on"
                                active: !!root.tool("muted")
                                hint: "Mute or unmute the default output"
                                onTriggered: root.toggleAction(
                                    "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
                            }

                            ToolTile {
                                glyph: NotificationState.dnd ? "notifications_off" : "notifications"
                                label: "Do not disturb"
                                detail: NotificationState.dnd ? "DND on" : "Notify"
                                active: NotificationState.dnd
                                hint: "Silence notifications (do-not-disturb)"
                                onTriggered: NotificationState.toggleDnd()
                            }

                            ToolTile {
                                glyph: "lock"
                                label: "Lock"
                                hint: "Lock the screen now (hyprlock)"
                                onTriggered: root.launch("hyprlock")
                            }

                            ToolTile {
                                glyph: "content_paste"
                                label: "Clipboard"
                                hint: "Clipboard history (cliphist)"
                                onTriggered: root.launch(
                                    Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-cliphist")
                            }

                            ToolTile {
                                glyph: root.stats.tools && root.stats.tools.idle_inhibited
                                       ? "coffee" : "bedtime"
                                label: "Keep awake"
                                hint: "Stop the screen locking and sleeping (hypridle)"
                                detail: root.stats.tools && root.stats.tools.idle_inhibited
                                        ? "Awake" : "Auto-sleep"
                                active: !!(root.stats.tools && root.stats.tools.idle_inhibited)
                                onTriggered: root.toggleAction(
                                    Quickshell.env("HOME") + "/.config/hypr/scripts/hypridle.sh toggle")
                            }

                            ToolTile {
                                glyph: "nightlight"
                                label: "Night light"
                                hint: "Toggle the warm screen shader (hyprsunset)"
                                onTriggered: root.toggleAction(
                                    "sleep 0.3; " + Quickshell.env("HOME")
                                    + "/.config/ml4w/scripts/ml4w-toggle-hyprsunset")
                            }

                            ToolTile {
                                readonly property string profile:
                                    root.stats.tools && root.stats.tools.power_profile
                                    ? root.stats.tools.power_profile : ""
                                glyph: profile === "performance" ? "speed"
                                     : profile === "power-saver" ? "eco" : "balance"
                                label: "Power"
                                hint: "Cycle power profile: saver, balanced, performance"
                                detail: profile === "power-saver" ? "Saver"
                                      : profile === "performance" ? "Performance"
                                      : profile === "balanced" ? "Balanced" : "Power"
                                // Cycles rather than opening a menu - there are
                                // only ever three and a menu is more clicks.
                                onTriggered: {
                                    const next = profile === "power-saver" ? "balanced"
                                               : profile === "balanced" ? "performance"
                                               : "power-saver"
                                    root.toggleAction("powerprofilesctl set " + next)
                                }
                            }

                            // These three commands are lifted from ML4W's SidebarWindow.qml -
                            // only the shell commands, not the widgets, so this doesn't
                            // depend on that file surviving an ML4W update.
                            ToolTile {
                                glyph: "brightness_6"
                                label: "Theme"
                                detail: "Theme"
                                hint: "Switch between the light and dark theme"
                                onTriggered: Quickshell.execDetached(
                                    ["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-toggle-theme"])
                            }

                            ToolTile {
                                glyph: "colorize"
                                label: "Colour picker"
                                detail: "Pick"
                                hint: "Pick a colour from the screen"
                                onTriggered: {
                                    root.isOpen = false
                                    Quickshell.execDetached(
                                        ["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/settings/hyprpicker.sh"])
                                }
                            }

                            ToolTile {
                                glyph: "photo_camera"
                                label: "Screenshot"
                                detail: "Shot"
                                hint: "Take a screenshot"
                                onTriggered: {
                                    root.isOpen = false
                                    Quickshell.execDetached(
                                        ["bash", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"])
                                }
                            }
                        }
                    }

                    // ---------- MEDIA ----------
                    // Quickshell's Mpris service replaces the bar's `custom/nowplaying`
                    // module, which polled `playerctl` every second - the players
                    // already live on the session bus, so this reads them directly
                    // instead.
                    Section {
                        id: mediaSection
                        title: "Media"
                        glyph: "music_note"

                        // First player that is actually playing, falling back to the
                        // first player at all.
                        readonly property var autoPlayer: {
                            const players = Mpris.players.values
                            if (players.length === 0) return null
                            return players.find(p => p.isPlaying) || players[0]
                        }

                        // Sticky per session only, by identity rather than index so
                        // it survives Mpris.players.values reordering. Empty means
                        // "auto". Not persisted to disk on purpose - which player is
                        // "yours" today has nothing to do with which one was yours
                        // last restart.
                        property string pinnedIdentity: ""

                        // undefined rather than null when nothing matches, so a
                        // pinned player that has disappeared (app closed, tab
                        // closed) falls back to autoPlayer via `||` below instead
                        // of the switcher going blank.
                        readonly property var pinnedPlayer: mediaSection.pinnedIdentity !== ""
                            ? Mpris.players.values.find(p => p.identity === mediaSection.pinnedIdentity)
                            : undefined

                        readonly property var player: mediaSection.pinnedPlayer || mediaSection.autoPlayer

                        // Bumped by the Timer below so progressFraction has something
                        // to react to - MprisPlayer.position is read on access, it
                        // does not push updates on its own.
                        property int positionTick: 0

                        readonly property real progressFraction: {
                            positionTick // dependency only, see comment above
                            if (!player || !player.lengthSupported || !player.positionSupported
                                    || player.length <= 0) return 0
                            return Math.min(1, player.position / player.length)
                        }

                        // Only worth showing once there is a choice to make -
                        // with one player the auto pick is never a guess.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: Mpris.players.values.length > 1
                            spacing: 6

                            Repeater {
                                model: Mpris.players.values

                                PlayerChip {
                                    required property var modelData
                                    label: modelData.identity
                                    active: modelData === mediaSection.player
                                    onPicked: mediaSection.pinnedIdentity = modelData.identity
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !mediaSection.player
                            text: "Nothing playing"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.outline
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!mediaSection.player
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 56
                                radius: 8
                                color: trackMouse.containsMouse
                                       ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                       : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 48
                                        Layout.preferredHeight: 48
                                        radius: 6
                                        color: "transparent"
                                        clip: true
                                        visible: !!(mediaSection.player && mediaSection.player.trackArtUrl)

                                        Image {
                                            anchors.fill: parent
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectCrop
                                            source: mediaSection.player ? mediaSection.player.trackArtUrl : ""
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: mediaSection.player ? mediaSection.player.trackTitle : ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.on_surface
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: !!(mediaSection.player && mediaSection.player.trackArtist)
                                            text: mediaSection.player ? mediaSection.player.trackArtist : ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            color: Theme.outline
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: trackMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (mediaSection.player) mediaSection.player.raise()
                                }
                            }

                            // Read-only - the point is glanceable state, not a seek
                            // bar to drag.
                            Rectangle {
                                Layout.fillWidth: true
                                visible: !!(mediaSection.player && mediaSection.player.lengthSupported
                                            && mediaSection.player.positionSupported
                                            && mediaSection.player.length > 0)
                                implicitHeight: 3
                                radius: 1.5
                                color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.2)

                                Rectangle {
                                    width: parent.width * mediaSection.progressFraction
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.primary
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 24

                                Glyph {
                                    text: "skip_previous"
                                    font.pixelSize: 20
                                    opacity: mediaSection.player && mediaSection.player.canGoPrevious ? 1 : 0.35

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !!(mediaSection.player && mediaSection.player.canGoPrevious)
                                        onClicked: mediaSection.player.previous()
                                    }
                                }

                                Glyph {
                                    text: mediaSection.player && mediaSection.player.isPlaying
                                          ? "pause" : "play_arrow"
                                    font.pixelSize: 22
                                    opacity: mediaSection.player && mediaSection.player.canTogglePlaying ? 1 : 0.35

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !!(mediaSection.player && mediaSection.player.canTogglePlaying)
                                        onClicked: mediaSection.player.togglePlaying()
                                    }
                                }

                                Glyph {
                                    text: "skip_next"
                                    font.pixelSize: 20
                                    opacity: mediaSection.player && mediaSection.player.canGoNext ? 1 : 0.35

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !!(mediaSection.player && mediaSection.player.canGoNext)
                                        onClicked: mediaSection.player.next()
                                    }
                                }
                            }
                        }

                        // Runs only while there is something to watch tick over -
                        // expanded and playing - so a paused or idle player does not
                        // spend a timer on a bar that never moves.
                        Timer {
                            interval: 1000
                            repeat: true
                            running: !mediaSection.collapsed
                                     && !!(mediaSection.player && mediaSection.player.isPlaying)
                            onTriggered: mediaSection.positionTick++
                        }
                    }

                    // ---------- NOTIFICATIONS ----------
                    // Quickshell is the notification daemon now, so there is no
                    // separate process to front for. This section is just a
                    // summary of what NotificationState is holding, and a way
                    // into the panel it owns.
                    Section {
                        title: "Notifications"
                        glyph: "notifications"

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 8
                            color: notifMouse.containsMouse
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                   : Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.07)

                            ToolTip.visible: notifMouse.containsMouse
                            ToolTip.text: "Open the notification panel"
                            ToolTip.delay: 400

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Glyph {
                                    text: NotificationState.dnd ? "notifications_off"
                                        : NotificationState.count > 0 ? "notifications_active"
                                        : "notifications_none"
                                    font.pixelSize: 18
                                    color: NotificationState.dnd ? Theme.outline
                                         : NotificationState.count > 0 ? Theme.tertiary
                                         : Theme.primary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const n = NotificationState.count || 0
                                        if (n === 0) return NotificationState.dnd
                                                     ? "No notifications · DND on" : "No notifications"
                                        return n + " notification" + (n === 1 ? "" : "s")
                                               + (NotificationState.dnd ? " · DND on" : "")
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.on_surface
                                }

                                Glyph { text: "chevron_right"; font.pixelSize: 16; color: Theme.outline }
                            }

                            MouseArea {
                                id: notifMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.isOpen = false
                                    NotificationState.togglePanel()
                                }
                            }
                        }
                    }

                    // ---------- UPDATES ----------
                    Section {
                        title: "Updates"
                        glyph: "system_update_alt"

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 8
                            color: updatesMouse.containsMouse
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                   : Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.07)

                            ToolTip.visible: updatesMouse.containsMouse && root.updateCount > 0
                            ToolTip.text: "Install pending package updates"
                            ToolTip.delay: 400

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Glyph {
                                    text: root.updateCount > 0 ? "download_for_offline" : "check_circle"
                                    font.pixelSize: 18
                                    color: root.updateCount > 0 ? Theme.tertiary : Theme.primary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.updateCount > 0
                                          ? root.updateCount + " package" + (root.updateCount === 1 ? "" : "s")
                                            + " to update"
                                          : "System is up to date"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.on_surface
                                }

                                Glyph {
                                    text: "chevron_right"
                                    font.pixelSize: 16
                                    color: Theme.outline
                                    visible: root.updateCount > 0
                                }
                            }

                            MouseArea {
                                id: updatesMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.updateCount > 0
                                onClicked: root.launch(
                                    Quickshell.env("HOME") + "/.config/ml4w/settings/installupdates.sh")
                            }
                        }

                    }

                    // ---------- TRAY ----------
                    Section {
                        title: "Tray"
                        glyph: "widgets"

                        Text {
                            Layout.fillWidth: true
                            visible: SystemTray.items.values.length === 0
                            text: "Nothing in the tray"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.outline
                        }

                        Repeater {
                            model: SystemTray.items

                            Rectangle {
                                id: trayRow
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: 6
                                color: trayMouse.containsMouse
                                       ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                       : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 10

                                    Image {
                                        source: trayRow.modelData.icon
                                        sourceSize.width: 20
                                        sourceSize.height: 20
                                        width: 20
                                        height: 20
                                        fillMode: Image.PreserveAspectFit
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: trayRow.modelData.tooltipTitle
                                              || trayRow.modelData.title
                                              || trayRow.modelData.id
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.on_surface
                                        elide: Text.ElideRight
                                    }

                                    Glyph {
                                        text: "more_vert"
                                        font.pixelSize: 16
                                        color: Theme.outline
                                        visible: trayRow.modelData.hasMenu
                                    }
                                }

                                MouseArea {
                                    id: trayMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        // An item with onlyMenu has no activate
                                        // action at all - left-clicking it in a
                                        // real tray opens the menu too.
                                        if (mouse.button === Qt.RightButton
                                                || trayRow.modelData.onlyMenu) {
                                            if (trayRow.modelData.hasMenu) {
                                                trayRow.modelData.display(root, mouse.x, mouse.y)
                                            }
                                        } else {
                                            trayRow.modelData.activate()
                                            root.isOpen = false
                                        }
                                    }
                                }
                            }
                        }
                    }
            }
        }
    }

    // Drives the header clock. One second would be wasted work for a display
    // that only shows minutes.
    Timer {
        id: clock
        property date now: new Date()
        interval: 20000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: now = new Date()
    }
}
