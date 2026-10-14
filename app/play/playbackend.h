#pragma once

#include <QDir>
#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QVariant>

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"

class PlayInput;
class PlayMeta;
class Session;
class StreamingPreferences;

// What Dot Play's screens talk to (`Play` in QML): one library of the games on every paired PC, with
// details and art (PlayMeta), play time, stream profiles and settings; and starting a stream.
//
// A game is known by its key: its name, lower case, letters and digits only. The same game on two PCs is
// one game in the library, and plays on whichever PC is awake (or the one chosen for it).
//
// Saved in play.json beside Moonlight's own settings: keys, profiles, and per game its profile, PC,
// art chosen by hand, favourite/hidden, play time and when it was last played.
class PlayBackend : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList games READ games NOTIFY changed)
    Q_PROPERTY(QVariantList rows READ rows NOTIFY changed)
    Q_PROPERTY(QStringList tags READ tags NOTIFY changed)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY changed)
    Q_PROPERTY(QVariantList pcs READ pcs NOTIFY changed)
    Q_PROPERTY(QVariantList hiddenGames READ hiddenGames NOTIFY changed)
    Q_PROPERTY(QVariantMap keys READ keys NOTIFY changed)
    Q_PROPERTY(bool anyOnline READ anyOnline NOTIFY changed)
    Q_PROPERTY(QString pcSummary READ pcSummary NOTIFY changed)
    Q_PROPERTY(QString emptyTitle READ emptyTitle NOTIFY changed)
    Q_PROPERTY(QString emptyText READ emptyText NOTIFY changed)
    Q_PROPERTY(bool preview READ preview CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    PlayBackend(ComputerManager* computers, StreamingPreferences* prefs, PlayInput* input, QObject* parent = nullptr);

    QVariantList games() const { return m_Games; }
    QVariantList rows() const { return m_Rows; }
    QStringList tags() const { return m_Tags; }
    QVariantList profiles() const;
    QVariantList pcs() const;
    QVariantList hiddenGames() const { return m_Hidden; }
    QVariantMap keys() const;
    bool anyOnline() const { return m_AnyOnline; }
    QString pcSummary() const { return m_PcSummary; }
    QString emptyTitle() const { return m_EmptyTitle; }
    QString emptyText() const { return m_EmptyText; }
    bool preview() const { return false; }
    QString version() const;

    Q_INVOKABLE QVariantList search(const QString& text, const QStringList& tags) const;
    Q_INVOKABLE QVariantMap game(const QString& key) const;

    Q_INVOKABLE void identifySearch(const QString& text);
    Q_INVOKABLE void identify(const QString& key, int igdbId);
    Q_INVOKABLE void identifyNone(const QString& key);
    Q_INVOKABLE void artSearch(const QString& key, const QString& kind);
    Q_INVOKABLE void setArt(const QString& key, const QString& kind, const QString& url);
    Q_INVOKABLE void resetArt(const QString& key, const QString& kind);

    Q_INVOKABLE void setHidden(const QString& key, bool hidden);
    Q_INVOKABLE void setFavourite(const QString& key, bool favourite);
    Q_INVOKABLE void setGameProfile(const QString& key, const QString& profileId);
    Q_INVOKABLE void setGamePc(const QString& key, const QString& pcName);

    Q_INVOKABLE QString saveProfile(const QVariantMap& profile);
    Q_INVOKABLE void deleteProfile(const QString& id);
    Q_INVOKABLE void saveKeys(const QVariantMap& keys);
    Q_INVOKABLE void refreshMeta();

    // Streaming: createSession applies the game's profile to Moonlight's settings (in memory only);
    // streamEnded puts them back and adds the play time.
    Q_INVOKABLE Session* createSession(const QString& key);
    Q_INVOKABLE QVariantMap streamInfo(const QString& key) const;
    Q_INVOKABLE void streamStarted(const QString& key);
    Q_INVOKABLE void streamEnded(const QString& key);

    Q_INVOKABLE QString clipboard() const;
    Q_INVOKABLE void backToDot();

    // For Game.exe "Elden Ring" / `dot-play --game NAME`: the key of the game with this name, or ""
    QString keyForName(const QString& name) const;

signals:
    void changed();
    void identifyResults(QVariantList results);
    void artResults(QString kind, QVariantList results);
    void launchRequested(QString key);

private slots:
    void rebuild();
    void scheduleRebuild();
    void handleBoxArt(NvComputer* computer, NvApp app, QUrl image);

private:
    struct Source {
        NvComputer* computer;
        NvApp app;
        QString pcName;
        bool online;
        bool running;
    };

    QJsonObject gameStore(const QString& key) const;
    void setGameStore(const QString& key, const QString& field, const QJsonValue& value);
    QJsonObject profileFor(const QString& key) const;
    const Source* sourceFor(const QString& key) const;
    QVariantMap toMap(const QString& key, const QList<Source>& sources) const;
    QVariantList buildRows() const;
    static QString keyOf(const QString& name);
    static QString colorFor(const QString& name);
    static QString ago(qint64 secs);
    void load();
    void save();

    ComputerManager* m_Computers;
    StreamingPreferences* m_Prefs;
    PlayInput* m_Input;
    PlayMeta* m_Meta;
    BoxArtManager m_BoxArt;
    QDir m_Dir;
    QJsonObject m_Store;      // play.json
    QTimer m_RebuildTimer;
    QTimer m_SaveTimer;

    QMap<QString, QList<Source>> m_Sources;  // per game key, every PC that has it
    QMap<QString, QUrl> m_BoxArtUrls;        // per game key, Sunshine's own picture
    QVariantList m_Games, m_Rows, m_Hidden;
    QStringList m_Tags;
    bool m_AnyOnline = false;
    QString m_PcSummary, m_EmptyTitle, m_EmptyText;

    // the stream running now, and Moonlight's settings from before it
    QString m_StreamKey;
    qint64 m_StreamStart = 0;
    QVariantMap m_SavedPrefs;
};
