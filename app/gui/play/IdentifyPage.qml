import QtQuick

// "Which game is this?": search IGDB with the name as Sunshine has it (or one you type), pick the right one.
FocusScope {
    id: page
    property var nav
    property var game

    property string query: game ? game.sourceName || game.name : ""
    property var results: []
    property bool searching: false
    property bool typing: false
    property int current: 0
    readonly property bool pad: PlayInput.mode === "pad"

    function search() {
        searching = true
        Play.identifySearch(query)
    }
    Component.onCompleted: search()
    Connections {
        target: Play
        function onIdentifyResults(list) {
            page.results = list
            page.searching = false
            page.current = 0
        }
    }
    Timer { id: debounce; interval: 450; onTriggered: page.search() }
    onQueryChanged: debounce.restart()

    function choose() {
        if (results.length) {
            Play.identify(game.key, results[current].id)
            nav.back()
        }
    }

    Keys.onUpPressed: current = Math.max(0, current - 1)
    Keys.onDownPressed: current = Math.min(results.length - 1, current + 1)
    Keys.onReturnPressed: choose()
    Keys.onEscapePressed: nav.back()
    Keys.onBackPressed: nav.back()
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Search) { typing = true; osk.forceActiveFocus(); event.accepted = true }       // Y
        else if (event.key === Qt.Key_Menu) { Play.identifyNone(game.key); nav.back(); event.accepted = true }  // X
        else if (event.key === Qt.Key_Backspace) { query = query.slice(0, -1); event.accepted = true }
        else if (!pad && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) {
            query += event.text
            event.accepted = true
        }
    }

    Rectangle { anchors.fill: parent; color: "#0a0a0a" }

    Rectangle {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        y: page.typing ? 24 : (720 - height) / 2
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        width: 760
        height: content.implicitHeight + 56
        radius: 28
        color: "#1c1c1e"

        Column {
            id: content
            x: 28; y: 28
            width: 704
            spacing: 18

            Column {
                width: parent.width
                spacing: 6
                Text {
                    width: parent.width
                    text: "Which game is “" + (page.game ? page.game.sourceName || page.game.name : "") + "”?"
                    color: "#ffffff"
                    elide: Text.ElideRight
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: "As it's named on " + (page.game ? page.game.pc : "the PC") + ". Pick the right one and Dot Play fetches its details and art."
                    color: Qt.rgba(1, 1, 1, 0.6)
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                }
            }

            Rectangle {
                width: parent.width
                height: 52
                radius: 14
                color: "#2c2c2e"
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 16
                    spacing: 12
                    Text { text: "⌕"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: page.query; color: "#ffffff"; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {
                        visible: page.typing || !page.pad
                        width: 2; height: 22; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.searching ? "Searching…" : "IGDB"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 12
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: page.results.slice(0, 5)
                    Rectangle {
                        readonly property bool focused: index === page.current && !page.typing
                        width: parent.width
                        height: 82
                        radius: 14
                        color: focused ? "#ffffff" : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                        FocusRing { on: parent.focused && page.pad; parentRadius: 14 }
                        Rectangle {
                            x: 10; y: 10
                            width: 46; height: 62; radius: 7
                            color: "#3a2a24"
                            clip: true
                            Image { anchors.fill: parent; source: modelData.cover || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 92 }
                        }
                        Column {
                            x: 72
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 72 - 110
                            Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; color: parent.parent.focused ? "#000000" : "#ffffff"; font.pixelSize: 16; font.weight: Font.DemiBold }
                            Text { text: [modelData.year, modelData.detail].filter(function (x) { return !!x }).join(" · "); color: parent.parent.focused ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }
                        }
                        Text {
                            visible: index === 0
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Best match"
                            color: parent.focused ? "#000000" : Qt.rgba(1, 1, 1, 0.6)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: page.current = index
                            onClicked: { page.current = index; page.choose() }
                        }
                    }
                }
                Text {
                    visible: !page.searching && page.results.length === 0
                    text: "Nothing on IGDB by that name. Try another spelling."
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 15
                }
            }

            Row {
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width - noMatch.width - cancel.width - 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Not a game, or not listed? Keep Sunshine's own picture."
                    color: Qt.rgba(1, 1, 1, 0.55)
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                }
                PillButton { id: noMatch; implicitHeight: 44; fontSize: 14; text: "No match"; glyph: "x"; onClicked: { Play.identifyNone(page.game.key); page.nav.back() } }
                PillButton { id: cancel; implicitHeight: 44; fontSize: 14; text: "Cancel"; onClicked: page.nav.back() }
            }
        }
    }

    Osk {
        id: osk
        visible: page.typing && page.pad
        anchors.horizontalCenter: parent.horizontalCenter
        y: 720 - height - 80
        onTyped: function (ch) { page.query += ch }
        onErase: page.query = page.query.slice(0, -1)
        onClear: page.query = ""
        onLeaveUp: { page.typing = false; page.forceActiveFocus() }
        onLeaveDown: { page.typing = false; page.forceActiveFocus() }
        Keys.onEscapePressed: { page.typing = false; page.forceActiveFocus() }
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: page.typing ? [
            { b: "a", label: "Type" },
            { b: "x", label: "Delete" },
            { b: "b", label: "Done typing" }
        ] : [
            { b: "a", label: "Use this", key: "Enter" },
            { b: "y", label: "Edit name", key: "Type" },
            { b: "x", label: "No match" },
            { b: "b", label: "Cancel", key: "Esc" }
        ]
    }
}
