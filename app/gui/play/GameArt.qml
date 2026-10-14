import QtQuick

// A game's picture of one kind ("cover", "banner", "icon"), falling back to the next best picture and
// finally to a plain tile in the game's own colour with its name, so a game without art still looks intended.
Rectangle {
    id: art
    property var game: null
    property string kind: "banner"
    property bool showName: true
    property int nameSize: 15

    readonly property string source: {
        if (!game) return ""
        if (kind === "cover") return game.cover || ""
        if (kind === "icon") return game.icon || game.cover || ""
        return game.banner || game.screenshot || ""
    }

    // what's behind the tile: its picture's corners are covered in this colour, which rounds them off
    // without clipping (cheap on a Pi, and leaves room for the focus ring around the tile)
    property color cornerColor: "#000000"

    color: game ? game.color : "#1c1c1e"
    radius: 14

    Image {
        id: image
        anchors.fill: parent
        source: art.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Math.min(1920, Math.round(art.width * 2))
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // the name stays readable on any picture: a short dark band, not a wash over the whole tile
    Rectangle {
        visible: art.showName && name.text.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: name.implicitHeight + 22
        color: image.status === Image.Ready ? Qt.rgba(0, 0, 0, 0.55) : "transparent"
    }
    Text {
        id: name
        visible: art.showName
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        text: art.game ? art.game.name : ""
        color: "#ffffff"
        elide: Text.ElideRight
        font.family: "Geist"
        font.pixelSize: art.nameSize
        font.weight: Font.DemiBold
    }

    Rectangle {
        visible: art.radius > 0 && image.status === Image.Ready
        anchors.fill: parent
        anchors.margins: -art.radius
        radius: art.radius * 2
        color: "transparent"
        border.width: art.radius
        border.color: art.cornerColor
    }
}
