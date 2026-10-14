#pragma once

#include <QDir>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QQueue>
#include <QSet>
#include <QTimer>
#include <functional>

// Game details and art for Dot Play:
//   IGDB (igdb.com, through a Twitch developer app's client ID and secret): name, summary, year,
//   developer, genres, themes, game modes, cover, artwork, screenshots.
//   SteamGridDB (steamgriddb.com, an API key): covers, wide banners ("heroes"), logos, icons.
// Everything is cached on disk: meta.json beside Dot Play's settings, and the pictures in art/.
class PlayMeta : public QObject
{
    Q_OBJECT

public:
    explicit PlayMeta(const QDir& dataDir, QObject* parent = nullptr);

    void setKeys(const QString& igdbClientId, const QString& igdbSecret, const QString& steamGridDbKey);
    bool hasIgdb() const { return !m_ClientId.isEmpty() && !m_Secret.isEmpty(); }
    bool hasSteamGridDb() const { return !m_SgdbKey.isEmpty(); }

    // What's known about a game (by Dot Play's key): {"igdb": {...}, "sgdb": {"id", "cover", ...}, "none": bool}
    QJsonObject entry(const QString& key) const { return m_Games.value(key).toObject(); }

    // Look up every game that hasn't been looked up yet (or all of them again)
    void lookUpMissing(const QList<QPair<QString, QString>>& keysAndNames, bool again = false);

    // Identify: IGDB results for a name -> [{id, name, year, detail, cover}]
    void searchIgdb(const QString& name, std::function<void(QJsonArray)> done);
    void identify(const QString& key, int igdbId);
    void identifyNone(const QString& key);

    // Change art: SteamGridDB pictures of one kind -> [{url, thumb, author}]
    void searchArt(const QString& key, const QString& name, const QString& kind, std::function<void(QJsonArray)> done);

    // A picture on disk if it's been downloaded, else its address (and it gets downloaded for next time)
    QString local(const QString& url);

signals:
    void changed();

private:
    void withToken(std::function<void(QString)> then);
    void igdb(const QString& body, std::function<void(QJsonArray)> done);
    void sgdb(const QString& path, std::function<void(QJsonValue)> done);
    void lookUp(const QString& key, const QString& name);
    void storeIgdb(const QString& key, const QJsonObject& game);
    void lookUpSgdb(const QString& key, const QString& name);
    void next();
    void save();

    static QString image(const QString& imageId, const QString& size);
    static QJsonObject simplify(const QJsonObject& game);

    QDir m_Dir;
    QNetworkAccessManager m_Net;
    QString m_ClientId, m_Secret, m_SgdbKey;
    QString m_Token;
    qint64 m_TokenExpires = 0;
    QJsonObject m_Games;
    QQueue<std::function<void()>> m_Queue;  // one request at a time: IGDB allows a few per second
    bool m_Busy = false;
    QTimer m_SaveTimer;
    QSet<QString> m_Downloading;
};
