import QtQuick

// The white ring around whatever has focus. Sits 4 px outside its parent.
Rectangle {
    property real parentRadius: 14
    property bool on: true
    anchors.fill: parent
    anchors.margins: -7
    radius: parentRadius + 7
    color: "transparent"
    border.width: 3
    border.color: "#ffffff"
    opacity: on ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
}
