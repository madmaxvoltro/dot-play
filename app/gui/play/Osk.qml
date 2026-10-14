import QtQuick

// The on-screen keyboard for typing with a controller: letters, numbers, space, delete and clear.
// A types the focused key, X deletes, Y adds a space. Hidden in keyboard mode, where you just type.
FocusScope {
    id: osk
    signal typed(string ch)
    signal erase()
    signal clear()
    signal leaveDown()
    signal leaveRight()
    signal leaveUp()

    property bool numbers: false
    readonly property var letters: "abcdefghijklmnopqrstuvwxyz".split("").concat(["123", "⌫"])
    readonly property var digits: "1234567890-:'&.!?".split("").concat(["", "", "", "", "", "", "", "", "", "abc", "⌫"])
    readonly property var keys: numbers ? digits : letters

    implicitWidth: 7 * 60
    implicitHeight: grid.height + 6 + 46

    function press(k) {
        if (k === "⌫") erase()
        else if (k === "123") numbers = true
        else if (k === "abc") numbers = false
        else if (k !== "") typed(k)
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Menu) { erase(); event.accepted = true }            // X
        else if (event.key === Qt.Key_Search) { typed(" "); event.accepted = true }  // Y
    }

    GridView {
        id: grid
        width: 7 * 60
        height: 4 * 52
        cellWidth: 60
        cellHeight: 52
        interactive: false
        focus: true
        model: osk.keys
        keyNavigationEnabled: true
        Keys.onDownPressed: function (event) {
            if (currentIndex + 7 >= count) bottomRow.forceActiveFocus()
            else event.accepted = false
        }
        Keys.onUpPressed: function (event) {
            if (currentIndex < 7) osk.leaveUp()
            else event.accepted = false
        }
        Keys.onRightPressed: function (event) {
            if (currentIndex % 7 === 6) osk.leaveRight()
            else event.accepted = false
        }
        Keys.onReturnPressed: osk.press(osk.keys[currentIndex])
        delegate: Rectangle {
            width: 54
            height: 46
            radius: 10
            readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
            color: focused ? "#ffffff" : "#1c1c1e"
            opacity: modelData === "" ? 0 : 1
            FocusRing { on: parent.focused; parentRadius: 10 }
            Text {
                anchors.centerIn: parent
                text: modelData
                color: parent.focused ? "#000000" : "#ffffff"
                font.pixelSize: modelData.length > 1 ? 14 : 16
                font.weight: parent.focused ? Font.DemiBold : Font.Normal
            }
            MouseArea { anchors.fill: parent; onClicked: osk.press(modelData) }
        }
    }

    Row {
        id: bottomRow
        y: grid.height + 6
        spacing: 6
        property int current: 0
        Keys.onLeftPressed: current = 0
        Keys.onRightPressed: function (event) {
            if (current === 0) current = 1
            else osk.leaveRight()
        }
        Keys.onUpPressed: grid.forceActiveFocus()
        Keys.onDownPressed: osk.leaveDown()
        Keys.onReturnPressed: current === 0 ? osk.typed(" ") : osk.clear()
        Repeater {
            model: ["Space", "Clear"]
            Rectangle {
                width: 3.5 * 60 - 6
                height: 46
                radius: 10
                readonly property bool focused: bottomRow.activeFocus && bottomRow.current === index
                color: focused ? "#ffffff" : "#1c1c1e"
                FocusRing { on: parent.focused; parentRadius: 10 }
                Text { anchors.centerIn: parent; text: modelData; color: parent.focused ? "#000000" : "#ffffff"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onClicked: index === 0 ? osk.typed(" ") : osk.clear() }
            }
        }
    }
}
