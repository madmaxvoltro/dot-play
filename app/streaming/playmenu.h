#pragma once

#include <QByteArray>
#include <QMap>
#include <QString>

#include "SDL_compat.h"
#include <SDL_ttf.h>

class Session;

// Dot Play's in-game menu, drawn over the stream: Resume, volume, performance stats, mouse mode,
// Disconnect (the game keeps running), Stop the game, Back to work.
//
// Opened with Guide on a controller, L1+R1+Select+Start, or Ctrl+Alt+Shift+Q (Moonlight's quit
// shortcuts, which open this menu instead). While it's open, no input reaches the game.
//
// It's drawn as one full-window picture handed to the stream's overlay (in place of the stats text),
// so every video renderer shows it without changes of its own.
class PlayMenu
{
public:
    enum ExitAction {
        ExitNone,
        ExitDisconnect,   // leave the game running on the PC
        ExitStopGame,     // quit the game on the PC too
        ExitBackToWork,   // and leave Dot Play: Dot goes back to Remote Desktop
    };

    explicit PlayMenu(Session* session);
    ~PlayMenu();

    bool isOpen() const { return m_Open; }
    void open();
    void close();

    // Called with every SDL event while streaming; true when the menu used it (so the game doesn't get it)
    bool handleEvent(const SDL_Event& event);

    // The menu as a picture the size of the window (called by the overlay manager)
    SDL_Surface* render();

    // What the menu asked for when the stream ended (read once, by Dot Play's backend)
    static ExitAction takeExitAction();

private:
    enum Item { Resume, Volume, Stats, Mouse, Disconnect, StopGame, BackToWork, ItemCount };

    void move(int delta);
    void adjust(int delta);
    void activate();
    void quitStream(ExitAction action);
    void redraw();
    int readVolume();
    void setVolume(int volume);

    TTF_Font* font(int px, bool bold);

    Session* m_Session;
    bool m_Open = false;
    int m_Index = 0;
    int m_Volume = -1;
    bool m_StatsAfter = false;    // the stats overlay, once the menu closes
    Uint32 m_StartedAt;
    short m_LastStickY = 0;
    SDL_mutex* m_Lock;
    QByteArray m_Regular, m_SemiBold;
    QMap<int, TTF_Font*> m_Fonts;   // by size * 2 + bold

    static ExitAction s_ExitAction;
};
