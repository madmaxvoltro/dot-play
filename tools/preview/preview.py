"""Preview Dot Play's screens on a PC, without Moonlight or a Raspberry Pi.

Runs app/gui/play/PlayWindow.qml with PySide6 and a stand-in for the C++ backend (`Play`, `PlayInput`)
holding demo games, so the screens can be looked at and screenshotted while designing them.

    pip install PySide6-Essentials==6.12.0
    python tools/preview/preview.py                         # a window; keys switch modes (see below)
    python tools/preview/preview.py --shots out/            # one PNG per screen, controller and keyboard

In the window: F1 controller mode, F2 keyboard mode, F3 cycles Xbox / PlayStation / Switch buttons;
arrows, Enter, Esc work like the controller's D-pad, A and B; PageUp/PageDown are LB/RB.
"""

import argparse
import hashlib
import os
import sys
import time

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Signal, Slot, Qt, QEvent, qInstallMessageHandler
from PySide6.QtGui import QFontDatabase, QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
QML = os.path.join(ROOT, "app", "gui", "play", "PlayWindow.qml")
FONT = os.path.join(ROOT, "app", "res", "fonts", "Geist.ttf")

DEMO = [
    ("Elden Ring", 2022, ["Action RPG", "Open world", "Souls-like"], 3660, 2, "#2b2118",
     "Rise, Tarnished, and be guided by grace to brandish the power of the Elden Ring."),
    ("Forza Horizon 5", 2021, ["Racing", "Open world", "Online co-op"], 1320, 1, "#1a2433",
     "Explore the vibrant open world landscapes of Mexico in the world's greatest cars."),
    ("Baldur's Gate 3", 2023, ["Role-playing", "Turn-based", "Online co-op"], 6240, 5, "#23182c",
     "Gather your party and return to the Forgotten Realms."),
    ("Hades II", 2025, ["Roguelike", "Action", "Short sessions"], 540, 9, "#2c1414",
     "Battle beyond the Underworld using dark sorcery to take on the Titan of Time."),
    ("Rocket League", 2015, ["Sports", "Online co-op", "Short sessions"], 8400, 3, "#14262a",
     "Soccer meets driving in a high-powered hybrid of arcade football and vehicular mayhem."),
    ("Stardew Valley", 2016, ["Simulation", "Couch co-op", "Relaxing"], 0, None, "#1f2a1a",
     "You've inherited your grandfather's old farm plot."),
    ("It Takes Two", 2021, ["Adventure", "Couch co-op", "Platformer"], 720, 40, "#26162a",
     "Embark on the craziest journey of your life in a genre-bending platform adventure."),
    ("Cuphead", 2017, ["Platformer", "Couch co-op", "Hard"], 260, 80, "#2c2010",
     "A classic run and gun action game heavily focused on boss battles."),
    ("DOOM Eternal", 2020, ["Shooter", "Fast", "Action"], 900, 12, "#3a1610",
     "Hell's armies have invaded Earth. Become the Slayer."),
    ("Cyberpunk 2077", 2020, ["Action RPG", "Open world", "Shooter"], 2040, 20, "#2a2a12",
     "An open-world, action-adventure RPG set in the megalopolis of Night City."),
    ("Halo Infinite", 2021, ["Shooter", "Online co-op", "Action"], 300, 60, "#122a24",
     "When all hope is lost, Master Chief is ready to confront the most ruthless foe."),
    ("Celeste", 2018, ["Platformer", "Hard", "Short sessions"], 0, None, "#2a1630",
     "Help Madeline survive her inner demons on her journey to the top of Celeste Mountain."),
]


def game_map(i, name, year, tags, minutes, days, color, summary):
    last = time.time() - days * 86400 if days is not None else 0
    hours = minutes // 60
    played = f"{hours} h" if hours else (f"{minutes} min" if minutes else "Never played")
    when = "" if days is None else ("yesterday" if days == 1 else f"{days} days ago")
    blurb = (f"{played} played, last {when}. " if minutes else "Not played yet. ") + summary
    return {
        "key": hashlib.md5(name.encode()).hexdigest()[:12], "name": name, "year": str(year), "tags": tags,
        "summary": summary, "blurb": blurb, "developer": "", "color": color,
        "cover": "", "banner": "", "logo": "", "icon": "", "screenshot": "", "screenshots": [],
        "playMinutes": minutes, "playedText": played, "lastPlayed": last, "lastPlayedText": when or "Never",
        "progress": 0.72 if i == 0 else 0, "pc": "Living room PC" if i == 3 else "Gaming PC",
        "pcs": ["Gaming PC"], "online": True, "running": i == 0, "profileId": "default",
        "profileName": "Default", "favourite": i in (1, 4), "hidden": False, "hasMeta": True,
    }


class Play(QObject):
    changed = Signal()
    identifyResults = Signal("QVariantList")
    artResults = Signal(str, "QVariantList")
    launchRequested = Signal(str)

    def __init__(self, empty=False):
        super().__init__()
        self._games = [] if empty else [game_map(i, *g) for i, g in enumerate(DEMO)]

    def _get_games(self):
        return self._games

    def _rows(self):
        g = self._games
        if not g:
            return []
        played = sorted([x for x in g if x["playMinutes"]], key=lambda x: -x["lastPlayed"])
        return [
            {"title": "Continue playing", "games": played[:6]},
            {"title": "Because you play role-playing games", "games": [g[2], g[9], g[0], g[3]]},
            {"title": "Couch co-op", "games": [x for x in g if "Couch co-op" in x["tags"]]},
            {"title": "Not played yet", "games": [x for x in g if not x["playMinutes"]]},
            {"title": "Short sessions", "games": [x for x in g if "Short sessions" in x["tags"]]},
        ]

    def _tags(self):
        seen = []
        for x in self._games:
            for t in x["tags"]:
                if t not in seen:
                    seen.append(t)
        return seen

    games = Property("QVariantList", _get_games, notify=changed)
    rows = Property("QVariantList", _rows, notify=changed)
    tags = Property("QStringList", _tags, notify=changed)
    preview = Property(bool, lambda self: True, constant=True)
    anyOnline = Property(bool, lambda self: True, notify=changed)
    pcSummary = Property(str, lambda self: "Gaming PC", notify=changed)
    emptyTitle = Property(str, lambda self: "No gaming PC paired yet", notify=changed)
    emptyText = Property(str, lambda self: "On your Dot: Settings › Games, choose how this PC plays games and press Pair. Its games show up here.", notify=changed)
    hasIgdb = Property(bool, lambda self: True, notify=changed)
    hasSteamGridDb = Property(bool, lambda self: True, notify=changed)
    version = Property(str, lambda self: "preview", constant=True)

    def _profiles(self):
        return [
            {"id": "default", "name": "Default", "width": 2560, "height": 1440, "fps": 60, "bitrate": 40000,
             "codec": "auto", "hdr": False, "audio": "stereo", "mouse": "game", "pc": "", "games": 10},
            {"id": "fast", "name": "Fast games", "width": 1920, "height": 1080, "fps": 120, "bitrate": 40000,
             "codec": "hevc", "hdr": False, "audio": "stereo", "mouse": "game", "pc": "", "games": 2},
        ]

    profiles = Property("QVariantList", _profiles, notify=changed)
    pcs = Property("QVariantList", lambda self: [{"name": "Gaming PC", "uuid": "a", "online": True}, {"name": "Living room PC", "uuid": "b", "online": False}], notify=changed)
    hiddenGames = Property("QVariantList", lambda self: [], notify=changed)
    keys = Property("QVariantMap", lambda self: {"igdbClientId": "abc123", "igdbSecret": "", "steamGridDbKey": "", "padIcons": "auto", "swapButtons": False}, notify=changed)

    @Slot(str, "QStringList", result="QVariantList")
    def search(self, text, tags):
        t = text.lower()
        return [x for x in self._games if t in x["name"].lower() and all(tag in x["tags"] for tag in tags)]

    @Slot(str, result="QVariantMap")
    def game(self, key):
        return next((x for x in self._games if x["key"] == key), {})

    @Slot(str)
    def identifySearch(self, text):
        base = [("DOOM Eternal", 2020, "id Software · Shooter"),
                ("DOOM Eternal: The Ancient Gods – Part One", 2020, "Expansion"),
                ("DOOM", 2016, "id Software · Shooter"), ("DOOM", 1993, "id Software · Shooter")]
        res = [{"id": i + 1, "name": n, "year": str(y), "detail": d, "cover": ""} for i, (n, y, d) in enumerate(base)]
        QTimer.singleShot(300, lambda: self.identifyResults.emit(res))

    @Slot(str, str)
    def artSearch(self, key, kind):
        res = [{"url": "", "thumb": "", "author": "artist", "inUse": i == 0, "color": c}
               for i, c in enumerate(["#2c1414", "#3a1a10", "#24101a", "#33231a", "#1f1424", "#2a1a12", "#1c1c1e", "#1c1c1e"])]
        QTimer.singleShot(300, lambda: self.artResults.emit(kind, res))

    @Slot(str, int)
    def identify(self, key, igdb_id):
        print("identify", key, igdb_id)

    @Slot(str)
    def identifyNone(self, key):
        print("no match", key)

    @Slot(str, str, str)
    def setArt(self, key, kind, url):
        print("art", key, kind, url)

    @Slot(str, str)
    def resetArt(self, key, kind):
        print("reset art", key, kind)

    @Slot(str, bool)
    def setHidden(self, key, hidden):
        print("hidden", key, hidden)

    @Slot(str, bool)
    def setFavourite(self, key, fav):
        print("favourite", key, fav)

    @Slot(str, str)
    def setGameProfile(self, key, pid):
        print("profile", key, pid)

    @Slot(str, str)
    def setGamePc(self, key, uuid):
        print("pc", key, uuid)

    @Slot("QVariantMap", result=str)
    def saveProfile(self, p):
        print("save profile", dict(p))
        return p.get("id") or "new"

    @Slot(str)
    def deleteProfile(self, pid):
        print("delete profile", pid)

    @Slot("QVariantMap")
    def saveKeys(self, keys):
        print("keys", dict(keys))

    @Slot()
    def refreshMeta(self):
        print("refresh")

    @Slot(str, result=QObject)
    def createSession(self, key):
        return None

    @Slot(str, result="QVariantMap")
    def streamInfo(self, key):
        return {"summary": "1440p · 60 fps · HEVC · Default profile"}

    @Slot(str)
    def streamStarted(self, key):
        pass

    @Slot(str)
    def streamEnded(self, key):
        pass

    @Slot(result=str)
    def clipboard(self):
        return ""

    @Slot()
    def backToDot(self):
        print("back to Dot")


class PlayInput(QObject):
    changed = Signal()

    def __init__(self, mode, pad):
        super().__init__()
        self._mode, self._pad = mode, pad

    def set_mode(self, mode):
        self._mode = mode
        self.changed.emit()

    def set_pad(self, pad):
        self._pad = pad
        self.changed.emit()

    mode = Property(str, lambda self: self._mode, notify=changed)
    padType = Property(str, lambda self: self._pad, notify=changed)
    padName = Property(str, lambda self: {"xbox": "Xbox controller", "playstation": "DualSense", "switch": "Pro Controller"}[self._pad], notify=changed)
    gamepads = Property(int, lambda self: 1, notify=changed)

    @Slot()
    def enable(self):
        pass

    @Slot()
    def disable(self):
        pass

    @Slot(bool)
    def notifyWindowFocus(self, focus):
        pass


class Keys(QObject):
    """F1/F2/F3 switch modes; PageUp/PageDown act as LB/RB."""

    def __init__(self, inp):
        super().__init__()
        self.inp = inp

    def eventFilter(self, obj, ev):
        if ev.type() == QEvent.KeyPress and not getattr(ev, "_dot", False):
            k = ev.key()
            if k == Qt.Key_F1:
                self.inp.set_mode("pad"); return True
            if k == Qt.Key_F2:
                self.inp.set_mode("keys"); return True
            if k == Qt.Key_F3:
                order = ["xbox", "playstation", "switch"]
                self.inp.set_pad(order[(order.index(self.inp._pad) + 1) % 3]); return True
            if k in (Qt.Key_PageUp, Qt.Key_PageDown):
                QGuiApplication.sendEvent(obj, QKeyEvent(QEvent.KeyPress, Qt.Key_F13 if k == Qt.Key_PageUp else Qt.Key_F14, Qt.NoModifier))
                return True
        return False


SCREENS = ["home", "library", "search", "game", "identify", "art", "launch", "settings"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", help="write a PNG of every screen to this folder, then quit")
    ap.add_argument("--screens", default=",".join(SCREENS))
    ap.add_argument("--mode", default="pad")
    ap.add_argument("--pad", default="xbox")
    ap.add_argument("--empty", action="store_true")
    args = ap.parse_args()

    qInstallMessageHandler(lambda mode, ctx, msg: print(msg, file=sys.stderr, flush=True))
    app = QGuiApplication(sys.argv)
    QFontDatabase.addApplicationFont(FONT)
    play = Play(empty=args.empty)
    inp = PlayInput(args.mode, args.pad)
    engine = QQmlApplicationEngine()
    import PySide6
    engine.addImportPath(os.path.join(os.path.dirname(PySide6.__file__), "qml"))
    engine.rootContext().setContextProperty("Play", play)
    engine.rootContext().setContextProperty("PlayInput", inp)
    engine.rootContext().setContextProperty("StreamingPreferences", None)
    engine.load(QUrl.fromLocalFile(QML))
    if not engine.rootObjects():
        sys.exit(1)
    win = engine.rootObjects()[0]
    keys = Keys(inp)
    app.installEventFilter(keys)

    if args.shots:
        os.makedirs(args.shots, exist_ok=True)
        jobs = [(s, m) for m in ("pad", "keys") for s in args.screens.split(",")]

        def step(i=0):
            if i >= len(jobs):
                app.quit()
                return
            screen, mode = jobs[i]
            inp.set_mode(mode)
            win.showScreen(screen)
            QTimer.singleShot(900, lambda: (win.grabWindow().save(os.path.join(args.shots, f"{screen}-{mode}.png")),
                                            step(i + 1)))

        QTimer.singleShot(600, step)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
