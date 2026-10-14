import QtQuick

// The pill of button hints at the bottom of every screen. With a controller it shows that controller's
// buttons; with a keyboard and mouse it shows the keys instead.
// hints: [{ b: "a", label: "Play", key: "Enter" }, ...]; a hint without `key` only shows with a controller.
Rectangle {
    id: bar
    property var hints: []
    readonly property bool pad: PlayInput.mode === "pad"

    visible: shown.length > 0
    readonly property var shown: hints.filter(function (h) { return bar.pad ? !!h.b : !!h.key })

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 38
    radius: height / 2
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.92)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 18

        Repeater {
            model: bar.shown

            Row {
                spacing: 7
                anchors.verticalCenter: parent.verticalCenter

                ButtonGlyph {
                    visible: bar.pad
                    anchors.verticalCenter: parent.verticalCenter
                    button: modelData.b || "a"
                    filled: index === 0
                }
                Rectangle {
                    visible: !bar.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: keyText.implicitWidth + 12
                    height: 20
                    radius: 5
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: modelData.key || ""
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.family: "Geist"
                        font.pixelSize: 11
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: "#ffffff"
                    font.family: "Geist"
                    font.pixelSize: 13
                }
            }
        }
    }
}
