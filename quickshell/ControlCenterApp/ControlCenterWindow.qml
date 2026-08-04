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
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.CustomTheme

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore

    implicitWidth: 460
    color: "transparent"

    // Bottom-anchored and content-sized rather than full height: a panel pinned
    // to both vertical edges is mostly empty space on a 2560px-tall screen, and
    // it reads as a second desktop rather than as something the bar opened.
    // Capped so a long tray list scrolls instead of running off the top.
    // Pushed up from the body rather than read down into it: referencing the
    // scroll column's id from here is a forward reference the root's
    // implicitHeight binding evaluates before that object exists, which throws
    // "ReferenceError: body is not defined" and leaves the window unsized.
    //
    // 160 = the card's 20px shadow inset top and bottom, its 20px inner padding
    // top and bottom, the header row, and the divider under it.
    property real bodyHeight: 0
    implicitHeight: Math.min(root.bodyHeight + 160, 1300)

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
        property bool collapsed: false
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
                onClicked: section.collapsed = !section.collapsed
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

    // --- CALENDAR DATA ---
    readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    property int viewMonth: new Date().getMonth()
    property int viewYear: new Date().getFullYear()

    ListModel { id: dayModel }

    Component.onCompleted: buildMonth(viewYear, viewMonth)

    function stepMonth(delta) {
        let month = viewMonth + delta
        let year = viewYear
        if (month < 0) { month = 11; year-- }
        if (month > 11) { month = 0; year++ }
        viewMonth = month; viewYear = year
        buildMonth(year, month)
    }

    function buildMonth(year, month) {
        dayModel.clear()
        const first = new Date(year, month, 1).getDay()
        // JS weeks start on Sunday; this grid starts on Monday.
        const offset = first === 0 ? 6 : first - 1
        const daysThis = new Date(year, month + 1, 0).getDate()
        const daysPrev = new Date(year, month, 0).getDate()
        const today = new Date()

        for (let i = 0; i < 42; i++) {
            if (i < offset) {
                dayModel.append({ day: daysPrev - offset + i + 1, inMonth: false, isToday: false })
            } else if (i < offset + daysThis) {
                const n = i - offset + 1
                dayModel.append({
                    day: n,
                    inMonth: true,
                    isToday: n === today.getDate() && month === today.getMonth()
                             && year === today.getFullYear()
                })
            } else {
                dayModel.append({ day: i - offset - daysThis + 1, inMonth: false, isToday: false })
            }
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

        Rectangle {
            id: mainBgRect
            anchors.fill: parent
            radius: 10

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: Theme.on_primary }
            }

            // Frosted glass - see the note in AudioWindow.qml.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - anchors.margins
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.30)
            }
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
            ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: body
                    // Bound to the ScrollView by id. `parent.parent` resolves to
                    // the internal Flickable, whose availableWidth is not the
                    // one that matters - the column ended up sized to its own
                    // content and hugged the left edge.
                    width: bodyScroll.availableWidth
                    spacing: 12

                    onImplicitHeightChanged: root.bodyHeight = implicitHeight
                    Component.onCompleted: root.bodyHeight = implicitHeight

                    // ---------- CALENDAR ----------
                    Section {
                        title: "Calendar"
                        glyph: "calendar_month"

                        RowLayout {
                            Layout.fillWidth: true

                            Glyph {
                                text: "chevron_left"
                                font.pixelSize: 18
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.stepMonth(-1)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.primary
                            }

                            Glyph {
                                text: "chevron_right"
                                font.pixelSize: 18
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.stepMonth(1)
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 2
                            columnSpacing: 2

                            Repeater {
                                model: root.dayNames
                                Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.outline
                                }
                            }

                            Repeater {
                                model: dayModel

                                Rectangle {
                                    required property var model
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 100
                                    color: model.isToday ? Theme.primary : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: model.day
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: model.isToday
                                        color: model.isToday ? Theme.on_primary
                                             : model.inMonth ? Theme.on_surface : Theme.outline
                                        opacity: model.inMonth ? 1.0 : 0.45
                                    }
                                }
                            }
                        }
                    }

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

                        // 2x2, not a single row: four pills across ~380px left
                        // each one about 90px, and "118 KB/s" plus its icon does
                        // not fit in that, so the values ran into each other.
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            columns: 2
                            rowSpacing: 6
                            columnSpacing: 6

                            InfoPill {
                                glyph: "device_thermostat"
                                value: root.stats.temperature ? root.stats.temperature + "°C" : "—"
                                caption: "Temp"
                            }

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
                                glyph: "schedule"
                                value: root.humanUptime(root.stats.uptime)
                                caption: "Uptime"
                            }
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

                            // The first four mirror swaync's own buttons-grid,
                            // so the Control Center is a superset of the panel
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
                                glyph: root.tool("dnd") ? "notifications_off" : "notifications"
                                label: "Do not disturb"
                                detail: root.tool("dnd") ? "DND on" : "Notify"
                                active: !!root.tool("dnd")
                                hint: "Silence notifications (swaync do-not-disturb)"
                                onTriggered: root.toggleAction("swaync-client -d -sw")
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
                        }
                    }

                    // ---------- NOTIFICATIONS ----------
                    // swaync stays the notification daemon - only one process
                    // can own org.freedesktop.Notifications, and reimplementing
                    // a daemon to move a button is the wrong trade. This is a
                    // front end over `swaync-client`, which is exactly what the
                    // bar's custom/notification module was.
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
                                    text: root.tool("dnd") ? "notifications_off"
                                        : root.tool("notifications") > 0 ? "notifications_active"
                                        : "notifications_none"
                                    font.pixelSize: 18
                                    color: root.tool("dnd") ? Theme.outline
                                         : root.tool("notifications") > 0 ? Theme.tertiary
                                         : Theme.primary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const n = root.tool("notifications") || 0
                                        if (n === 0) return root.tool("dnd")
                                                     ? "No notifications · DND on" : "No notifications"
                                        return n + " notification" + (n === 1 ? "" : "s")
                                               + (root.tool("dnd") ? " · DND on" : "")
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
                                    Quickshell.execDetached(["swaync-client", "-t", "-sw"])
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
