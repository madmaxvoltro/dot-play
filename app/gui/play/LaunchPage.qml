import QtQuick
import QtQuick.Effects

// Starting a game: its art blurred behind its logo, the Dot pulsing, and where it is: PC awake,
// connected, starting the game. Hands the screen to the stream once the picture arrives, and comes back
// here (then pops) when the stream ends. Errors stay on this screen until B.
FocusScope {
    id: page
    property var nav
    property var game

    property var session: null
    property int step: 0             // 0 connecting, 1 connected, 2 starting the game
    property string error: ""
    property bool stopping: false
    readonly property var info: game ? Play.streamInfo(game.key) : ({})

    Keys.onEscapePressed: if (error || !session) nav.back()
    Keys.onBackPressed: if (error || !session) nav.back()
    Keys.onReturnPressed: if (error) nav.back()

    function start() {
        if (Play.preview) {   // the screen preview has no Moonlight to stream with
            step = 2
            return
        }
        session = Play.createSession(game.key)
        if (!session) {
            if (!Play.preview) error = "Couldn't start " + game.name + "."
            return
        }
        session.stageStarting.connect(function (stage) { page.step = 2 })
        session.stageFailed.connect(function (stage, code, ports) {
            page.error = "Starting " + stage + " failed (error " + code + ")."
                + (ports ? "\nCheck the firewall on the PC for port(s) " + ports + "." : "")
        })
        session.displayLaunchError.connect(function (text) { page.error = text })
        session.connectionStarted.connect(function () {
            Play.streamStarted(game.key)
            page.Window.window.visible = false
        })
        session.quitStarting.connect(function () {
            page.stopping = true
            page.Window.window.visible = true
        })
        session.sessionFinished.connect(function (portTestResult) {
            Play.streamEnded(game.key)
            PlayInput.enable()
            page.Window.window.visible = true
            page.session = null
            if (!page.error) page.nav.back()
        })
        session.readyForDeletion.connect(function () { page.session = null; gc() })

        PlayInput.disable()
        if (!session.initialize(page.Window.window)) {
            PlayInput.enable()
            if (!error) error = "Couldn't set up the stream on this Dot."
            session = null
            return
        }
        step = 1
        startTimer.start()
    }
    Timer { id: startTimer; interval: 50; onTriggered: { gc(); page.session.start() } }
    Component.onCompleted: Qt.callLater(start)

    Rectangle { anchors.fill: parent; color: "#000000" }

    GameArt {
        id: art
        anchors.fill: parent
        anchors.margins: -40
        radius: 0
        game: page.game
        kind: "banner"
        showName: false
        visible: false
    }
    MultiEffect {
        anchors.fill: art
        source: art
        blurEnabled: true
        blur: 1.0
        blurMax: 48
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.7) }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 200
        spacing: 10
        width: 900
        Image {
            id: logo
            anchors.horizontalCenter: parent.horizontalCenter
            source: page.game ? (page.game.logo || "") : ""
            height: 110
            width: 600
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.height: 220
            visible: status === Image.Ready
        }
        Text {
            visible: logo.status !== Image.Ready
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: page.game ? page.game.name : ""
            color: "#ffffff"
            wrapMode: Text.WordWrap
            font.pixelSize: 64
            font.weight: Font.Bold
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 400
        spacing: 26

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20; height: 20; radius: 10
            color: page.error ? "#e8305e" : "#ffffff"
            SequentialAnimation on scale {
                running: !page.error
                loops: Animation.Infinite
                NumberAnimation { to: 0.82; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        Row {
            visible: !page.error && !page.stopping
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 28
            Repeater {
                model: [
                    page.game ? page.game.pc + " is awake" : "",
                    "Connected",
                    page.game ? "Starting " + page.game.name : ""
                ]
                Text {
                    readonly property bool done: index < page.step
                    readonly property bool now: index === page.step
                    text: (done ? "✓  " : "") + modelData
                    visible: index <= page.step
                    color: now ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 15
                    font.weight: now ? Font.DemiBold : Font.Normal
                }
            }
        }
        Text {
            visible: page.stopping && !page.error
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Stopping " + (page.game ? page.game.name : "") + "…"
            color: "#ffffff"
            font.pixelSize: 15
        }
        Text {
            visible: page.error !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: 760
            horizontalAlignment: Text.AlignHCenter
            text: page.error
            color: "#ffffff"
            wrapMode: Text.WordWrap
            font.pixelSize: 16
            lineHeight: 1.3
        }
        Text {
            visible: !page.error
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.info.summary || ""
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 13
        }
    }

    HintBar {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        hints: page.error ? [{ b: "b", label: "Back", key: "Esc" }]
                          : [{ b: "guide", label: "Opens the menu in game", key: "Ctrl Alt Shift Q" }]
    }
}
