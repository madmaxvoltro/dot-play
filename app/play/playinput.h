#pragma once

#include <QObject>
#include <QTimer>
#include <QEvent>
#include <QElapsedTimer>
#include <QPoint>

#include "SDL_compat.h"

class StreamingPreferences;

// Dot Play's input: controllers become key presses for the QML screens (like Moonlight's
// SdlGamepadKeyNavigation), and Dot Play keeps track of what you used last, a controller or the keyboard
// and mouse, so every screen can show the right hints. Holding a direction repeats, and speeds up a
// little after 3 seconds.
//
//   A Return   B Escape   X Menu   Y Search   LB F13   RB F14   LT F15   RT F16
//   Start F17  Back/Select F18     Guide F19  D-pad / left stick: arrow keys
class PlayInput : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)           // "pad" or "keys"
    Q_PROPERTY(QString padType READ padType NOTIFY padChanged)      // "xbox", "playstation", "switch"
    Q_PROPERTY(QString padName READ padName NOTIFY padChanged)
    Q_PROPERTY(int gamepads READ gamepads NOTIFY padChanged)

public:
    explicit PlayInput(StreamingPreferences* prefs, QObject* parent = nullptr);
    ~PlayInput();

    QString mode() const { return m_Mode; }
    QString padType() const;
    QString padName() const { return m_PadName; }
    int gamepads() const { return m_Gamepads.size(); }

    // "auto" follows the controller in use; "xbox", "playstation" or "switch" force the icons
    void setIconOverride(const QString& icons);

    Q_INVOKABLE void enable();
    Q_INVOKABLE void disable();
    Q_INVOKABLE void notifyWindowFocus(bool hasFocus);

signals:
    void modeChanged();
    void padChanged();

protected:
    bool eventFilter(QObject* obj, QEvent* event) override;

private slots:
    void poll();

private:
    void setMode(const QString& mode);
    void sendKey(QEvent::Type type, Qt::Key key);
    void tap(Qt::Key key);
    void updateTimer();
    void openAll();
    void updatePadInfo(SDL_GameController* gc);
    void handleDirection(Qt::Key key);

    StreamingPreferences* m_Prefs;
    QTimer* m_Timer;
    QList<SDL_GameController*> m_Gamepads;
    bool m_Enabled = false;
    bool m_HasFocus = true;
    bool m_FirstPoll = false;
    QString m_Mode = "keys";
    QString m_PadType = "xbox";
    QString m_PadName;
    QString m_IconOverride = "auto";

    // held direction (D-pad or stick) and its repeat timing
    Qt::Key m_Held = Qt::Key_unknown;
    QElapsedTimer m_HeldFor;
    qint64 m_NextRepeat = 0;
    bool m_LeftTrigger = false;
    bool m_RightTrigger = false;
    QPoint m_LastMouse;
};
