import QtQuick

// A controller button as drawn on the controller in use: A/B/X/Y on Xbox, cross/circle/square/triangle on
// PlayStation, Nintendo's labels on Switch. Buttons are named by position, like SDL: "a" is the bottom face
// button, "b" the right one, "x" the left one, "y" the top one.
Rectangle {
    id: glyph
    property string button: "a"
    property bool filled: false
    property int size: 22

    readonly property string label: {
        var labels = {
            xbox: { a: "A", b: "B", x: "X", y: "Y", lb: "LB", rb: "RB", lt: "LT", rt: "RT", menu: "≡", view: "⧉", guide: "◉", lr: "◀ ▶" },
            playstation: { a: "✕", b: "○", x: "□", y: "△", lb: "L1", rb: "R1", lt: "L2", rt: "R2", menu: "≡", view: "⧉", guide: "◉", lr: "◀ ▶" },
            "switch": { a: "B", b: "A", x: "Y", y: "X", lb: "L", rb: "R", lt: "ZL", rt: "ZR", menu: "+", view: "−", guide: "◉", lr: "◀ ▶" }
        }
        var set = labels[PlayInput.padType] || labels.xbox
        return set[button] || button.toUpperCase()
    }
    readonly property bool wide: label.length > 1 && label !== "◉"

    implicitWidth: wide ? text.implicitWidth + size * 0.55 : size
    implicitHeight: size
    radius: wide ? size * 0.28 : size / 2
    color: filled ? "#ffffff" : "transparent"
    border.width: filled ? 0 : 1.5
    border.color: Qt.rgba(1, 1, 1, 0.8)

    Text {
        id: text
        anchors.centerIn: parent
        text: glyph.label
        color: glyph.filled ? "#000000" : "#ffffff"
        font.family: "Geist"
        font.pixelSize: Math.round(glyph.size * 0.5)
        font.weight: Font.Bold
    }
}
