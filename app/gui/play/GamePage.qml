import QtQuick

// One game: banner, cover, title, tags, Play, which PC, which stream profile, the ⋮ menu (Identify,
// Change art, profile, favourite, hide), play time, IGDB's summary and screenshots.
FocusScope {
    id: page
    property var nav
    property var game
    // re-read the game when anything changes (art, match, profile)
    readonly property var g: { Play.games; return game ? (Play.game(game.key).key ? Play.game(game.key) : game) : null }

    property int button: 0           // 0 Play, 1 PC, 2 Profile, 3 ⋮
    property string popup: ""        // "", "menu", "pc", "profile"
    property int popupIndex: 0

    readonly property var menuItems: g ? [
        { id: "identify", label: "Identify game…", note: "wrong match?" },
        { id: "art", label: "Change art…" },
        { id: "profile", label: "Stream profile…" },
        { id: "favourite", label: g.favourite ? "Remove from favourites" : "Add to favourites" },
        { id: "hide", label: "Hide from library", dim: true }
    ] : []
    readonly property var popupItems: {
        if (popup === "menu") return menuItems
        if (popup === "pc") return g.pcs.map(function (p) { return { id: p, label: p, on: p === g.pc } })
        if (popup === "profile") return Play.profiles.map(function (p) { return { id: p.id, label: p.name, on: p.id === g.profileId } })
            .concat([{ id: "__edit", label: "Edit profiles…", dim: true }])
        return []
    }

    function openPopup(kind) {
        popup = kind
        popupIndex = 0
        popupList.forceActiveFocus()
    }
    function closePopup() {
        popup = ""
        page.forceActiveFocus()
    }
    function choose(item) {
        var kind = popup
        closePopup()
        if (kind === "menu") {
            if (item.id === "identify") nav.openIdentify(g)
            else if (item.id === "art") nav.openArt(g)
            else if (item.id === "profile") openPopup("profile")
            else if (item.id === "favourite") Play.setFavourite(g.key, !g.favourite)
            else if (item.id === "hide") { Play.setHidden(g.key, true); nav.back() }
        }
        else if (kind === "pc") Play.setGamePc(g.key, item.id)
        else if (kind === "profile") {
            if (item.id === "__edit") nav.openSettings("profiles")
            else Play.setGameProfile(g.key, item.id)
        }
    }
    function activate(i) {
        if (i === 0) nav.launch(g)
        else if (i === 1 && g.pcs.length > 1) openPopup("pc")
        else if (i === 2) openPopup("profile")
        else if (i === 3) openPopup("menu")
    }

    Keys.onLeftPressed: button = Math.max(0, button - 1)
    Keys.onRightPressed: button = Math.min(3, button + 1)
    Keys.onReturnPressed: activate(button)
    Keys.onMenuPressed: openPopup("menu")
    Keys.onEscapePressed: nav.back()
    Keys.onBackPressed: nav.back()

    Rectangle { anchors.fill: parent; color: "#000000" }

    GameArt {
        width: 1280
        height: 400
        radius: 0
        game: page.g
        kind: "banner"
        showName: false
    }
    Rectangle { width: 1280; height: 250; color: Qt.rgba(0, 0, 0, 0.25) }
    Rectangle { y: 250; width: 1280; height: 470; color: "#000000" }

    Row {
        x: 64; y: 30
        spacing: 10
        ButtonGlyph { visible: PlayInput.mode === "pad"; button: "b"; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: PlayInput.mode === "pad" ? "Library" : "‹ Library"
            color: Qt.rgba(1, 1, 1, 0.8)
            font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: page.nav.back() }
        }
    }

    GameArt {
        x: 64; y: 168
        width: 188
        height: 282
        radius: 16
        game: page.g
        kind: "cover"
        showName: false
        cornerColor: "transparent"
    }

    Column {
        x: 284
        y: 264
        width: 1280 - 284 - 64
        spacing: 12

        Text {
            width: parent.width
            text: page.g ? page.g.name : ""
            color: "#ffffff"
            elide: Text.ElideRight
            font.pixelSize: 44
            font.weight: Font.Bold
        }
        Flow {
            width: parent.width
            spacing: 8
            Text {
                text: page.g ? [page.g.year, page.g.developer].filter(function (x) { return !!x }).join(" · ") : ""
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 13
                height: 24
                verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: page.g ? page.g.tags.slice(0, 5) : []
                Rectangle {
                    height: 24
                    width: tagText.implicitWidth + 22
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Text { id: tagText; anchors.centerIn: parent; text: modelData; color: "#ffffff"; font.pixelSize: 13 }
                }
            }
        }
        Item { width: 1; height: 8 }
        Row {
            spacing: 12
            PillButton {
                implicitHeight: 52
                primary: true
                glyph: "a"
                fontSize: 17
                text: page.g && page.g.running ? "Resume" : "Play"
                focusedLook: page.button === 0 && page.popup === "" && page.activeFocus
                onClicked: page.activate(0)
            }
            PillButton {
                implicitHeight: 52
                fontSize: 15
                text: page.g ? "On " + page.g.pc + (page.g.pcs.length > 1 ? "  ▾" : "") : ""
                focusedLook: page.button === 1 && page.popup === "" && page.activeFocus
                onClicked: page.activate(1)
            }
            PillButton {
                implicitHeight: 52
                fontSize: 15
                text: page.g ? "Profile: " + page.g.profileName : ""
                focusedLook: page.button === 2 && page.popup === "" && page.activeFocus
                onClicked: page.activate(2)
            }
            PillButton {
                implicitHeight: 52
                implicitWidth: 52
                fontSize: 26
                text: "⋮"
                focusedLook: page.button === 3 && page.popup === "" && page.activeFocus
                onClicked: page.activate(3)
            }
        }
    }

    Row {
        x: 284
        y: 520
        spacing: 36
        Repeater {
            model: page.g ? [
                { big: page.g.playedText, small: "played" },
                { big: page.g.lastPlayedText, small: "last played" },
                { big: page.g.profileName, small: "stream profile" }
            ] : []
            Column {
                Text { text: modelData.big; color: "#ffffff"; font.pixelSize: 22; font.weight: Font.DemiBold }
                Text { text: modelData.small; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }
            }
        }
    }
    Text {
        x: 284
        y: 590
        width: 560
        text: page.g ? (page.g.summary || "No details yet. Add an IGDB key in Settings › Game info and art.") : ""
        color: Qt.rgba(1, 1, 1, 0.75)
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        elide: Text.ElideRight
        font.pixelSize: 15
        lineHeight: 1.3
    }

    Column {
        x: 880
        y: 520
        width: 336
        spacing: 10
        visible: shots.count > 0
        Text { text: "Screenshots"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }
        Grid {
            columns: 2
            spacing: 10
            Repeater {
                id: shots
                model: page.g ? page.g.screenshots.slice(0, 4) : []
                Rectangle {
                    width: 163; height: 90; radius: 10; color: "#1c1c1e"; clip: true
                    Image { anchors.fill: parent; source: modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 330 }
                }
            }
        }
    }

    // popups: the ⋮ menu, PC chooser, profile chooser
    Rectangle {
        visible: page.popup !== ""
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: page.closePopup() }
    }
    Rectangle {
        visible: page.popup !== ""
        x: 900
        y: 250
        width: 316
        height: popupList.contentHeight + 16
        radius: 20
        color: "#1c1c1e"
        ListView {
            id: popupList
            x: 8; y: 8
            width: 300
            height: contentHeight
            interactive: false
            model: page.popupItems
            currentIndex: page.popupIndex
            keyNavigationEnabled: false
            Keys.onUpPressed: page.popupIndex = Math.max(0, page.popupIndex - 1)
            Keys.onDownPressed: page.popupIndex = Math.min(count - 1, page.popupIndex + 1)
            Keys.onReturnPressed: page.choose(page.popupItems[page.popupIndex])
            Keys.onEscapePressed: page.closePopup()
            Keys.onBackPressed: page.closePopup()
            Keys.onMenuPressed: page.closePopup()
            delegate: Rectangle {
                width: 300
                height: 48
                radius: 12
                readonly property bool focused: index === page.popupIndex
                color: focused ? "#ffffff" : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    text: modelData.label + (modelData.on ? "  ✓" : "")
                    color: parent.focused ? "#000000" : (modelData.dim ? Qt.rgba(1, 1, 1, 0.7) : "#ffffff")
                    font.pixelSize: 15
                    font.weight: parent.focused ? Font.DemiBold : Font.Normal
                }
                Text {
                    visible: !!modelData.note
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: modelData.note || ""
                    color: parent.focused ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 12
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: page.popupIndex = index
                    onClicked: page.choose(modelData)
                }
            }
        }
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: page.popup !== "" ? [
            { b: "a", label: "Choose", key: "Enter" },
            { b: "b", label: "Close", key: "Esc" }
        ] : [
            { b: "a", label: page.button === 0 ? "Play" : "Choose", key: "Enter" },
            { b: "x", label: "Menu", key: "Menu" },
            { b: "b", label: "Back", key: "Esc" }
        ]
    }
}
