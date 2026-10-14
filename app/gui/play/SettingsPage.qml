import QtQuick

// Settings: stream profiles (one Default plus your own, chosen per game), controllers, the IGDB and
// SteamGridDB keys, hidden games, about. TV-style: up/down picks a row, left/right changes it, A opens it.
// Gaming PCs and pairing stay in Dot's own Settings › Games.
FocusScope {
    id: page
    property var nav
    signal upFromTop()

    readonly property var sections: [
        { id: "profiles", label: "Stream profiles" },
        { id: "controllers", label: "Controllers" },
        { id: "meta", label: "Game info and art" },
        { id: "hidden", label: "Hidden games" },
        { id: "about", label: "About" }
    ]
    property int section: 0
    property int profileIndex: 0
    property int row: 0
    property string zone: "nav"          // nav | profiles | rows
    property string editing: ""          // the text field being typed into
    property string draft: ""
    readonly property bool pad: PlayInput.mode === "pad"

    function showSection(id) {
        for (var i = 0; i < sections.length; i++) if (sections[i].id === id) section = i
        zone = "nav"
    }

    readonly property var profile: Play.profiles.length ? Play.profiles[Math.min(profileIndex, Play.profiles.length - 1)] : null

    // option lists for profile rows
    readonly property var resolutions: [[1280, 720, "720p"], [1920, 1080, "1080p"], [2560, 1440, "1440p"], [3840, 2160, "4K"]]
    readonly property var rates: [30, 60, 90, 120, 144]
    readonly property var codecs: [["auto", "Auto"], ["h264", "H.264"], ["hevc", "HEVC"], ["av1", "AV1"]]
    readonly property var audios: [["stereo", "Stereo"], ["5.1", "5.1 surround"], ["7.1", "7.1 surround"]]
    readonly property var mice: [["game", "Captured by the game"], ["desktop", "Like a desktop pointer"]]
    readonly property var padIcons: [["auto", "Match the controller"], ["xbox", "Xbox"], ["playstation", "PlayStation"], ["switch", "Switch"]]

    function idx(list, test) { for (var i = 0; i < list.length; i++) if (test(list[i])) return i; return 0 }

    readonly property var rows: {
        var s = sections[section].id, p = profile, k = Play.keys
        if (s === "profiles" && p) {
            var res = resolutions[idx(resolutions, function (r) { return r[0] === p.width && r[1] === p.height })]
            var pcName = p.pc ? (Play.pcs.filter(function (x) { return x.uuid === p.pc })[0] || { name: "?" }).name : "The PC that's awake"
            return [
                { id: "name", label: "Name", value: p.name, kind: "text", locked: p.id === "default" },
                { id: "res", label: "Resolution", value: res[2], kind: "choice" },
                { id: "fps", label: "Frame rate", value: p.fps + " fps", kind: "choice" },
                { id: "bitrate", label: "Bitrate", value: Math.round(p.bitrate / 1000) + " Mbps", kind: "slider", fraction: Math.min(1, p.bitrate / 150000) },
                { id: "codec", label: "Video codec", value: codecs[idx(codecs, function (c) { return c[0] === p.codec })][1], kind: "choice" },
                { id: "hdr", label: "HDR", value: p.hdr ? "On" : "Off", kind: "toggle" },
                { id: "audio", label: "Sound", value: audios[idx(audios, function (a) { return a[0] === p.audio })][1], kind: "choice" },
                { id: "mouse", label: "Mouse", value: mice[idx(mice, function (m) { return m[0] === p.mouse })][1], kind: "choice" },
                { id: "pc", label: "Play on", value: pcName, kind: "choice" }
            ].concat(p.id === "default" ? [] : [{ id: "delete", label: "Delete this profile", kind: "action", danger: true }])
        }
        if (s === "controllers") return [
            { id: "padIcons", label: "Button icons", value: padIcons[idx(padIcons, function (x) { return x[0] === (k.padIcons || "auto") })][1], kind: "choice" },
            { id: "swap", label: "Swap A and B", value: k.swapButtons ? "On" : "Off", kind: "toggle", note: "For Nintendo-style confirm on the right" },
            { id: "info", label: "Connected", value: PlayInput.gamepads > 0 ? PlayInput.padName : "No controller", kind: "info" }
        ]
        if (s === "meta") return [
            { id: "igdbClientId", label: "IGDB client ID", value: k.igdbClientId || "Not set", kind: "text" },
            { id: "igdbSecret", label: "IGDB client secret", value: k.igdbSecret ? "••••••••" : "Not set", kind: "text" },
            { id: "steamGridDbKey", label: "SteamGridDB API key", value: k.steamGridDbKey ? "••••••••" : "Not set", kind: "text" },
            { id: "refresh", label: "Look up every game again", kind: "action" }
        ]
        if (s === "hidden") return Play.hiddenGames.length
            ? Play.hiddenGames.map(function (g) { return { id: "unhide", key: g.key, label: g.name, value: "Show again", kind: "action" } })
            : [{ id: "none", label: "No hidden games", kind: "info", value: "" }]
        if (s === "about") return [
            { id: "v", label: "Dot Play", value: Play.version, kind: "info" },
            { id: "m", label: "Based on", value: "Moonlight, GPL-3.0", kind: "info" },
            { id: "d", label: "Game info", value: "IGDB.com", kind: "info" },
            { id: "a", label: "Art", value: "SteamGridDB", kind: "info" }
        ]
        return []
    }

    function save(changes) {
        var p = {}
        for (var key in profile) p[key] = profile[key]
        for (var c in changes) p[c] = changes[c]
        Play.saveProfile(p)
    }
    function step(list, current, dir) { return list[(current + dir + list.length) % list.length] }

    function change(r, dir) {
        var p = profile, k = {}
        if (r.id === "res") {
            var res = step(resolutions, idx(resolutions, function (x) { return x[0] === p.width && x[1] === p.height }), dir)
            save({ width: res[0], height: res[1] })
        }
        else if (r.id === "fps") save({ fps: step(rates, rates.indexOf(p.fps), dir) })
        else if (r.id === "bitrate") save({ bitrate: Math.max(5000, Math.min(150000, p.bitrate + dir * 5000)) })
        else if (r.id === "codec") save({ codec: step(codecs, idx(codecs, function (c) { return c[0] === p.codec }), dir)[0] })
        else if (r.id === "hdr") save({ hdr: !p.hdr })
        else if (r.id === "audio") save({ audio: step(audios, idx(audios, function (a) { return a[0] === p.audio }), dir)[0] })
        else if (r.id === "mouse") save({ mouse: step(mice, idx(mice, function (m) { return m[0] === p.mouse }), dir)[0] })
        else if (r.id === "pc") {
            var ids = [""].concat(Play.pcs.map(function (x) { return x.uuid }))
            save({ pc: step(ids, ids.indexOf(p.pc), dir) })
        }
        else if (r.id === "padIcons") {
            k.padIcons = step(padIcons, idx(padIcons, function (x) { return x[0] === (Play.keys.padIcons || "auto") }), dir)[0]
            Play.saveKeys(k)
        }
        else if (r.id === "swap") { k.swapButtons = !Play.keys.swapButtons; Play.saveKeys(k) }
    }

    function activate(r) {
        if (r.kind === "text" && !r.locked) {
            editing = r.id
            draft = r.id === "name" ? profile.name : (Play.keys[r.id] || "")
            if (pad) osk.forceActiveFocus()
        }
        else if (r.kind === "choice" || r.kind === "toggle") change(r, 1)
        else if (r.id === "delete") { Play.deleteProfile(profile.id); profileIndex = 0; zone = "profiles"; row = 0 }
        else if (r.id === "refresh") Play.refreshMeta()
        else if (r.id === "unhide") Play.setHidden(r.key, false)
    }

    function finishEditing(keep) {
        if (keep) {
            if (editing === "name") save({ name: draft.trim() || profile.name })
            else { var k = {}; k[editing] = draft.trim(); Play.saveKeys(k) }
        }
        editing = ""
        page.forceActiveFocus()
    }

    Keys.onPressed: function (event) {
        if (editing !== "") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) finishEditing(true)
            else if (event.key === Qt.Key_Escape) finishEditing(false)
            else if (event.key === Qt.Key_Backspace) draft = draft.slice(0, -1)
            else if (event.text.length === 1 && event.text >= " ") draft += event.text
            else if ((event.key === Qt.Key_V) && (event.modifiers & Qt.ControlModifier)) draft += Play.clipboard()
            event.accepted = true
            return
        }
        var sectionId = sections[section].id
        if (event.key === Qt.Key_Up) {
            if (zone === "nav") { if (section > 0) { section--; row = 0 } else upFromTop() }
            else if (zone === "profiles") { if (profileIndex > 0) profileIndex-- }
            else if (row > 0) row--
        }
        else if (event.key === Qt.Key_Down) {
            if (zone === "nav") { if (section < sections.length - 1) { section++; row = 0 } }
            else if (zone === "profiles") { if (profileIndex < Play.profiles.length) profileIndex++ }
            else if (row < rows.length - 1) row++
        }
        else if (event.key === Qt.Key_Right) {
            if (zone === "nav") zone = sectionId === "profiles" ? "profiles" : "rows"
            else if (zone === "profiles") { if (profileIndex < Play.profiles.length) { zone = "rows"; row = 0 } }
            else if (rows[row] && (rows[row].kind === "choice" || rows[row].kind === "slider" || rows[row].kind === "toggle")) change(rows[row], 1)
        }
        else if (event.key === Qt.Key_Left) {
            if (zone === "rows" && rows[row] && (rows[row].kind === "choice" || rows[row].kind === "slider" || rows[row].kind === "toggle")) change(rows[row], -1)
            else if (zone === "rows") zone = sectionId === "profiles" ? "profiles" : "nav"
            else if (zone === "profiles") zone = "nav"
        }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (zone === "nav") zone = sectionId === "profiles" ? "profiles" : "rows"
            else if (zone === "profiles") {
                if (profileIndex === Play.profiles.length) {   // + New profile
                    Play.saveProfile({ name: "Profile " + (Play.profiles.length + 1) })
                }
                zone = "rows"; row = 0
            }
            else if (rows[row]) activate(rows[row])
        }
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            if (zone === "rows") zone = sectionId === "profiles" ? "profiles" : "nav"
            else if (zone === "profiles") zone = "nav"
            else return   // let the shell take it (back to Home)
        }
        else return
        event.accepted = true
    }

    // sections
    Column {
        x: 44; y: 104
        width: 230
        spacing: 4
        Repeater {
            model: page.sections
            Rectangle {
                width: 230; height: 44; radius: 12
                readonly property bool chosen: index === page.section
                color: chosen ? "#1c1c1e" : (navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                FocusRing { on: page.activeFocus && page.zone === "nav" && parent.chosen && page.editing === ""; parentRadius: 12 }
                Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: parent.chosen ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7); font.pixelSize: 15; font.weight: parent.chosen ? Font.DemiBold : Font.Normal }
                MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { page.section = index; page.row = 0; page.zone = "nav"; page.forceActiveFocus() } }
            }
        }
    }
    Text {
        x: 58; y: 600
        width: 210
        text: "Gaming PCs and pairing are in Dot's own Settings › Games."
        color: Qt.rgba(1, 1, 1, 0.45)
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        lineHeight: 1.3
    }

    // profiles list
    Column {
        visible: page.sections[page.section].id === "profiles"
        x: 300; y: 104
        width: 270
        spacing: 8
        Text { text: "Profiles"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 }
        Repeater {
            model: Play.profiles.concat([{ id: "__new", name: "+ New profile" }])
            Rectangle {
                readonly property bool chosen: index === page.profileIndex
                readonly property bool isNew: modelData.id === "__new"
                width: 270
                height: isNew ? 48 : 64
                radius: 14
                color: chosen && page.zone !== "nav" ? "#ffffff" : (isNew ? "transparent" : "#1c1c1e")
                border.width: isNew ? 1.5 : 0
                border.color: "#3a3a3c"
                FocusRing { on: page.activeFocus && page.zone === "profiles" && parent.chosen; parentRadius: 14 }
                Column {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: modelData.name; color: parent.parent.chosen && page.zone !== "nav" ? "#000000" : "#ffffff"; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text {
                        visible: !parent.parent.isNew
                        text: parent.parent.isNew ? "" : (modelData.height ? modelData.height + "p" : "") + " · " + modelData.fps + " fps · " + modelData.games + (modelData.games === 1 ? " game" : " games")
                        color: parent.parent.chosen && page.zone !== "nav" ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 12
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.isNew) Play.saveProfile({ name: "Profile " + (Play.profiles.length + 1) })
                        page.profileIndex = index; page.zone = "rows"; page.row = 0; page.forceActiveFocus()
                    }
                }
            }
        }
    }

    // rows
    Rectangle {
        readonly property bool wide: page.sections[page.section].id !== "profiles"
        x: wide ? 300 : 594
        y: 104
        width: 1280 - 64 - x
        height: rowsColumn.implicitHeight + 44
        radius: 24
        color: "#1c1c1e"

        Column {
            id: rowsColumn
            x: 22; y: 22
            width: parent.width - 44
            spacing: 2

            Text {
                visible: page.sections[page.section].id === "profiles"
                text: page.profile ? page.profile.name : ""
                color: "#ffffff"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                bottomPadding: 10
            }
            Text {
                visible: page.sections[page.section].id === "meta"
                width: parent.width
                text: "Game details come from IGDB: make a free app at dev.twitch.tv (Applications › Register) and copy its client ID and secret. Art comes from SteamGridDB: steamgriddb.com › Preferences › API. Easiest with a keyboard."
                color: Qt.rgba(1, 1, 1, 0.6)
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                lineHeight: 1.3
                bottomPadding: 12
            }

            Repeater {
                model: page.rows
                Rectangle {
                    readonly property bool focused: page.activeFocus && page.zone === "rows" && index === page.row
                    readonly property bool isEditing: page.editing === modelData.id && page.editing !== ""
                    width: rowsColumn.width
                    height: 50
                    radius: 12
                    color: focused ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    FocusRing { on: parent.focused && page.pad; parentRadius: 12 }

                    Rectangle {
                        visible: index > 0 && !parent.focused
                        width: parent.width - 8; x: 4; height: 1; color: "#2c2c2e"
                    }
                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: modelData.danger ? "#ff6b8e" : "#ffffff"
                        font.pixelSize: 15
                    }
                    Text {
                        visible: !!modelData.note
                        x: 8 + 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.note || ""
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 12
                    }

                    // value: text / choice with arrows / slider / toggle
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle {
                            visible: modelData.kind === "slider"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 200; height: 6; radius: 3; color: "#3a3a3c"
                            Rectangle { width: parent.width * (modelData.fraction || 0); height: 6; radius: 3; color: "#ffffff" }
                        }
                        Text {
                            visible: (modelData.kind === "choice" || modelData.kind === "slider") && parent.parent.focused
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 18
                        }
                        Rectangle {
                            visible: modelData.value !== undefined && modelData.value !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            height: 32
                            width: valueText.implicitWidth + 24
                            radius: 10
                            color: parent.parent.isEditing ? "#ffffff" : (modelData.kind === "info" ? "transparent" : "#2c2c2e")
                            Text {
                                id: valueText
                                anchors.centerIn: parent
                                text: parent.parent.parent.isEditing ? (page.draft + "▏") : (modelData.value || "")
                                color: parent.parent.parent.isEditing ? "#000000" : (modelData.kind === "info" ? Qt.rgba(1, 1, 1, 0.6) : "#ffffff")
                                font.pixelSize: 14
                            }
                        }
                        Text {
                            visible: (modelData.kind === "choice" || modelData.kind === "slider") && parent.parent.focused
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 18
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: modelData.kind === "info" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onEntered: if (!page.pad) { page.zone = "rows"; page.row = index }
                        onClicked: function (mouse) {
                            page.forceActiveFocus()
                            page.zone = "rows"; page.row = index
                            if (modelData.kind === "choice" || modelData.kind === "slider") page.change(modelData, mouse.x < width / 2 ? -1 : 1)
                            else page.activate(modelData)
                        }
                    }
                }
            }
        }
    }

    Osk {
        id: osk
        visible: page.editing !== "" && page.pad
        anchors.horizontalCenter: parent.horizontalCenter
        y: 720 - height - 80
        z: 5
        onTyped: function (ch) { page.draft += ch }
        onErase: page.draft = page.draft.slice(0, -1)
        onClear: page.draft = ""
        onLeaveUp: page.finishEditing(true)
        onLeaveDown: page.finishEditing(true)
        Keys.onEscapePressed: page.finishEditing(false)
        Keys.onBackPressed: page.finishEditing(false)
    }

    HintBar {
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        hints: page.editing !== "" ? [
            { b: "a", label: "Type", key: "Enter" },
            { b: "x", label: "Delete", key: "Backspace" },
            { b: "b", label: "Cancel", key: "Esc" }
        ] : [
            { b: "a", label: "Choose", key: "Enter" },
            { b: "lr", label: "Change", key: "← →" },
            { b: "b", label: "Back", key: "Esc" }
        ]
    }
}
