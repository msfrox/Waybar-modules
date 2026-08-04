// Network popup for the Waybar `network` module.
//
// Replaces rendering nm-applet's tray menu through rofi - same reasoning as
// BluetoothApp: that depended on nm-applet living in the tray, and looked like
// rofi rather than like the bar. Quickshell.Networking talks to NetworkManager
// over DBus directly.
//
// Window chrome is duplicated from AudioWindow on purpose; see the note at the
// top of BluetoothWindow.qml.

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.CustomTheme

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore

    implicitWidth: 420
    implicitHeight: Math.min(content.implicitHeight + 80, 900)
    color: "transparent"

    anchors {
        bottom: true
        right: true
    }

    property real currentBottomMargin: isOpen ? 45 : -1200

    margins {
        bottom: root.currentBottomMargin
        right: 0
    }

    property bool isOpen: false
    property bool showWindow: false
    visible: showWindow

    onIsOpenChanged: {
        if (isOpen) {
            showWindow = true
            // Scanning only while visible - a background scan on every wifi
            // device is a real power cost for a list nobody is looking at.
            if (wifiDevice) wifiDevice.scannerEnabled = true
        } else {
            if (wifiDevice) wifiDevice.scannerEnabled = false
            pskFor = null
            pskText = ""
        }
    }

    Behavior on currentBottomMargin {
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
        target: "network"
        function toggle(): void { root.isOpen = !root.isOpen }
        function open(): void { root.isOpen = true }
        function close(): void { root.isOpen = false }
        function isOpen(): bool { return root.isOpen }
    }

    // --- NETWORKMANAGER ---
    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDevices: devices.filter(d => d.type === DeviceType.Wired)

    // Connected first, then by signal. NetworkManager hands these back in
    // whatever order it discovered them, which is useless to read.
    readonly property var wifiNetworks: {
        if (!wifiDevice || !wifiDevice.networks) return []
        const list = wifiDevice.networks.values.slice()
        list.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return list
    }

    // Which network currently has the inline password field open, if any.
    property var pskFor: null
    property string pskText: ""

    function secured(net) {
        return net && net.security !== WifiSecurityType.Open
                   && net.security !== WifiSecurityType.Owe
    }

    // signalStrength is 0..1. Material has no partial-wifi ligature set worth
    // using, so step the same glyph through four opacity bands instead.
    function bars(strength) {
        const s = strength || 0
        if (s > 0.75) return 4
        if (s > 0.5) return 3
        if (s > 0.25) return 2
        return 1
    }

    // --- SHARED PIECES ---
    component Glyph: Text {
        font.family: "Material Icons Round"
        font.pixelSize: 20
        color: Theme.primary
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    component SectionLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
        color: Theme.outline
        Layout.topMargin: 4
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.primary
        opacity: 0.3
    }

    component Toggle: Rectangle {
        id: tgl
        property bool checked: false
        signal toggled

        implicitWidth: 40
        implicitHeight: 22
        radius: 100
        color: checked ? Theme.primary : Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.25)
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: 16
            height: 16
            radius: 100
            color: tgl.checked ? Theme.on_primary : Theme.background
            anchors.verticalCenter: parent.verticalCenter
            x: tgl.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tgl.toggled()
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
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.62)
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Network"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    color: Theme.primary
                }

                Toggle {
                    checked: Networking.wifiEnabled
                    enabled: Networking.wifiHardwareEnabled
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 6
                    color: settingsMouse.containsMouse
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                           : "transparent"

                    Glyph { anchors.centerIn: parent; text: "tune"; font.pixelSize: 17 }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["nm-connection-editor"])
                            root.isOpen = false
                        }
                    }
                }
            }

            Divider {}

            // --- WIRED ---
            SectionLabel {
                text: "Wired"
                visible: root.wiredDevices.length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.wiredDevices.length > 0

                Repeater {
                    model: root.wiredDevices

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10

                        Glyph {
                            text: "lan"
                            font.pixelSize: 18
                            color: modelData.connected ? Theme.primary : Theme.outline
                            leftPadding: 8
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: modelData.connected ? Theme.primary : Theme.on_surface
                            }

                            Text {
                                text: modelData.connected ? (modelData.address || "Connected") : "Disconnected"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.outline
                            }
                        }
                    }
                }
            }

            Divider { visible: root.wiredDevices.length > 0 && root.wifiDevice }

            // --- WI-FI ---
            RowLayout {
                Layout.fillWidth: true
                visible: root.wifiDevice !== null

                SectionLabel { Layout.fillWidth: true; text: "Wi-Fi" }

                Text {
                    text: "Rescan"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: rescan.containsMouse ? Theme.primary : Theme.outline
                    visible: Networking.wifiEnabled

                    MouseArea {
                        id: rescan
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Toggling the scanner is what forces a fresh sweep.
                            root.wifiDevice.scannerEnabled = false
                            root.wifiDevice.scannerEnabled = true
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.wifiDevice !== null && !Networking.wifiEnabled
                text: Networking.wifiHardwareEnabled ? "Wi-Fi is off" : "Wi-Fi is blocked by hardware"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.outline
                leftPadding: 8
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.wifiDevice !== null && Networking.wifiEnabled

                Repeater {
                    model: root.wifiNetworks

                    ColumnLayout {
                        id: netEntry
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        readonly property bool pskOpen: root.pskFor === modelData

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: 6
                            color: netMouse.containsMouse
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                   : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                Glyph {
                                    text: "wifi"
                                    font.pixelSize: 18
                                    color: netEntry.modelData.connected ? Theme.primary : Theme.on_surface
                                    // 4 bars -> full strength, 1 bar -> faint.
                                    opacity: 0.25 + 0.25 * root.bars(netEntry.modelData.signalStrength)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: netEntry.modelData.name || "(hidden)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: netEntry.modelData.connected ? Theme.primary : Theme.on_surface
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: netEntry.modelData.stateChanging
                                    text: "…"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.outline
                                }

                                Glyph {
                                    text: "lock"
                                    font.pixelSize: 13
                                    color: Theme.outline
                                    visible: root.secured(netEntry.modelData)
                                }

                                Glyph {
                                    text: "close"
                                    font.pixelSize: 14
                                    color: forget.containsMouse ? Theme.error : Theme.outline
                                    visible: netEntry.modelData.known

                                    MouseArea {
                                        id: forget
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: netEntry.modelData.forget()
                                    }
                                }
                            }

                            MouseArea {
                                id: netMouse
                                anchors.fill: parent
                                anchors.rightMargin: 26
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const net = netEntry.modelData
                                    if (net.connected) {
                                        net.disconnect()
                                    } else if (net.known || !root.secured(net)) {
                                        // A known network already has its
                                        // credentials in NetworkManager.
                                        net.connect()
                                    } else {
                                        root.pskText = ""
                                        root.pskFor = netEntry.pskOpen ? null : net
                                    }
                                }
                            }
                        }

                        // Inline password entry, shown only for a secured
                        // network NetworkManager has no saved secret for.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            implicitHeight: netEntry.pskOpen ? 32 : 0
                            visible: netEntry.pskOpen
                            radius: 6
                            color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.08)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 6

                                TextInput {
                                    id: pskField
                                    Layout.fillWidth: true
                                    text: root.pskText
                                    onTextChanged: root.pskText = text
                                    echoMode: TextInput.Password
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.on_surface
                                    clip: true
                                    verticalAlignment: TextInput.AlignVCenter
                                    focus: netEntry.pskOpen
                                    onAccepted: {
                                        netEntry.modelData.connectWithPsk(root.pskText)
                                        root.pskFor = null
                                        root.pskText = ""
                                    }

                                    Text {
                                        anchors.fill: parent
                                        visible: pskField.text === ""
                                        text: "Password"
                                        font: pskField.font
                                        color: Theme.outline
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Glyph {
                                    text: "arrow_forward"
                                    font.pixelSize: 16

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            netEntry.modelData.connectWithPsk(root.pskText)
                                            root.pskFor = null
                                            root.pskText = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.wifiDevice !== null && Networking.wifiEnabled && root.wifiNetworks.length === 0
                text: "Scanning…"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.outline
                leftPadding: 8
            }

            Item { Layout.fillHeight: true }
        }
    }
}
