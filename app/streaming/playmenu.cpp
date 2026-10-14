#include "playmenu.h"

#include "session.h"
#include "streaming/input/input.h"

#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QTime>
#include <cmath>

PlayMenu::ExitAction PlayMenu::s_ExitAction = PlayMenu::ExitNone;

static const SDL_Color WHITE = {255, 255, 255, 255};
static const SDL_Color BLACK = {0, 0, 0, 255};
static const SDL_Color MUTED = {170, 170, 175, 255};
static const SDL_Color PINK = {255, 107, 142, 255};

PlayMenu::PlayMenu(Session* session)
    : m_Session(session),
      m_StartedAt(SDL_GetTicks()),
      m_Lock(SDL_CreateMutex())
{
    QFile regular(":/res/fonts/Geist-Regular.ttf"), semibold(":/res/fonts/Geist-SemiBold.ttf");
    if (regular.open(QIODevice::ReadOnly)) m_Regular = regular.readAll();
    if (semibold.open(QIODevice::ReadOnly)) m_SemiBold = semibold.readAll();
}

PlayMenu::~PlayMenu()
{
    for (TTF_Font* f : std::as_const(m_Fonts)) {
        TTF_CloseFont(f);
    }
    SDL_DestroyMutex(m_Lock);
}

PlayMenu::ExitAction PlayMenu::takeExitAction()
{
    ExitAction a = s_ExitAction;
    s_ExitAction = ExitNone;
    return a;
}

TTF_Font* PlayMenu::font(int px, bool bold)
{
    int key = px * 2 + (bold ? 1 : 0);
    if (!m_Fonts.contains(key)) {
        const QByteArray& data = bold ? m_SemiBold : m_Regular;
        m_Fonts[key] = data.isEmpty() ? nullptr : TTF_OpenFontRW(SDL_RWFromConstMem(data.constData(), data.size()), 1, px);
    }
    return m_Fonts.value(key);
}

// --- opening and closing ------------------------------------------------------------------------------

void PlayMenu::open()
{
    if (m_Open) {
        return;
    }
    // nothing stays held down in the game while the menu is up
    m_Session->m_InputHandler->raiseAllKeys();
    m_Session->m_InputHandler->releaseGamepads();

    m_StatsAfter = m_Session->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug);
    m_Volume = readVolume();
    m_Index = Resume;
    m_Open = true;
    m_Session->getOverlayManager().setMenu([this] { return render(); });
}

void PlayMenu::close()
{
    if (!m_Open) {
        return;
    }
    m_Open = false;
    m_Session->getOverlayManager().setMenu(nullptr, m_StatsAfter);
}

void PlayMenu::redraw()
{
    m_Session->getOverlayManager().refreshMenu();
}

void PlayMenu::quitStream(ExitAction action)
{
    s_ExitAction = action;
    close();
    SDL_Event quit;
    quit.type = SDL_QUIT;
    quit.quit.timestamp = SDL_GetTicks();
    SDL_PushEvent(&quit);
}

// --- input --------------------------------------------------------------------------------------------

void PlayMenu::move(int delta)
{
    m_Index = (m_Index + delta + ItemCount) % ItemCount;
    redraw();
}

void PlayMenu::adjust(int delta)
{
    if (m_Index == Volume) {
        setVolume(std::max(0, std::min(100, m_Volume + delta * 5)));
    }
    else if (m_Index == Stats || m_Index == Mouse) {
        activate();
        return;
    }
    redraw();
}

void PlayMenu::activate()
{
    switch (m_Index) {
    case Resume: close(); return;
    case Volume: setVolume(m_Volume > 0 ? 0 : 50); break;
    case Stats: m_StatsAfter = !m_StatsAfter; break;
    case Mouse: m_Session->m_InputHandler->toggleMouseMode(); break;
    case Disconnect: quitStream(ExitDisconnect); return;
    case StopGame: quitStream(ExitStopGame); return;
    case BackToWork: quitStream(ExitBackToWork); return;
    default: break;
    }
    redraw();
}

bool PlayMenu::handleEvent(const SDL_Event& event)
{
    if (!m_Open) {
        return false;
    }
    switch (event.type) {
    case SDL_KEYDOWN:
        switch (event.key.keysym.scancode) {
        case SDL_SCANCODE_UP: move(-1); break;
        case SDL_SCANCODE_DOWN: move(1); break;
        case SDL_SCANCODE_LEFT: adjust(-1); break;
        case SDL_SCANCODE_RIGHT: adjust(1); break;
        case SDL_SCANCODE_RETURN:
        case SDL_SCANCODE_KP_ENTER:
        case SDL_SCANCODE_SPACE: activate(); break;
        case SDL_SCANCODE_ESCAPE:
        case SDL_SCANCODE_BACKSPACE:
        case SDL_SCANCODE_Q: close(); break;
        default: break;
        }
        return true;
    case SDL_TEXTINPUT:
    case SDL_MOUSEMOTION:
    case SDL_MOUSEWHEEL:
    case SDL_MOUSEBUTTONDOWN:
    case SDL_FINGERDOWN:
    case SDL_FINGERMOTION:
        return true;
    case SDL_CONTROLLERBUTTONDOWN:
        switch (event.cbutton.button) {
        case SDL_CONTROLLER_BUTTON_DPAD_UP: move(-1); break;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN: move(1); break;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT: adjust(-1); break;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: adjust(1); break;
        case SDL_CONTROLLER_BUTTON_A: activate(); break;
        case SDL_CONTROLLER_BUTTON_B:
        case SDL_CONTROLLER_BUTTON_GUIDE:
        case SDL_CONTROLLER_BUTTON_START: close(); break;
        default: break;
        }
        return true;
    case SDL_CONTROLLERBUTTONUP:
        // releases go through, so the game's idea of which buttons are held stays right
        return event.cbutton.button == SDL_CONTROLLER_BUTTON_GUIDE;
    case SDL_CONTROLLERAXISMOTION:
        if (event.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY) {
            short y = event.caxis.value;
            if (y < -24000 && m_LastStickY >= -24000) move(-1);
            else if (y > 24000 && m_LastStickY <= 24000) move(1);
            m_LastStickY = y;
        }
        return true;
    default:
        return false;
    }
}

// --- volume (the Dot's own sound output, like Dot's volume control) -------------------------------------

int PlayMenu::readVolume()
{
    QProcess p;
    p.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
    if (!p.waitForFinished(1500)) {
        return -1;
    }
    QRegularExpressionMatch m = QRegularExpression("(\\d+)%").match(QString::fromUtf8(p.readAllStandardOutput()));
    return m.hasMatch() ? m.captured(1).toInt() : -1;
}

void PlayMenu::setVolume(int volume)
{
    if (m_Volume < 0) {
        return;  // no PulseAudio / PipeWire to talk to
    }
    m_Volume = volume;
    QProcess::startDetached("pactl", {"set-sink-volume", "@DEFAULT_SINK@", QString("%1%").arg(volume)});
}

// --- drawing ------------------------------------------------------------------------------------------

static Uint32 rgba(SDL_Surface* s, int r, int g, int b, int a)
{
    return SDL_MapRGBA(s->format, Uint8(r), Uint8(g), Uint8(b), Uint8(a));
}

// SDL has no rounded rectangles: fill row by row, each row inset at the corners
static void fillRound(SDL_Surface* s, int x, int y, int w, int h, int r, Uint32 color)
{
    r = std::min(r, std::min(w, h) / 2);
    for (int row = 0; row < h; row++) {
        int inset = 0;
        int dy = row < r ? r - row : (row >= h - r ? row - (h - r) + 1 : 0);
        if (dy > 0) {
            inset = r - int(std::sqrt(double(r * r - (dy - 0.5) * (dy - 0.5))));
        }
        SDL_Rect line = {x + inset, y + row, w - 2 * inset, 1};
        SDL_FillRect(s, &line, color);
    }
}

static int drawText(SDL_Surface* s, TTF_Font* f, const QString& text, int x, int y, SDL_Color color, int maxWidth = 0, bool right = false)
{
    if (f == nullptr || text.isEmpty()) {
        return 0;
    }
    SDL_Surface* t = TTF_RenderUTF8_Blended(f, text.toUtf8().constData(), color);
    if (t == nullptr) {
        return 0;
    }
    SDL_SetSurfaceBlendMode(t, SDL_BLENDMODE_BLEND);
    int w = maxWidth > 0 ? std::min(t->w, maxWidth) : t->w;
    SDL_Rect src = {0, 0, w, t->h};
    SDL_Rect dst = {right ? x - w : x, y, w, t->h};
    SDL_BlitSurface(t, &src, s, &dst);
    SDL_FreeSurface(t);
    return w;
}

SDL_Surface* PlayMenu::render()
{
    SDL_LockMutex(m_Lock);

    int W = 0, H = 0;
    SDL_GetWindowSizeInPixels(m_Session->m_Window, &W, &H);
    W &= ~1;
    H &= ~1;
    if (W <= 0 || H <= 0) {
        SDL_UnlockMutex(m_Lock);
        return nullptr;
    }
    double u = H / 720.0;  // the design's 720p units
    auto px = [u](double v) { return int(std::lround(v * u)); };

    SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, W, H, 32, SDL_PIXELFORMAT_ARGB8888);
    if (s == nullptr) {
        SDL_UnlockMutex(m_Lock);
        return nullptr;
    }
    SDL_FillRect(s, nullptr, rgba(s, 0, 0, 0, 140));

    // the panel
    int x0 = px(48), y0 = px(48), pw = px(380), ph = H - px(96);
    fillRound(s, x0, y0, pw, ph, px(28), rgba(s, 28, 28, 30, 246));
    int pad = px(22);
    int left = x0 + pad, width = pw - 2 * pad;

    // header: the game, the PC, how long
    fillRound(s, left, y0 + pad, px(44), px(44), px(11), rgba(s, 58, 58, 60, 255));
    int minutes = int((SDL_GetTicks() - m_StartedAt) / 60000);
    QString played = minutes >= 60 ? QString("%1 h %2 min").arg(minutes / 60).arg(minutes % 60) : QString("%1 min").arg(minutes);
    drawText(s, font(px(17), true), m_Session->m_App.name, left + px(56), y0 + pad + px(2), WHITE, width - px(56) - px(60));
    drawText(s, font(px(13), false), m_Session->m_Computer->name + " · " + played, left + px(56), y0 + pad + px(24), MUTED, width - px(56));
    drawText(s, font(px(18), false), QTime::currentTime().toString("HH:mm"), left + width, y0 + pad + px(8), WHITE, 0, true);

    // rows
    auto row = [&](int item, int y, const QString& label, const QString& value, SDL_Color labelColor, double fill = -1) {
        bool on = item == m_Index;
        int rh = px(50);
        fillRound(s, left, y, width, rh, px(14), on ? rgba(s, 255, 255, 255, 255) : rgba(s, 44, 44, 46, 255));
        TTF_Font* f = font(px(15), on);
        int ty = y + (rh - TTF_FontHeight(f)) / 2;
        drawText(s, f, label, left + px(16), ty, on ? BLACK : labelColor);
        if (fill >= 0) {
            int bx = left + px(110), bw = width - px(110) - px(56), by = y + rh / 2 - px(3);
            fillRound(s, bx, by, bw, px(6), px(3), on ? rgba(s, 200, 200, 204, 255) : rgba(s, 72, 72, 74, 255));
            fillRound(s, bx, by, std::max(px(6), int(bw * fill)), px(6), px(3), on ? rgba(s, 0, 0, 0, 255) : rgba(s, 255, 255, 255, 255));
        }
        if (!value.isEmpty()) {
            TTF_Font* small = font(px(13), false);
            drawText(s, small, value, left + width - px(16), y + (rh - TTF_FontHeight(small)) / 2, on ? SDL_Color{80, 80, 84, 255} : MUTED, 0, true);
        }
    };
    int y = y0 + pad + px(44) + px(18);
    int step = px(56);
    row(Resume, y, "Resume", "", WHITE); y += step;
    row(Volume, y, "Volume", m_Volume >= 0 ? QString::number(m_Volume) : QString("—"), WHITE, m_Volume >= 0 ? m_Volume / 100.0 : 0); y += step;
    row(Stats, y, "Performance stats", m_StatsAfter ? "On" : "Off", WHITE); y += step;
    row(Mouse, y, m_Session->m_InputHandler->isAbsoluteMouseMode() ? "Mouse: like a desktop" : "Mouse: in the game", "Switch", WHITE);

    int bottom = y0 + ph - pad - 3 * step + px(6);
    row(Disconnect, bottom, "Disconnect", "game keeps running", WHITE); bottom += step;
    row(StopGame, bottom, "Stop the game", "", PINK); bottom += step;
    row(BackToWork, bottom, "‹ Back to work", "", WHITE);

    // stats, top right, from Moonlight's own performance text
    QStringList lines = QString::fromUtf8(m_Session->getOverlayManager().getOverlayText(Overlay::OverlayDebug)).split('\n', Qt::SkipEmptyParts);
    if (!lines.isEmpty()) {
        int sw = px(300), sx = W - px(48) - sw, sy = px(48);
        TTF_Font* small = font(px(13), false);
        int lh = TTF_FontLineSkip(small);
        int shown = std::min<int>(int(lines.size()), 10);
        fillRound(s, sx, sy, sw, px(36) + shown * lh, px(20), rgba(s, 28, 28, 30, 230));
        drawText(s, font(px(12), false), "Stream", sx + px(18), sy + px(12), MUTED);
        for (int i = 0; i < shown; i++) {
            drawText(s, small, lines[i].trimmed(), sx + px(18), sy + px(30) + i * lh, WHITE, sw - px(36));
        }
    }

    // hints, bottom right
    QString hint = "A choose    B resume    Guide · L1 R1 Select Start · Ctrl Alt Shift Q";
    TTF_Font* hf = font(px(13), false);
    int hw = 0, hh = 0;
    TTF_SizeUTF8(hf, hint.toUtf8().constData(), &hw, &hh);
    int bw = hw + px(32), bh = px(38);
    fillRound(s, W - px(48) - bw, H - px(40) - bh, bw, bh, bh / 2, rgba(s, 28, 28, 30, 235));
    drawText(s, hf, hint, W - px(48) - bw + px(16), H - px(40) - bh + (bh - hh) / 2, WHITE);

    SDL_UnlockMutex(m_Lock);
    return s;
}
