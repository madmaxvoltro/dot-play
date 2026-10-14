#include "playinput.h"

#include <QCursor>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWindow>

#include "settings/mappingmanager.h"
#include "settings/streamingpreferences.h"

// Holding a direction: first repeat after this long, then every REPEAT_MS, and every FAST_REPEAT_MS
// once it has been held for ACCELERATE_AFTER_MS (the "speeds up after 3 seconds").
static const int FIRST_REPEAT_MS = 380;
static const int REPEAT_MS = 130;
static const int FAST_REPEAT_MS = 75;
static const int ACCELERATE_AFTER_MS = 3000;
static const short STICK_THRESHOLD = 24000;
static const short TRIGGER_THRESHOLD = 20000;

PlayInput::PlayInput(StreamingPreferences* prefs, QObject* parent)
    : QObject(parent),
      m_Prefs(prefs)
{
    m_Timer = new QTimer(this);
    m_Timer->setTimerType(Qt::PreciseTimer);
    connect(m_Timer, &QTimer::timeout, this, &PlayInput::poll);
    qApp->installEventFilter(this);
}

PlayInput::~PlayInput()
{
    disable();
}

QString PlayInput::padType() const
{
    return m_IconOverride == "auto" ? m_PadType : m_IconOverride;
}

void PlayInput::setIconOverride(const QString& icons)
{
    QString value = icons.isEmpty() ? "auto" : icons;
    if (value != m_IconOverride) {
        m_IconOverride = value;
        emit padChanged();
    }
}

void PlayInput::enable()
{
    if (m_Enabled) {
        return;
    }

    // Like SdlGamepadKeyNavigation: the game controller subsystem is opened and closed around each
    // stream, so the streaming session gets its own fresh controller arrival events.
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Dot Play: SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) failed: %s", SDL_GetError());
        return;
    }

    MappingManager mappingManager;
    mappingManager.applyMappings();

    SDL_JoystickUpdate();
    SDL_FlushEvent(SDL_CONTROLLERDEVICEADDED);
    openAll();

    m_Enabled = true;
    if (!m_Gamepads.isEmpty() && m_Mode != "pad") {
        setMode("pad");
    }
    emit padChanged();
    updateTimer();
}

void PlayInput::disable()
{
    if (!m_Enabled) {
        return;
    }
    m_Enabled = false;
    updateTimer();
    while (!m_Gamepads.isEmpty()) {
        SDL_GameControllerClose(m_Gamepads.takeFirst());
    }
    SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
    m_Held = Qt::Key_unknown;
}

void PlayInput::notifyWindowFocus(bool hasFocus)
{
    m_HasFocus = hasFocus;
    updateTimer();
}

void PlayInput::updateTimer()
{
    bool run = m_Enabled && m_HasFocus;
    if (run && !m_Timer->isActive()) {
        m_FirstPoll = true;
        m_Timer->start(16);
    }
    else if (!run && m_Timer->isActive()) {
        m_Timer->stop();
    }
}

void PlayInput::openAll()
{
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        if (SDL_IsGameController(i)) {
            SDL_GameController* gc = SDL_GameControllerOpen(i);
            if (gc != nullptr && !m_Gamepads.contains(gc)) {
                m_Gamepads.append(gc);
                updatePadInfo(gc);
            }
        }
    }
}

void PlayInput::updatePadInfo(SDL_GameController* gc)
{
    QString type = "xbox";
#if SDL_VERSION_ATLEAST(2, 0, 12)
    switch (SDL_GameControllerGetType(gc)) {
    case SDL_CONTROLLER_TYPE_PS3:
    case SDL_CONTROLLER_TYPE_PS4:
#if SDL_VERSION_ATLEAST(2, 0, 14)
    case SDL_CONTROLLER_TYPE_PS5:
#endif
        type = "playstation";
        break;
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_PRO:
#if SDL_VERSION_ATLEAST(2, 24, 0)
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_LEFT:
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT:
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_PAIR:
#endif
        type = "switch";
        break;
    default:
        break;
    }
#endif
    const char* name = SDL_GameControllerName(gc);
    m_PadType = type;
    m_PadName = name ? QString::fromUtf8(name) : QStringLiteral("Controller");
    emit padChanged();
}

void PlayInput::setMode(const QString& mode)
{
    if (mode == m_Mode) {
        return;
    }
    m_Mode = mode;
    // With a controller, the mouse pointer only gets in the way
    if (mode == "pad") {
        QGuiApplication::setOverrideCursor(Qt::BlankCursor);
    }
    else {
        while (QGuiApplication::overrideCursor() != nullptr) {
            QGuiApplication::restoreOverrideCursor();
        }
    }
    emit modeChanged();
}

bool PlayInput::eventFilter(QObject* obj, QEvent* event)
{
    Q_UNUSED(obj)
    // Real keyboard and mouse use switches to keyboard mode. Key presses we send for the controller
    // aren't spontaneous, so they don't count.
    switch (event->type()) {
    case QEvent::KeyPress:
        if (event->spontaneous()) {
            setMode("keys");
        }
        break;
    case QEvent::MouseButtonPress:
    case QEvent::Wheel:
        if (event->spontaneous()) {
            setMode("keys");
        }
        break;
    case QEvent::MouseMove:
        if (event->spontaneous()) {
            QPoint pos = static_cast<QMouseEvent*>(event)->globalPosition().toPoint();
            // a few pixels of jitter (or the cursor being hidden) isn't someone using the mouse
            if (!m_LastMouse.isNull() && (pos - m_LastMouse).manhattanLength() > 12) {
                setMode("keys");
            }
            m_LastMouse = pos;
        }
        break;
    default:
        break;
    }
    return false;
}

void PlayInput::sendKey(QEvent::Type type, Qt::Key key)
{
    QWindow* window = QGuiApplication::focusWindow();
    if (window != nullptr) {
        QKeyEvent ev(type, key, Qt::NoModifier);
        QGuiApplication::sendEvent(window, &ev);
    }
}

void PlayInput::tap(Qt::Key key)
{
    sendKey(QEvent::KeyPress, key);
    sendKey(QEvent::KeyRelease, key);
}

void PlayInput::handleDirection(Qt::Key key)
{
    if (key != m_Held) {
        m_Held = key;
        if (key != Qt::Key_unknown) {
            setMode("pad");
            tap(key);
            m_HeldFor.start();
            m_NextRepeat = FIRST_REPEAT_MS;
        }
        return;
    }
    if (key == Qt::Key_unknown) {
        return;
    }
    qint64 held = m_HeldFor.elapsed();
    if (held >= m_NextRepeat) {
        tap(key);
        m_NextRepeat = held + (held >= ACCELERATE_AFTER_MS ? FAST_REPEAT_MS : REPEAT_MS);
    }
}

void PlayInput::poll()
{
    SDL_Event event;
    SDL_JoystickUpdate();

    // Don't pick up buttons still held from the stream (like the quit combo)
    if (m_FirstPoll) {
        SDL_FlushEvent(SDL_CONTROLLERBUTTONDOWN);
        SDL_FlushEvent(SDL_CONTROLLERBUTTONUP);
        m_FirstPoll = false;
    }

    while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT) == 1) {
        switch (event.type) {
        case SDL_QUIT:
            QCoreApplication::quit();
            break;
        case SDL_CONTROLLERDEVICEADDED: {
            SDL_GameController* gc = SDL_GameControllerOpen(event.cdevice.which);
            if (gc != nullptr) {
                if (!m_Gamepads.contains(gc)) {
                    m_Gamepads.append(gc);
                    updatePadInfo(gc);
                }
                else {
                    SDL_GameControllerClose(gc);
                }
            }
            break;
        }
        case SDL_CONTROLLERDEVICEREMOVED: {
            SDL_GameController* gc = SDL_GameControllerFromInstanceID(event.cdevice.which);
            if (gc != nullptr && m_Gamepads.removeOne(gc)) {
                SDL_GameControllerClose(gc);
                emit padChanged();
            }
            break;
        }
        case SDL_CONTROLLERBUTTONDOWN:
        case SDL_CONTROLLERBUTTONUP: {
            bool down = event.type == SDL_CONTROLLERBUTTONDOWN;
            if (down) {
                SDL_GameController* gc = SDL_GameControllerFromInstanceID(event.cbutton.which);
                if (gc != nullptr && m_Gamepads.size() > 1) {
                    updatePadInfo(gc);  // icons follow whichever controller is in use
                }
                setMode("pad");
            }
            int button = event.cbutton.button;
            if (m_Prefs != nullptr && m_Prefs->swapFaceButtons) {
                if (button == SDL_CONTROLLER_BUTTON_A) button = SDL_CONTROLLER_BUTTON_B;
                else if (button == SDL_CONTROLLER_BUTTON_B) button = SDL_CONTROLLER_BUTTON_A;
                else if (button == SDL_CONTROLLER_BUTTON_X) button = SDL_CONTROLLER_BUTTON_Y;
                else if (button == SDL_CONTROLLER_BUTTON_Y) button = SDL_CONTROLLER_BUTTON_X;
            }
            QEvent::Type type = down ? QEvent::KeyPress : QEvent::KeyRelease;
            switch (button) {
            case SDL_CONTROLLER_BUTTON_A: sendKey(type, Qt::Key_Return); break;
            case SDL_CONTROLLER_BUTTON_B: sendKey(type, Qt::Key_Escape); break;
            case SDL_CONTROLLER_BUTTON_X: sendKey(type, Qt::Key_Menu); break;
            case SDL_CONTROLLER_BUTTON_Y: sendKey(type, Qt::Key_Search); break;
            case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: sendKey(type, Qt::Key_F13); break;
            case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: sendKey(type, Qt::Key_F14); break;
            case SDL_CONTROLLER_BUTTON_START: sendKey(type, Qt::Key_F17); break;
            case SDL_CONTROLLER_BUTTON_BACK: sendKey(type, Qt::Key_F18); break;
            case SDL_CONTROLLER_BUTTON_GUIDE: sendKey(type, Qt::Key_F19); break;
            default: break;  // the D-pad is read below, with the stick, so it can repeat
            }
            break;
        }
        default:
            break;
        }
    }

    // Directions: D-pad and left stick, with hold-to-repeat
    Qt::Key direction = Qt::Key_unknown;
    bool left = false, right = false;
    for (SDL_GameController* gc : std::as_const(m_Gamepads)) {
        short x = SDL_GameControllerGetAxis(gc, SDL_CONTROLLER_AXIS_LEFTX);
        short y = SDL_GameControllerGetAxis(gc, SDL_CONTROLLER_AXIS_LEFTY);
        if (SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_DPAD_UP) || y < -STICK_THRESHOLD) direction = Qt::Key_Up;
        else if (SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_DPAD_DOWN) || y > STICK_THRESHOLD) direction = Qt::Key_Down;
        else if (SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_DPAD_LEFT) || x < -STICK_THRESHOLD) direction = Qt::Key_Left;
        else if (SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_DPAD_RIGHT) || x > STICK_THRESHOLD) direction = Qt::Key_Right;
        left = left || SDL_GameControllerGetAxis(gc, SDL_CONTROLLER_AXIS_TRIGGERLEFT) > TRIGGER_THRESHOLD;
        right = right || SDL_GameControllerGetAxis(gc, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) > TRIGGER_THRESHOLD;
        if (direction != Qt::Key_unknown) {
            break;
        }
    }
    handleDirection(direction);

    // Triggers are axes: one key press each time one is pulled
    if (left != m_LeftTrigger) {
        m_LeftTrigger = left;
        if (left) { setMode("pad"); tap(Qt::Key_F15); }
    }
    if (right != m_RightTrigger) {
        m_RightTrigger = right;
        if (right) { setMode("pad"); tap(Qt::Key_F16); }
    }
}
