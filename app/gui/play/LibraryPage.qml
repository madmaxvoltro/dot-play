import QtQuick

// Library: every game as a cover, filtered by a tag on the left and sorted. Works the same with a
// controller (D-pad through the grid, left edge into the tags) and with a mouse (hover, click).
FocusScope {
    id: page
    property var nav
    signal upFromTop()

    property string tag: ""
    property int sort: 0
    readonly property var sorts: ["Recently played", "Most played", "A to Z"]
    readonly property var games: {
        var list = Play.search("", tag ? [tag] : [])
        var by = [
            function (a, b) { return b.lastPlayed - a.lastPlayed || a.name.localeCompare(b.name) },
            function (a, b) { return b.playMinutes - a.playMinutes || a.name.localeCompare(b.name) },
            function (a, b) { return a.name.localeCompare(b.name) }
        ][sort]
        return list.slice().sort(by)
    }

    // sidebar: All games + tags
    ListView {
        id: tagList
        x: 48
        y: 104
        width: 210
        height: 560
        clip: true
        keyNavigationEnabled: false
        model: [""].concat(Play.tags)
        spacing: 2
        delegate: Rectangle {
            width: 210
            height: 38
            radius: 10
            readonly property bool chosen: modelData === page.tag
            color: chosen ? "#1c1c1e" : (tagMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
            FocusRing { on: tagList.activeFocus && parent.ListView.isCurrentItem; parentRadius: 10 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                text: modelData === "" ? "All games" : modelData
                color: parent.chosen ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: 14
                font.weight: parent.chosen ? Font.DemiBold : Font.Normal
            }
            MouseArea {
                id: tagMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { page.tag = modelData; tagList.currentIndex = index }
            }
        }
        Keys.onUpPressed: currentIndex > 0 ? decrementCurrentIndex() : page.upFromTop()
        Keys.onDownPressed: incrementCurrentIndex()
        Keys.onReturnPressed: page.tag = model[currentIndex]
        Keys.onRightPressed: grid.forceActiveFocus()
        onCurrentIndexChanged: if (activeFocus) page.tag = model[currentIndex]
    }

    Row {
        x: 290
        y: 104
        spacing: 14
        Text { text: page.tag || "Library"; color: "#ffffff"; font.pixelSize: 24; font.weight: Font.DemiBold; anchors.baseline: count.baseline }
        Text { id: count; text: page.games.length + (page.games.length === 1 ? " game" : " games"); color: Qt.rgba(1, 1, 1, 0.5); font.pixelSize: 14 }
    }
    PillButton {
        x: 1280 - 64 - width
        y: 98
        implicitHeight: 36
        fontSize: 13
        text: page.sorts[page.sort] + "  ▾"
        glyph: "y"
        onClicked: page.sort = (page.sort + 1) % page.sorts.length
    }

    GridView {
        id: grid
        x: 290
        y: 154
        width: 6 * 158 + 16
        height: 720 - 154 - 76
        focus: true
        clip: true
        cellWidth: 158
        cellHeight: 278
        model: page.games
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 160
        preferredHighlightBegin: 20
        preferredHighlightEnd: 260
        highlightRangeMode: GridView.ApplyRange
        topMargin: 16
        leftMargin: 8
        boundsBehavior: Flickable.StopAtBounds

        Keys.onLeftPressed: function (event) {
            if (currentIndex % 6 === 0) tagList.forceActiveFocus()
            else event.accepted = false
        }
        Keys.onUpPressed: function (event) {
            if (currentIndex < 6) page.upFromTop()
            else event.accepted = false
        }
        Keys.onReturnPressed: page.nav.launch(page.games[currentIndex])
        Keys.onMenuPressed: page.nav.openGame(page.games[currentIndex])
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Search) { page.sort = (page.sort + 1) % page.sorts.length; event.accepted = true }
        }

        delegate: Item {
            width: 158
            height: 278
            readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
            z: focused ? 2 : 1

            GameArt {
                id: cover
                x: 6
                y: 4
                width: 140
                height: 210
                game: modelData
                kind: "cover"
                radius: 12
                showName: false
                scale: parent.focused ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                // a cover without a picture still says what it is
                Text {
                    visible: !modelData.cover
                    anchors.fill: parent
                    anchors.margins: 14
                    text: modelData.name
                    color: "#ffffff"
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignBottom
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    visible: hover.containsMouse && PlayInput.mode !== "pad"
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 52
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        PillButton { implicitHeight: 34; implicitWidth: 76; fontSize: 14; primary: true; text: "▶ Play"; onClicked: page.nav.launch(modelData) }
                        PillButton { implicitHeight: 34; implicitWidth: 34; text: "⋮"; onClicked: page.nav.openGame(modelData) }
                    }
                }
                FocusRing { on: cover.parent.focused; parentRadius: 12 }
            }
            Text {
                x: 6
                y: 224
                width: 140
                text: modelData.name
                color: "#ffffff"
                elide: Text.ElideRight
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                x: 6
                y: 244
                width: 140
                text: modelData.playedText + " · " + modelData.pc
                color: Qt.rgba(1, 1, 1, 0.5)
                elide: Text.ElideRight
                font.pixelSize: 12
            }
            MouseArea {
                id: hover
                anchors.fill: cover
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: if (PlayInput.mode !== "pad") grid.currentIndex = index
            }
        }
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: [
            { b: "a", label: "Play", key: "Enter" },
            { b: "x", label: "Details", key: "Menu" },
            { b: "y", label: "Sort" },
            { b: "b", label: "Home", key: "Esc" }
        ]
    }
}
