#include "playmeta.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QUrlQuery>

#include <memory>

static const char* IGDB_FIELDS =
    "fields name,summary,first_release_date,genres.name,themes.name,game_modes.name,"
    "cover.image_id,artworks.image_id,screenshots.image_id,"
    "involved_companies.developer,involved_companies.company.name;";

static QString normalized(const QString& name)
{
    return name.toLower().remove(QRegularExpression("[^a-z0-9]"));
}

PlayMeta::PlayMeta(const QDir& dataDir, QObject* parent)
    : QObject(parent),
      m_Dir(dataDir)
{
    m_Dir.mkpath("art");
    QFile file(m_Dir.filePath("meta.json"));
    if (file.open(QIODevice::ReadOnly)) {
        m_Games = QJsonDocument::fromJson(file.readAll()).object().value("games").toObject();
    }
    m_SaveTimer.setSingleShot(true);
    m_SaveTimer.setInterval(1000);
    connect(&m_SaveTimer, &QTimer::timeout, this, &PlayMeta::save);
}

void PlayMeta::setKeys(const QString& igdbClientId, const QString& igdbSecret, const QString& steamGridDbKey)
{
    if (igdbClientId != m_ClientId || igdbSecret != m_Secret) {
        m_Token.clear();
    }
    m_ClientId = igdbClientId.trimmed();
    m_Secret = igdbSecret.trimmed();
    m_SgdbKey = steamGridDbKey.trimmed();
}

void PlayMeta::save()
{
    QSaveFile file(m_Dir.filePath("meta.json"));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(QJsonObject{{"games", m_Games}}).toJson(QJsonDocument::Compact));
        file.commit();
    }
}

// --- one request at a time ---------------------------------------------------------------------------

void PlayMeta::next()
{
    if (m_Busy || m_Queue.isEmpty()) {
        return;
    }
    m_Busy = true;
    m_Queue.dequeue()();
}

// Every queued task ends by calling this (through `finish` below)
static void finishLater(PlayMeta* self, bool* busy, std::function<void()> next)
{
    QTimer::singleShot(260, self, [busy, next] { *busy = false; next(); });
}

// --- IGDB ---------------------------------------------------------------------------------------------

void PlayMeta::withToken(std::function<void(QString)> then)
{
    if (!m_Token.isEmpty() && QDateTime::currentSecsSinceEpoch() < m_TokenExpires - 60) {
        then(m_Token);
        return;
    }
    QUrl url("https://id.twitch.tv/oauth2/token");
    QUrlQuery query;
    query.addQueryItem("client_id", m_ClientId);
    query.addQueryItem("client_secret", m_Secret);
    query.addQueryItem("grant_type", "client_credentials");
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    QNetworkReply* reply = m_Net.post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply, then] {
        reply->deleteLater();
        QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
        m_Token = o.value("access_token").toString();
        m_TokenExpires = QDateTime::currentSecsSinceEpoch() + o.value("expires_in").toInt(3600);
        if (m_Token.isEmpty()) {
            qWarning() << "Dot Play: IGDB sign-in failed:" << reply->errorString();
        }
        then(m_Token);
    });
}

void PlayMeta::igdb(const QString& body, std::function<void(QJsonArray)> done)
{
    if (!hasIgdb()) {
        done(QJsonArray());
        return;
    }
    withToken([this, body, done](QString token) {
        if (token.isEmpty()) {
            done(QJsonArray());
            return;
        }
        QNetworkRequest request(QUrl("https://api.igdb.com/v4/games"));
        request.setRawHeader("Client-ID", m_ClientId.toUtf8());
        request.setRawHeader("Authorization", "Bearer " + token.toUtf8());
        request.setHeader(QNetworkRequest::ContentTypeHeader, "text/plain");
        QNetworkReply* reply = m_Net.post(request, body.toUtf8());
        connect(reply, &QNetworkReply::finished, this, [reply, done] {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                qWarning() << "Dot Play: IGDB:" << reply->errorString();
            }
            done(QJsonDocument::fromJson(reply->readAll()).array());
        });
    });
}

QString PlayMeta::image(const QString& imageId, const QString& size)
{
    return imageId.isEmpty() ? QString() : QString("https://images.igdb.com/igdb/image/upload/%1/%2.jpg").arg(size, imageId);
}

QJsonObject PlayMeta::simplify(const QJsonObject& g)
{
    QJsonObject out;
    out["id"] = g.value("id").toInt();
    out["name"] = g.value("name").toString();
    out["summary"] = g.value("summary").toString();
    qint64 released = g.value("first_release_date").toInteger();
    out["year"] = released ? QString::number(QDateTime::fromSecsSinceEpoch(released).date().year()) : QString();

    for (const QJsonValue& c : g.value("involved_companies").toArray()) {
        QJsonObject company = c.toObject();
        if (company.value("developer").toBool()) {
            out["developer"] = company.value("company").toObject().value("name").toString();
            break;
        }
    }

    QJsonArray tags;
    QStringList seen;
    for (const char* field : {"genres", "themes", "game_modes"}) {
        for (const QJsonValue& v : g.value(field).toArray()) {
            QString name = v.toObject().value("name").toString();
            // IGDB's longer names, said the way a person would
            if (name == "Role-playing (RPG)") name = "Role-playing";
            else if (name == "Hack and slash/Beat 'em up") name = "Hack and slash";
            else if (name == "Shooter" && seen.contains("Shooter")) continue;
            else if (name == "Single player") continue;  // nearly every game; says nothing
            else if (name == "Multiplayer") name = "Online multiplayer";
            else if (name == "Split screen") name = "Couch co-op";
            if (!name.isEmpty() && !seen.contains(name)) {
                seen << name;
                tags.append(name);
            }
        }
    }
    out["tags"] = tags;

    out["cover"] = image(g.value("cover").toObject().value("image_id").toString(), "t_cover_big");
    QJsonArray artworks = g.value("artworks").toArray();
    QJsonArray shots;
    for (const QJsonValue& s : g.value("screenshots").toArray()) {
        if (shots.size() < 6) shots.append(image(s.toObject().value("image_id").toString(), "t_screenshot_big"));
    }
    out["screenshots"] = shots;
    out["banner"] = !artworks.isEmpty() ? image(artworks.first().toObject().value("image_id").toString(), "t_1080p")
                  : (!g.value("screenshots").toArray().isEmpty() ? image(g.value("screenshots").toArray().first().toObject().value("image_id").toString(), "t_1080p") : QString());
    return out;
}

void PlayMeta::storeIgdb(const QString& key, const QJsonObject& game)
{
    QJsonObject e = m_Games.value(key).toObject();
    e["igdb"] = simplify(game);
    e.remove("none");
    e["checked"] = QDateTime::currentSecsSinceEpoch();
    m_Games[key] = e;
    m_SaveTimer.start();
    emit changed();
}

void PlayMeta::lookUp(const QString& key, const QString& name)
{
    QString escaped = QString(name).replace('"', ' ');
    igdb(QString("search \"%1\"; %2 limit 10;").arg(escaped, IGDB_FIELDS), [this, key, name](QJsonArray results) {
        // the best match: the same name (newest first, so "DOOM" is the 2016 one), else IGDB's first result
        QJsonObject best;
        qint64 bestDate = -1;
        for (const QJsonValue& v : results) {
            QJsonObject g = v.toObject();
            if (normalized(g.value("name").toString()) == normalized(name) && g.value("first_release_date").toInteger() > bestDate) {
                best = g;
                bestDate = g.value("first_release_date").toInteger();
            }
        }
        if (best.isEmpty() && !results.isEmpty()) {
            best = results.first().toObject();
        }
        if (!best.isEmpty()) {
            storeIgdb(key, best);
        }
        else {
            QJsonObject e = m_Games.value(key).toObject();
            e["checked"] = QDateTime::currentSecsSinceEpoch();
            m_Games[key] = e;
            m_SaveTimer.start();
        }
        lookUpSgdb(key, best.isEmpty() ? name : best.value("name").toString());
    });
}

void PlayMeta::lookUpMissing(const QList<QPair<QString, QString>>& keysAndNames, bool again)
{
    if (!hasIgdb() && !hasSteamGridDb()) {
        return;
    }
    for (const auto& kn : keysAndNames) {
        QJsonObject e = m_Games.value(kn.first).toObject();
        bool known = e.contains("checked") || e.value("none").toBool();
        if (known && !again) {
            continue;
        }
        if (again && e.value("pinned").toBool()) {
            continue;  // chosen by hand in Identify: keep it
        }
        QString key = kn.first, name = kn.second;
        m_Queue.enqueue([this, key, name] {
            if (hasIgdb()) {
                lookUp(key, name);
            }
            else {
                QJsonObject e = m_Games.value(key).toObject();
                e["checked"] = QDateTime::currentSecsSinceEpoch();
                m_Games[key] = e;
                lookUpSgdb(key, name);
            }
        });
    }
    next();
}

void PlayMeta::searchIgdb(const QString& name, std::function<void(QJsonArray)> done)
{
    QString escaped = QString(name).replace('"', ' ');
    igdb(QString("search \"%1\"; %2 limit 8;").arg(escaped, IGDB_FIELDS), [done](QJsonArray results) {
        QJsonArray out;
        for (const QJsonValue& v : results) {
            QJsonObject g = simplify(v.toObject());
            QJsonArray tags = g.value("tags").toArray();
            QStringList detail;
            if (!g.value("developer").toString().isEmpty()) detail << g.value("developer").toString();
            if (!tags.isEmpty()) detail << tags.first().toString();
            out.append(QJsonObject{
                {"id", g.value("id")},
                {"name", g.value("name")},
                {"year", g.value("year")},
                {"detail", detail.join(" · ")},
                {"cover", g.value("cover").toString().replace("t_cover_big", "t_cover_small")},
            });
        }
        done(out);
    });
}

void PlayMeta::identify(const QString& key, int igdbId)
{
    igdb(QString("%1 where id = %2;").arg(IGDB_FIELDS).arg(igdbId), [this, key](QJsonArray results) {
        if (results.isEmpty()) {
            return;
        }
        storeIgdb(key, results.first().toObject());
        QJsonObject e = m_Games.value(key).toObject();
        e["pinned"] = true;
        e.remove("sgdb");
        m_Games[key] = e;
        m_SaveTimer.start();
        QString name = e.value("igdb").toObject().value("name").toString();
        m_Queue.enqueue([this, key, name] { lookUpSgdb(key, name); });
        next();
    });
}

void PlayMeta::identifyNone(const QString& key)
{
    QJsonObject e = m_Games.value(key).toObject();
    e.remove("igdb");
    e.remove("sgdb");
    e["none"] = true;
    e["pinned"] = true;
    e["checked"] = QDateTime::currentSecsSinceEpoch();
    m_Games[key] = e;
    m_SaveTimer.start();
    emit changed();
}

// --- SteamGridDB --------------------------------------------------------------------------------------

void PlayMeta::sgdb(const QString& path, std::function<void(QJsonValue)> done)
{
    if (!hasSteamGridDb()) {
        done(QJsonValue());
        return;
    }
    QNetworkRequest request(QUrl("https://www.steamgriddb.com/api/v2/" + path));
    request.setRawHeader("Authorization", "Bearer " + m_SgdbKey.toUtf8());
    QNetworkReply* reply = m_Net.get(request);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "Dot Play: SteamGridDB:" << reply->errorString();
        }
        done(QJsonDocument::fromJson(reply->readAll()).object().value("data"));
    });
}

static QString sgdbPath(const QString& kind, int id)
{
    if (kind == "cover") return QString("grids/game/%1?dimensions=600x900,342x482,660x930&types=static").arg(id);
    if (kind == "banner") return QString("heroes/game/%1?types=static").arg(id);
    if (kind == "logo") return QString("logos/game/%1?types=static").arg(id);
    return QString("icons/game/%1?types=static").arg(id);
}

void PlayMeta::lookUpSgdb(const QString& key, const QString& name)
{
    auto finish = [this] { finishLater(this, &m_Busy, [this] { next(); }); };
    if (!hasSteamGridDb()) {
        finish();
        return;
    }
    sgdb("search/autocomplete/" + QString::fromUtf8(QUrl::toPercentEncoding(name)), [this, key, finish](QJsonValue data) {
        QJsonArray found = data.toArray();
        if (found.isEmpty()) {
            finish();
            return;
        }
        int id = found.first().toObject().value("id").toInt();
        QJsonObject e = m_Games.value(key).toObject();
        QJsonObject art{{"id", id}};
        e["sgdb"] = art;
        m_Games[key] = e;

        // the first (most liked) picture of each kind
        auto kinds = std::make_shared<QStringList>(QStringList{"cover", "banner", "logo", "icon"});
        auto step = std::make_shared<std::function<void()>>();
        *step = [this, key, id, kinds, step, finish] {
            if (kinds->isEmpty()) {
                m_SaveTimer.start();
                emit changed();
                finish();
                return;
            }
            QString kind = kinds->takeFirst();
            sgdb(sgdbPath(kind, id), [this, key, kind, step](QJsonValue data) {
                QJsonArray list = data.toArray();
                if (!list.isEmpty()) {
                    QJsonObject e = m_Games.value(key).toObject();
                    QJsonObject art = e.value("sgdb").toObject();
                    art[kind] = list.first().toObject().value("url").toString();
                    e["sgdb"] = art;
                    m_Games[key] = e;
                }
                (*step)();
            });
        };
        (*step)();
    });
}

void PlayMeta::searchArt(const QString& key, const QString& name, const QString& kind, std::function<void(QJsonArray)> done)
{
    auto list = [this, kind, done](int id) {
        sgdb(sgdbPath(kind, id), [done](QJsonValue data) {
            QJsonArray out;
            for (const QJsonValue& v : data.toArray()) {
                QJsonObject o = v.toObject();
                out.append(QJsonObject{
                    {"url", o.value("url")},
                    {"thumb", o.value("thumb").toString().isEmpty() ? o.value("url") : o.value("thumb")},
                    {"author", o.value("author").toObject().value("name")},
                });
            }
            done(out);
        });
    };
    int id = m_Games.value(key).toObject().value("sgdb").toObject().value("id").toInt();
    if (id) {
        list(id);
        return;
    }
    sgdb("search/autocomplete/" + QString::fromUtf8(QUrl::toPercentEncoding(name)), [list, done](QJsonValue data) {
        QJsonArray found = data.toArray();
        if (found.isEmpty()) done(QJsonArray());
        else list(found.first().toObject().value("id").toInt());
    });
}

// --- pictures on disk ---------------------------------------------------------------------------------

QString PlayMeta::local(const QString& url)
{
    if (url.isEmpty() || !url.startsWith("http")) {
        return url;
    }
    QString hash = QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha1).toHex();
    QString ext = url.section('.', -1).section('?', 0, 0).left(4).toLower();
    if (ext != "png" && ext != "jpg" && ext != "jpeg" && ext != "webp") ext = "img";
    QString path = m_Dir.filePath("art/" + hash + "." + ext);
    if (QFile::exists(path)) {
        return QUrl::fromLocalFile(path).toString();
    }
    if (!m_Downloading.contains(url)) {
        m_Downloading.insert(url);
        QNetworkReply* reply = m_Net.get(QNetworkRequest(QUrl(url)));
        connect(reply, &QNetworkReply::finished, this, [this, reply, url, path] {
            reply->deleteLater();
            m_Downloading.remove(url);
            if (reply->error() == QNetworkReply::NoError) {
                QSaveFile file(path);
                if (file.open(QIODevice::WriteOnly)) {
                    file.write(reply->readAll());
                    file.commit();
                }
            }
        });
    }
    return url;  // shown from the network this time, from disk next time
}
