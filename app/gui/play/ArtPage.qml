import QtQuick

// Change art: pictures from SteamGridDB, one tab per kind (cover, banner, logo, icon). LB/RB switch tabs.
FocusScope {
    id: page
    property var nav
    property var game

    readonly property var kinds: [
        { id: "cover", label: "Cover", w: 140, h: 210, cols: 5 },
        { id: "banner", label: "Banner", w: 380, h: 124, cols: 2 },
        { id: "logo", label: "Logo", w: 380, h: 130, cols: 2 },
        { id: "icon", label: "Icon", w: 120, h: 120, cols: 6 }
    ]
    property int kindIndex: 0
    readonly property var kind: kinds[kindIndex]
    property var results: []
    property bool loading: false
    readonly property var picked: results.length ? results[Math.max(0, grid.currentIndex)] : null

    function load() {
        loading = true
        results = []
        Play.artSearch(game.key, kind.id)
    }
    Component.onCompleted: load()
    onKindIndexChanged: load()
    Connections {
        target: Play
        function onArtResults(k, list) {
            if (k === page.kind.id) {
                page.results = list
                page.loading = false
            }
        }
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_F13) { kindIndex = (kindIndex + 3) % 4; event.accepted = true }       // LB
        else if (event.key === Qt.Key_F14) { kindIndex = (kindIndex + 1) % 4; event.accepted = true }  // RB
        else if (event.key === Qt.Key_Menu) { Play.resetArt(game.key, kind.id); event.accepted = true } // X
    }
    Keys.onEscapePressed: nav.back()
    Keys.onBackPressed: nav.back()

    Rectangle { anchors.fill: parent; color: "#000000" }

    Column {
        x: 64; y: 32
        spacing: 4
        Text { text: page.game ? page.game.name : ""; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 14 }
        Text { text: "Change art"; color: "#ffffff"; font.pixelSize: 28; font.weight: Font.DemiBold }
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 64
        y: 64
        text: page.loading ? "Looking on SteamGridDB…" : "From SteamGridDB · " + page.results.length + " pictures"
        color: Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 13
    }

    Row {
        x: 64; y: 112
        spacing: 6
        ButtonGlyph { visible: PlayInput.mode === "pad"; button: "lb"; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: page.kinds
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                width: kindLabel.implicitWidth + 36
                radius: 18
                color: index === page.kindIndex ? "#ffffff" : "#1c1c1e"
                Text { id: kindLabel; anchors.centerIn: parent; text: modelData.label; color: index === page.kindIndex ? "#000000" : "#ffffff"; font.pixelSize: 14; font.weight: index === page.kindIndex ? Font.DemiBold : Font.Normal }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.kindIndex = index }
            }
        }
        ButtonGlyph { visible: PlayInput.mode === "pad"; button: "rb"; anchors.verticalCenter: parent.verticalCenter }
    }

    GridView {
        id: grid
        x: 58
        y: 168
        width: page.kind.cols * (page.kind.w + 16) + 16
        height: 720 - 168 - 80
        clip: true
        focus: true
        cellWidth: page.kind.w + 16
        cellHeight: page.kind.h + 16
        topMargin: 8
        leftMargin: 8
        model: page.results
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        highlightRangeMode: GridView.ApplyRange
        preferredHighlightBegin: 8
        preferredHighlightEnd: height - page.kind.h - 24
        highlightMoveDuration: 150
        Keys.onReturnPressed: if (page.picked) Play.setArt(page.game.key, page.kind.id, page.picked.url)
        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight
            readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
            z: focused ? 2 : 1
            Rectangle {
                x: 6; y: 6
                width: page.kind.w
                height: page.kind.h
                radius: 12
                color: modelData.color || "#1c1c1e"
                scale: parent.focused ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 140 } }
                Image {
                    anchors.fill: parent
                    anchors.margins: page.kind.id === "logo" ? 10 : 0
                    source: modelData.thumb || ""
                    fillMode: page.kind.id === "logo" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: page.kind.w * 2
                }
                Rectangle {
                    visible: !!modelData.inUse
                    x: 8; y: 8
                    width: inUse.implicitWidth + 16; height: 22; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.7)
                    Text { id: inUse; anchors.centerIn: parent; text: "In use"; color: "#ffffff"; font.pixelSize: 11 }
                }
                FocusRing { on: parent.parent.focused; parentRadius: 12 }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (PlayInput.mode !== "pad") grid.currentIndex = index
                    onClicked: Play.setArt(page.game.key, page.kind.id, modelData.url)
                }
            }
        }
    }

    Column {
        x: 1280 - 64 - 250
        y: 168
        width: 250
        spacing: 12
        Text { text: "Preview in your library"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }
        Rectangle {
            width: 250
            height: page.kind.id === "cover" ? 300 : (page.kind.id === "icon" ? 250 : 120)
            radius: 14
            color: page.picked && page.picked.color ? page.picked.color : (page.game ? page.game.color : "#1c1c1e")
            Image {
                anchors.fill: parent
                anchors.margins: page.kind.id === "logo" ? 16 : 0
                source: page.picked ? (page.picked.url || "") : ""
                fillMode: page.kind.id === "logo" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 500
            }
        }
        Text { text: page.game ? page.game.name : ""; color: "#ffffff"; font.pixelSize: 15; font.weight: Font.DemiBold }
        Text {
            width: parent.width
            text: (page.picked && page.picked.author ? "By " + page.picked.author + " on SteamGridDB. " : "") + "Saved on this Dot; the PC isn't changed."
            color: Qt.rgba(1, 1, 1, 0.55)
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            lineHeight: 1.3
        }
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: [
            { b: "a", label: "Use this " + page.kind.label.toLowerCase(), key: "Enter" },
            { b: "x", label: "Back to default", key: "Menu" },
            { b: "b", label: "Done", key: "Esc" }
        ]
    }
}
