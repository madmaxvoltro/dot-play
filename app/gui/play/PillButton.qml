import QtQuick

// The rounded buttons of Dot Play. `primary` is the white one; `glyph` shows a controller button in it.
Rectangle {
    id: button
    property string text: ""
    property bool primary: false
    property bool focusedLook: false
    property string glyph: ""
    property color textColor: primary ? "#000000" : "#ffffff"
    property int fontSize: 16
    signal clicked()

    implicitHeight: 48
    implicitWidth: row.implicitWidth + (glyph ? 38 : 44)
    radius: 15
    color: primary ? "#ffffff" : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14))

    FocusRing { on: button.focusedLook; parentRadius: button.radius }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10
        Rectangle {
            visible: button.glyph !== "" && PlayInput.mode === "pad"
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 12
            color: button.primary ? "#000000" : "transparent"
            border.width: button.primary ? 0 : 1.5
            border.color: Qt.rgba(1, 1, 1, 0.8)
            ButtonGlyph {
                anchors.centerIn: parent
                button: button.glyph || "a"
                size: 24
                color: "transparent"
                border.width: 0
                // the glyph's own text is white on dark; on the white button it sits in a black disc
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.textColor
            font.family: "Geist"
            font.pixelSize: button.fontSize
            font.weight: button.primary ? Font.DemiBold : Font.Medium
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
