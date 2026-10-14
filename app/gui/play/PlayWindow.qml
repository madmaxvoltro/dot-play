import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Dot Play's window. Everything is laid out on a 1280 x 720 stage and scaled to the screen, so a 1080p TV
// and a 4K monitor show the same layout, just sharper.
ApplicationWindow {
    id: win
    width: 1280
    height: 720
    visible: true
    color: "#000000"
    title: "Dot Play"
    font.family: "Geist"

    Component.onCompleted: {
        if (!Play.preview) {
            showFullScreen()
        }
        PlayInput.enable()
    }

    onActiveChanged: PlayInput.notifyWindowFocus(active)

    function goBackToDot() {
        Play.backToDot()
    }

    // For screenshots: save what's on screen as a PNG
    function grab(path) {
        stage.grabToImage(function (result) { result.saveToFile(path) })
    }

    // For screenshots and tests: go straight to one screen
    function showScreen(name) {
        var game = Play.games.length ? Play.games[0] : null
        stack.pop(null)
        var tabs = { home: 0, library: 1, search: 2, settings: 3 }
        if (name in tabs) shellItem.showTab(tabs[name])
        else if (name === "game") stack.openGame(game)
        else if (name === "identify") stack.openIdentify(game)
        else if (name === "art") stack.openArt(game)
        else if (name === "launch") stack.launch(game)
    }

    Item {
        id: stage
        width: 1280
        height: 720
        anchors.centerIn: parent
        scale: Math.min(win.width / 1280, win.height / 720)

        StackView {
            id: stack
            anchors.fill: parent
            focus: true
            initialItem: shell

            function openGame(game) {
                if (game) push(gamePageComponent, { nav: stack, game: game })
            }
            function launch(game) {
                if (game) push(launchPageComponent, { nav: stack, game: game })
            }
            function openIdentify(game) { push(identifyPageComponent, { nav: stack, game: game }) }
            function openArt(game) { push(artPageComponent, { nav: stack, game: game }) }
            function openSettings(section) {
                pop(null)
                shellItem.showTab(3)
                if (section) shellItem.settingsPage.showSection(section)
            }
            function back() {
                if (depth > 1) pop()
            }

            pushEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 1.03; to: 1; duration: 240; easing.type: Easing.OutCubic }
                }
            }
            pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160 } }
            popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
            popExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160 }
                    NumberAnimation { property: "scale"; from: 1; to: 1.03; duration: 160 }
                }
            }
            replaceEnter: pushEnter
            replaceExit: pushExit

            onCurrentItemChanged: if (currentItem) currentItem.forceActiveFocus()
        }

        Component {
            id: shell
            FocusScope {
                id: shellRoot
                property int tab: 0
                readonly property var tabs: ["Home", "Library", "Search", "Settings"]
                property alias settingsPage: settingsPage
                Component.onCompleted: shellItem = shellRoot

                function showTab(i) {
                    tab = (i + tabs.length) % tabs.length
                    pages.children[tab].forceActiveFocus()
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_F13) { showTab(tab - 1); event.accepted = true }        // LB
                    else if (event.key === Qt.Key_F14) { showTab(tab + 1); event.accepted = true }   // RB
                    else if (event.key === Qt.Key_Search || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
                        showTab(2); event.accepted = true
                    }
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                        if (tab !== 0) showTab(0)
                        else if (exitToast.visible) win.goBackToDot()
                        else exitToast.show()
                        event.accepted = true
                    }
                }

                // top bar
                FocusScope {
                    id: tabBar
                    z: 10  // above the pages: Home draws its banner underneath the bar
                    x: 64; y: 28
                    width: 1152; height: 40
                    Keys.onLeftPressed: shellRoot.tab = Math.max(0, shellRoot.tab - 1)
                    Keys.onRightPressed: shellRoot.tab = Math.min(shellRoot.tabs.length - 1, shellRoot.tab + 1)
                    Keys.onDownPressed: shellRoot.showTab(shellRoot.tab)
                    Keys.onReturnPressed: shellRoot.showTab(shellRoot.tab)

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Rectangle { width: 18; height: 18; radius: 9; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Play"; color: "#ffffff"; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 22; height: 1 }
                        ButtonGlyph { visible: PlayInput.mode === "pad"; button: "lb"; anchors.verticalCenter: parent.verticalCenter }
                        Repeater {
                            model: shellRoot.tabs
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                width: tabLabel.implicitWidth + 32
                                radius: 16
                                color: index === shellRoot.tab ? "#ffffff" : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                                FocusRing { on: tabBar.activeFocus && index === shellRoot.tab; parentRadius: 16 }
                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: index === shellRoot.tab ? "#000000" : Qt.rgba(1, 1, 1, 0.7)
                                    font.pixelSize: 14
                                    font.weight: index === shellRoot.tab ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: shellRoot.showTab(index)
                                }
                            }
                        }
                        ButtonGlyph { visible: PlayInput.mode === "pad"; button: "rb"; anchors.verticalCenter: parent.verticalCenter }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 24
                        Row {
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: Play.anyOnline ? "#ffffff" : "transparent"
                                border.width: 1.5; border.color: Qt.rgba(1, 1, 1, 0.6)
                            }
                            Text { text: Play.pcSummary; color: Qt.rgba(1, 1, 1, 0.7); font.pixelSize: 13 }
                        }
                        Text {
                            id: clock
                            text: Qt.formatTime(new Date(), "HH:mm")
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.Light
                            Timer { interval: 5000; running: true; repeat: true; onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm") }
                        }
                    }
                }

                StackLayout {
                    id: pages
                    anchors.fill: parent
                    currentIndex: shellRoot.tab
                    HomePage { nav: stack; onUpFromTop: tabBar.forceActiveFocus(); focus: true }
                    LibraryPage { nav: stack; onUpFromTop: tabBar.forceActiveFocus() }
                    SearchPage { nav: stack; onUpFromTop: tabBar.forceActiveFocus() }
                    SettingsPage { id: settingsPage; nav: stack; onUpFromTop: tabBar.forceActiveFocus() }
                }
            }
        }

        Rectangle {
            id: exitToast
            visible: false
            z: 100
            anchors.horizontalCenter: parent.horizontalCenter
            y: 610
            width: toastText.implicitWidth + 40
            height: 44
            radius: 22
            color: "#2c2c2e"
            function show() { visible = true; toastTimer.restart() }
            Text {
                id: toastText
                anchors.centerIn: parent
                text: PlayInput.mode === "pad" ? "Press " + backGlyph.label + " again to go back to Dot" : "Press Esc again to go back to Dot"
                color: "#ffffff"
                font.pixelSize: 15
            }
            ButtonGlyph { id: backGlyph; visible: false; button: "b" }
            Timer { id: toastTimer; interval: 2500; onTriggered: exitToast.visible = false }
        }
    }

    property var shellItem: null

    Component { id: gamePageComponent; GamePage {} }
    Component { id: launchPageComponent; LaunchPage {} }
    Component { id: identifyPageComponent; IdentifyPage {} }
    Component { id: artPageComponent; ArtPage {} }
}
