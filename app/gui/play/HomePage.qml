import QtQuick

// Home: the focused game fills the banner; rows of games below ("Continue playing", recommendations,
// one row per favourite tag). Each row keeps its own position, like on a TV.
FocusScope {
    id: page
    property var nav
    signal upFromTop()

    readonly property var rows: Play.rows
    property var current: null

    function updateCurrent() {
        var row = rowsView.currentItem
        var game = row ? row.currentGame : null
        if (game !== current) {
            heroFade.restart()
            current = game
        }
    }
    onRowsChanged: Qt.callLater(updateCurrent)

    Keys.onUpPressed: {
        if (rowsView.currentIndex > 0) rowsView.decrementCurrentIndex()
        else page.upFromTop()
    }
    Keys.onDownPressed: if (rowsView.currentIndex < rowsView.count - 1) rowsView.incrementCurrentIndex()
    Keys.onLeftPressed: if (rowsView.currentItem) rowsView.currentItem.tiles.decrementCurrentIndex()
    Keys.onRightPressed: if (rowsView.currentItem) rowsView.currentItem.tiles.incrementCurrentIndex()
    Keys.onReturnPressed: nav.launch(current)
    Keys.onEnterPressed: nav.launch(current)
    Keys.onMenuPressed: nav.openGame(current)

    // banner
    GameArt {
        id: banner
        width: 1280
        height: 470
        radius: 0
        game: page.current
        kind: "banner"
        showName: false
    }
    Rectangle { width: 640; height: 470; color: Qt.rgba(0, 0, 0, 0.62) }
    Rectangle { width: 1280; height: 92; color: Qt.rgba(0, 0, 0, 0.35) }  // keeps the top bar readable
    Rectangle { y: 400; width: 1280; height: 320; color: "#000000" }

    Column {
        id: heroText
        x: 64
        y: 112
        width: 540
        spacing: 16
        visible: page.current !== null

        NumberAnimation on opacity { id: heroFade; from: 0.25; to: 1; duration: 260; running: false }

        Item {
            width: parent.width
            height: logo.status === Image.Ready ? 96 : title.implicitHeight
            Image {
                id: logo
                source: page.current ? (page.current.logo || "") : ""
                height: 96
                width: parent.width
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                sourceSize.height: 192
                visible: status === Image.Ready
            }
            Text {
                id: title
                visible: logo.status !== Image.Ready
                width: parent.width
                text: page.current ? page.current.name : ""
                color: "#ffffff"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: 52
                font.weight: Font.Bold
                lineHeight: 0.95
            }
        }

        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: page.current ? [page.current.year].concat(page.current.tags.slice(0, 3)).filter(function (t) { return !!t }) : []
                Rectangle {
                    height: 26
                    width: chip.implicitWidth + 24
                    radius: 13
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Text { id: chip; anchors.centerIn: parent; text: modelData; color: "#ffffff"; font.pixelSize: 13 }
                }
            }
        }

        Text {
            width: parent.width
            text: page.current ? page.current.blurb : ""
            color: Qt.rgba(1, 1, 1, 0.8)
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: 15
            lineHeight: 1.25
        }

        Row {
            spacing: 12
            PillButton { text: "Play"; primary: true; glyph: "a"; onClicked: page.nav.launch(page.current) }
            PillButton { text: "Details"; glyph: "x"; onClicked: page.nav.openGame(page.current) }
        }
    }

    // nothing to show yet
    Column {
        visible: rowsView.count === 0
        anchors.centerIn: parent
        spacing: 12
        width: 560
        Rectangle { width: 40; height: 40; radius: 20; color: "#ffffff"; anchors.horizontalCenter: parent.horizontalCenter }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Play.emptyTitle
            color: "#ffffff"
            font.pixelSize: 24
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Play.emptyText
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 15
            wrapMode: Text.WordWrap
            lineHeight: 1.3
        }
    }

    ListView {
        id: rowsView
        y: 420
        width: 1280
        height: 300
        model: page.rows
        spacing: 24
        clip: false
        interactive: false
        focus: true
        keyNavigationEnabled: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: 184
        highlightMoveDuration: 240
        onCurrentIndexChanged: page.updateCurrent()
        Component.onCompleted: page.updateCurrent()

        delegate: Item {
            id: rowItem
            width: 1280
            height: 184
            property alias tiles: tiles
            readonly property var currentGame: modelData.games.length ? modelData.games[Math.max(0, tiles.currentIndex)] : null
            readonly property int rowIndex: index
            readonly property bool isCurrentRow: ListView.isCurrentItem
            opacity: isCurrentRow ? 1 : 0.75
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
                x: 64
                text: modelData.title
                color: "#ffffff"
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            ListView {
                id: tiles
                y: 34
                width: 1280
                height: 150
                orientation: ListView.Horizontal
                model: modelData.games
                spacing: 18
                leftMargin: 64
                rightMargin: 64
                clip: false
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: 64
                preferredHighlightEnd: 1280 - 64 - 256
                highlightMoveDuration: 180
                highlightMoveVelocity: -1
                onCurrentIndexChanged: if (rowItem.isCurrentRow) page.updateCurrent()

                delegate: Item {
                    width: 256
                    height: 144
                    y: 3
                    readonly property bool focused: rowItem.isCurrentRow && ListView.isCurrentItem && page.activeFocus
                    z: focused ? 2 : 1

                    GameArt {
                        anchors.fill: parent
                        game: modelData
                        kind: "banner"
                        scale: parent.focused ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        FocusRing { on: parent.parent.focused }

                        Rectangle {
                            visible: modelData.progress > 0
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14; bottomMargin: 5 }
                            height: 3
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.25)
                            Rectangle { width: parent.width * modelData.progress; height: 3; radius: 2; color: "#e8305e" }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (PlayInput.mode !== "pad") {
                                rowsView.currentIndex = rowItem.rowIndex
                                tiles.currentIndex = index
                                page.forceActiveFocus()
                            }
                        }
                        onClicked: page.nav.openGame(modelData)
                        onDoubleClicked: page.nav.launch(modelData)
                    }
                }
            }
        }

        // mouse wheel moves between rows
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function (wheel) {
                if (wheel.angleDelta.y < 0) rowsView.incrementCurrentIndex()
                else rowsView.decrementCurrentIndex()
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
            { b: "y", label: "Search", key: "Ctrl F" },
            { b: "lb", label: "Tabs" },
            { b: "b", label: "Back to Dot", key: "Esc" }
        ]
    }
}
