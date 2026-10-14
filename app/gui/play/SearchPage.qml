import QtQuick

// Search by name and by tag. With a controller: the on-screen keyboard, tag chips under it and the
// results on the right (RT jumps there). With a keyboard: just type.
FocusScope {
    id: page
    property var nav
    signal upFromTop()

    property string query: ""
    property var chosenTags: []
    readonly property var results: Play.search(query, chosenTags)
    readonly property bool pad: PlayInput.mode === "pad"

    function toggleTag(t) {
        var list = chosenTags.slice()
        var i = list.indexOf(t)
        if (i >= 0) list.splice(i, 1)
        else list.push(t)
        chosenTags = list
    }

    // keyboard mode: typing goes straight into the search
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_F16) { results_.forceActiveFocus(); event.accepted = true }  // RT
        else if (event.key === Qt.Key_Backspace) { query = query.slice(0, -1); event.accepted = true }
        else if (!pad && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) {
            query += event.text
            event.accepted = true
        }
    }

    Column {
        x: 64
        y: 100
        width: 420
        spacing: 18

        Rectangle {
            width: parent.width
            height: 56
            radius: 16
            color: "#1c1c1e"
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 18
                spacing: 12
                Text { text: "⌕"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.query.length ? page.query : (page.pad ? "Search games" : "Type to search")
                    color: page.query.length ? "#ffffff" : Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 20
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2; height: 24; color: "#ffffff"
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
                }
            }
        }

        Osk {
            id: osk
            visible: page.pad
            focus: true
            onTyped: function (ch) { page.query += ch }
            onErase: page.query = page.query.slice(0, -1)
            onClear: page.query = ""
            onLeaveDown: tagFlow.forceActiveFocus()
            onLeaveRight: results_.forceActiveFocus()
            onLeaveUp: page.upFromTop()
        }

        Text { text: "Tags"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }

        FocusScope {
            id: tagFlow
            width: parent.width
            height: flow.height
            property int current: 0
            Keys.onLeftPressed: current = Math.max(0, current - 1)
            Keys.onRightPressed: current = Math.min(tagRepeater.count - 1, current + 1)
            Keys.onUpPressed: page.pad ? osk.forceActiveFocus() : page.upFromTop()
            Keys.onDownPressed: results_.forceActiveFocus()
            Keys.onReturnPressed: page.toggleTag(Play.tags[current])
            Flow {
                id: flow
                width: parent.width
                spacing: 8
                Repeater {
                    id: tagRepeater
                    model: Play.tags.slice(0, 14)
                    Rectangle {
                        readonly property bool on: page.chosenTags.indexOf(modelData) >= 0
                        height: 36
                        width: label.implicitWidth + 28
                        radius: 18
                        color: on ? "#ffffff" : "#1c1c1e"
                        FocusRing { on: tagFlow.activeFocus && tagFlow.current === index; parentRadius: 18 }
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: modelData + (parent.on ? "  ✓" : "")
                            color: parent.on ? "#000000" : "#ffffff"
                            font.pixelSize: 14
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleTag(modelData) }
                    }
                }
            }
        }
    }

    Text {
        x: 532
        y: 142
        text: page.results.length + (page.results.length === 1 ? " game" : " games")
              + (page.query ? " for “" + page.query + "”" : "")
              + (page.chosenTags.length ? " · " + page.chosenTags.join(", ") : "")
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 14
    }

    GridView {
        id: results_
        x: 532
        y: 172
        width: 2 * 344
        height: 520
        clip: true
        cellWidth: 344
        cellHeight: 172
        model: page.results
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        highlightRangeMode: GridView.ApplyRange
        preferredHighlightBegin: 10
        preferredHighlightEnd: 360
        highlightMoveDuration: 160
        Keys.onLeftPressed: function (event) {
            if (currentIndex % 2 === 0) (page.pad ? osk : tagFlow).forceActiveFocus()
            else event.accepted = false
        }
        Keys.onUpPressed: function (event) {
            if (currentIndex < 2) page.upFromTop()
            else event.accepted = false
        }
        Keys.onReturnPressed: page.nav.launch(page.results[currentIndex])
        Keys.onMenuPressed: page.nav.openGame(page.results[currentIndex])
        delegate: Item {
            width: 344
            height: 172
            readonly property bool focused: GridView.isCurrentItem && results_.activeFocus
            z: focused ? 2 : 1
            GameArt {
                x: 6; y: 8
                width: 326
                height: 150
                game: modelData
                kind: "banner"
                showName: false
                scale: parent.focused ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 150 } }
                Column {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                    Text { text: modelData.name; color: "#ffffff"; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { text: modelData.tags.slice(0, 2).join(" · "); color: Qt.rgba(1, 1, 1, 0.65); font.pixelSize: 12 }
                }
                FocusRing { on: parent.parent.focused }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (!page.pad) results_.currentIndex = index
                    onClicked: page.nav.openGame(modelData)
                    onDoubleClicked: page.nav.launch(modelData)
                }
            }
        }
    }

    Text {
        visible: page.results.length === 0
        x: 532
        y: 200
        text: "Nothing matches. Try fewer tags."
        color: Qt.rgba(1, 1, 1, 0.6)
        font.pixelSize: 16
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: [
            { b: "a", label: "Type", key: "Enter" },
            { b: "x", label: "Delete", key: "Backspace" },
            { b: "y", label: "Space" },
            { b: "rt", label: "Results" },
            { b: "b", label: "Home", key: "Esc" }
        ]
    }
}
