import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.CustomTheme

// The popups that replace the ones swaync used to draw.
//
// Top right, because the bar is along the bottom and the notification centre
// slides up from the bottom right — a toast landing there would be covered by
// the panel it is telling you to open.
//
// This window is always mapped but input-masked to the toasts themselves, so
// the empty area below the stack stays click-through.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell"
    exclusionMode: WlrLayershell.Ignore

    // No focus grab and no keyboard focus: a toast must never steal input from
    // whatever is being typed into.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }

    implicitWidth: 400
    implicitHeight: Math.max(1, toastColumn.implicitHeight + 40)
    color: "transparent"

    visible: NotificationState.toasts.length > 0

    // Only the cards take clicks; the gaps between them and the space below do not.
    mask: Region { item: toastColumn }

    margins {
        top: 10
        right: 0
    }

    Column {
        id: toastColumn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 20
        width: parent.width - 40
        spacing: 8

        Repeater {
            model: NotificationState.toasts

            Item {
                id: toast
                required property var modelData
                width: toastColumn.width
                implicitHeight: toastCard.implicitHeight

                // Slide in from the right.
                x: 0
                opacity: 1
                Component.onCompleted: slideIn.start()

                NumberAnimation {
                    id: slideIn
                    target: toast
                    property: "x"
                    from: toastColumn.width
                    to: 0
                    duration: 250
                    easing.type: Easing.OutQuint
                }

                RectangularShadow {
                    anchors.fill: toastCard
                    radius: toastCard.radius
                    blur: 15
                    color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
                }

                // Same card as the panel: translucent fill, hairline border, and
                // no gradient. See the long comment in NotificationCenterWindow
                // for why a gradient here makes the card opaque.
                Rectangle {
                    id: toastCard
                    width: parent.width
                    implicitHeight: toastEntry.implicitHeight + 4
                    radius: 10
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.30)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)

                    NotificationEntry {
                        id: toastEntry
                        anchors.fill: parent
                        anchors.margins: 2
                        notification: toast.modelData
                        showBackground: false
                    }
                }

                // Hovering holds the toast open — otherwise anything with an
                // action button is a race against the timer.
                HoverHandler { id: hover }

                Timer {
                    interval: NotificationState.timeoutFor(toast.modelData)
                    // interval 0 means "until dismissed", so do not arm at all.
                    running: interval > 0 && !hover.hovered
                    repeat: false
                    onTriggered: NotificationState.dropToast(toast.modelData)
                }
            }
        }
    }
}
