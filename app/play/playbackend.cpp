#include "playbackend.h"

#include "playinput.h"
#include "playmeta.h"

#include "settings/streamingpreferences.h"
#include "streaming/playmenu.h"
#include "streaming/session.h"

#include <QClipboard>
#include <QColor>
#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QReadLocker>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>

static const char* DEFAULT_PROFILE = "default";

PlayBackend::PlayBackend(ComputerManager* computers, StreamingPreferences* prefs, PlayInput* input, QObject* parent)
    : QObject(parent),
      m_Computers(computers),
      m_Prefs(prefs),
      m_Input(input)
{
    m_Dir = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    m_Dir.mkpath("dot-play");
    m_Dir.cd("dot-play");
    load();

    m_Meta = new PlayMeta(m_Dir, this);
    QJsonObject keys = m_Store.value("keys").toObject();
    m_Meta->setKeys(keys.value("igdbClientId").toString(), keys.value("igdbSecret").toString(), keys.value("steamGridDbKey").toString());
    m_Input->setIconOverride(keys.value("padIcons").toString("auto"));

    m_RebuildTimer.setSingleShot(true);
    m_RebuildTimer.setInterval(250);
    connect(&m_RebuildTimer, &QTimer::timeout, this, &PlayBackend::rebuild);
    m_SaveTimer.setSingleShot(true);
    m_SaveTimer.setInterval(800);
    connect(&m_SaveTimer, &QTimer::timeout, this, &PlayBackend::save);

    connect(m_Computers, &ComputerManager::computerStateChanged, this, &PlayBackend::scheduleRebuild);
    connect(m_Meta, &PlayMeta::changed, this, &PlayBackend::scheduleRebuild);
    connect(&m_BoxArt, &BoxArtManager::boxArtLoadComplete, this, &PlayBackend::handleBoxArt);

    m_PendingLaunch = qEnvironmentVariable("DOT_PLAY_GAME");
    m_Computers->startPolling();
    rebuild();
}

QString PlayBackend::version() const
{
    return QCoreApplication::applicationVersion();
}

// --- storage ------------------------------------------------------------------------------------------

void PlayBackend::load()
{
    QFile file(m_Dir.filePath("play.json"));
    if (file.open(QIODevice::ReadOnly)) {
        m_Store = QJsonDocument::fromJson(file.readAll()).object();
    }
    // There's always a Default profile: Moonlight's own settings at the time
    QJsonObject profiles = m_Store.value("profiles").toObject();
    if (!profiles.contains(DEFAULT_PROFILE)) {
        int codec = m_Prefs->videoCodecConfig;
        profiles[DEFAULT_PROFILE] = QJsonObject{
            {"id", DEFAULT_PROFILE}, {"name", "Default"},
            {"width", m_Prefs->width}, {"height", m_Prefs->height}, {"fps", m_Prefs->fps},
            {"bitrate", m_Prefs->bitrateKbps},
            {"codec", codec == StreamingPreferences::VCC_FORCE_H264 ? "h264" : codec == StreamingPreferences::VCC_FORCE_HEVC ? "hevc"
                      : codec == StreamingPreferences::VCC_FORCE_AV1 ? "av1" : "auto"},
            {"hdr", m_Prefs->enableHdr},
            {"audio", m_Prefs->audioConfig == StreamingPreferences::AC_51_SURROUND ? "5.1" : m_Prefs->audioConfig == StreamingPreferences::AC_71_SURROUND ? "7.1" : "stereo"},
            {"mouse", m_Prefs->absoluteMouseMode ? "desktop" : "game"},
            {"pc", ""},
        };
        m_Store["profiles"] = profiles;
    }
}

void PlayBackend::save()
{
    QSaveFile file(m_Dir.filePath("play.json"));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(m_Store).toJson());
        file.commit();
    }
}

QJsonObject PlayBackend::gameStore(const QString& key) const
{
    return m_Store.value("games").toObject().value(key).toObject();
}

void PlayBackend::setGameStore(const QString& key, const QString& field, const QJsonValue& value)
{
    QJsonObject games = m_Store.value("games").toObject();
    QJsonObject g = games.value(key).toObject();
    if (value.isNull() || value.isUndefined()) g.remove(field);
    else g[field] = value;
    games[key] = g;
    m_Store["games"] = games;
    m_SaveTimer.start();
    scheduleRebuild();
}

// --- the library --------------------------------------------------------------------------------------

QString PlayBackend::keyOf(const QString& name)
{
    return name.toLower().remove(QRegularExpression("[^a-z0-9]"));
}

QString PlayBackend::colorFor(const QString& name)
{
    // a dark, quiet colour of the game's own, so tiles without art can be told apart
    uint h = qHash(name) % 360;
    return QColor::fromHsl(int(h), 90, 34).name();
}

QString PlayBackend::ago(qint64 secs)
{
    if (secs <= 0) return "Never";
    qint64 days = (QDateTime::currentSecsSinceEpoch() - secs) / 86400;
    if (days < 1) return "Today";
    if (days == 1) return "Yesterday";
    if (days < 7) return QDateTime::fromSecsSinceEpoch(secs).toString("dddd");
    if (days < 60) return QString("%1 weeks ago").arg(std::max<qint64>(1, days / 7));
    return QDateTime::fromSecsSinceEpoch(secs).toString("MMMM yyyy");
}

void PlayBackend::scheduleRebuild()
{
    m_RebuildTimer.start();
}

void PlayBackend::handleBoxArt(NvComputer* computer, NvApp app, QUrl image)
{
    Q_UNUSED(computer)
    m_BoxArtUrls[keyOf(app.name)] = image;
    scheduleRebuild();
}

void PlayBackend::rebuild()
{
    m_Sources.clear();
    int paired = 0, online = 0;
    QStringList onlineNames, allNames;

    for (NvComputer* computer : m_Computers->getComputers()) {
        QString name;
        bool isOnline;
        int runningId;
        QVector<NvApp> apps;
        {
            QReadLocker lock(&computer->lock);
            if (computer->pairState != NvComputer::PS_PAIRED) {
                continue;
            }
            name = computer->name;
            isOnline = computer->state == NvComputer::CS_ONLINE;
            runningId = computer->currentGameId;
            apps = computer->appList;
        }
        paired++;
        allNames << name;
        if (isOnline) {
            online++;
            onlineNames << name;
        }
        for (NvApp& app : apps) {
            if (app.hidden) {
                continue;
            }
            QString key = keyOf(app.name);
            if (key.isEmpty()) {
                continue;
            }
            m_Sources[key].append(Source{computer, app, name, isOnline, runningId != 0 && runningId == app.id});
            if (!m_BoxArtUrls.contains(key)) {
                QUrl url = m_BoxArt.loadBoxArt(computer, app);
                if (!url.toString().startsWith("qrc:")) {
                    m_BoxArtUrls[key] = url;
                }
            }
        }
    }

    m_AnyOnline = online > 0;
    m_PcSummary = paired == 0 ? QString("No PC") : (paired == 1 ? allNames.first() : QString("%1 PCs").arg(paired));
    if (paired == 0) {
        m_EmptyTitle = "No gaming PC paired yet";
        m_EmptyText = "On your Dot: Settings › Games, choose how your PC plays games and press Pair. Its games show up here.";
    }
    else if (online == 0) {
        m_EmptyTitle = paired == 1 ? allNames.first() + " is asleep" : "Your gaming PCs are asleep";
        m_EmptyText = "Turn it on, or wake it from your Dot: Settings › Games. Its games show up here once it answers.";
    }
    else {
        m_EmptyTitle = "No games on " + onlineNames.join(", ");
        m_EmptyText = "Add your games in Sunshine (or Apollo) on the PC: each one shows up here with its art.";
    }

    // games, details looked up for any not seen before
    QList<QPair<QString, QString>> lookups;
    m_Games.clear();
    m_Hidden.clear();
    QMap<QString, int> tagCounts;
    QJsonObject stats = m_Store.value("games").toObject();
    bool storeChanged = false;
    for (auto it = m_Sources.constBegin(); it != m_Sources.constEnd(); ++it) {
        lookups.append({it.key(), it.value().first().app.name});
        QJsonObject g = stats.value(it.key()).toObject();
        if (!g.contains("firstSeen")) {
            g["firstSeen"] = QDateTime::currentSecsSinceEpoch();
            stats[it.key()] = g;
            storeChanged = true;
        }
        QVariantMap map = toMap(it.key(), it.value());
        if (map.value("hidden").toBool()) {
            m_Hidden.append(map);
            continue;
        }
        for (const QString& t : map.value("tags").toStringList()) {
            tagCounts[t]++;
        }
        m_Games.append(map);
    }
    if (storeChanged) {
        m_Store["games"] = stats;
        m_SaveTimer.start();
    }
    std::sort(m_Games.begin(), m_Games.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value("name").toString().compare(b.toMap().value("name").toString(), Qt::CaseInsensitive) < 0;
    });

    m_Tags = tagCounts.keys();
    std::sort(m_Tags.begin(), m_Tags.end(), [&](const QString& a, const QString& b) { return tagCounts[a] > tagCounts[b]; });

    m_Rows = buildRows();
    m_Meta->lookUpMissing(lookups);
    emit changed();

    if (!m_PendingLaunch.isEmpty()) {
        QString key = keyForName(m_PendingLaunch);
        if (!key.isEmpty() && game(key).value("online").toBool()) {
            m_PendingLaunch.clear();
            emit launchRequested(key);
        }
    }
}

QJsonObject PlayBackend::profileFor(const QString& key) const
{
    QJsonObject profiles = m_Store.value("profiles").toObject();
    QString id = gameStore(key).value("profile").toString(DEFAULT_PROFILE);
    return profiles.value(profiles.contains(id) ? id : DEFAULT_PROFILE).toObject();
}

const PlayBackend::Source* PlayBackend::sourceFor(const QString& key) const
{
    auto it = m_Sources.constFind(key);
    if (it == m_Sources.constEnd() || it->isEmpty()) {
        return nullptr;
    }
    // the PC chosen for this game (or in its profile) if it's awake; else one that's awake; else the first
    QString wanted = gameStore(key).value("pc").toString();
    if (wanted.isEmpty()) {
        QString uuid = profileFor(key).value("pc").toString();
        for (const Source& s : *it) {
            QReadLocker lock(&s.computer->lock);
            if (s.computer->uuid == uuid) wanted = s.pcName;
        }
    }
    for (const Source& s : *it) if (s.pcName == wanted && s.online) return &s;
    for (const Source& s : *it) if (s.running) return &s;
    for (const Source& s : *it) if (s.online) return &s;
    return &it->first();
}

QVariantMap PlayBackend::toMap(const QString& key, const QList<Source>& sources) const
{
    QJsonObject store = gameStore(key);
    QJsonObject meta = m_Meta->entry(key);
    QJsonObject igdb = meta.value("igdb").toObject();
    QJsonObject sgdb = meta.value("sgdb").toObject();
    QJsonObject custom = store.value("art").toObject();
    const Source* source = sourceFor(key);
    QString sourceName = sources.first().app.name;

    auto pick = [&](const QString& kind, QStringList fallbacks) {
        QString url = custom.value(kind).toString();
        if (url.isEmpty()) url = sgdb.value(kind).toString();
        for (const QString& f : fallbacks) if (url.isEmpty()) url = f;
        return m_Meta->local(url);
    };
    QUrl boxArt = m_BoxArtUrls.value(key);

    QVariantMap m;
    m["key"] = key;
    m["sourceName"] = sourceName;
    m["name"] = igdb.value("name").toString(sourceName);
    m["summary"] = igdb.value("summary").toString();
    m["year"] = igdb.value("year").toString();
    m["developer"] = igdb.value("developer").toString();
    QStringList tags;
    for (const QJsonValue& t : igdb.value("tags").toArray()) tags << t.toString();
    m["tags"] = tags;
    m["color"] = colorFor(key);
    m["cover"] = pick("cover", {igdb.value("cover").toString(), boxArt.isValid() ? boxArt.toString() : QString()});
    m["banner"] = pick("banner", {igdb.value("banner").toString()});
    m["logo"] = pick("logo", {});
    m["icon"] = pick("icon", {});
    QStringList shots;
    for (const QJsonValue& s : igdb.value("screenshots").toArray()) shots << m_Meta->local(s.toString());
    m["screenshots"] = shots;
    m["screenshot"] = shots.isEmpty() ? QString() : shots.first();
    m["hasMeta"] = !igdb.isEmpty();

    int minutes = store.value("minutes").toInt();
    qint64 last = store.value("last").toInteger();
    m["playMinutes"] = minutes;
    m["playedText"] = minutes >= 60 ? QString("%1 h").arg(minutes / 60) : (minutes > 0 ? QString("%1 min").arg(minutes) : QString("Never played"));
    m["lastPlayed"] = last;
    m["lastPlayedText"] = ago(last);
    m["firstSeen"] = store.value("firstSeen").toInteger();
    m["progress"] = 0;
    QString lastText = ago(last).toLower();
    QString blurb = minutes > 0 ? QString("%1 played, last %2. ").arg(m["playedText"].toString(), lastText == "today" || lastText == "yesterday" ? lastText : "on " + ago(last))
                                : QString("Not played yet. ");
    QString summary = m["summary"].toString();
    int dot = summary.indexOf(". ");
    m["blurb"] = blurb + (dot > 0 && dot < 220 ? summary.left(dot + 1) : summary.left(220));

    QStringList pcs;
    for (const Source& s : sources) pcs << s.pcName;
    m["pcs"] = pcs;
    m["pc"] = source ? source->pcName : pcs.first();
    m["online"] = source && source->online;
    bool running = false;
    for (const Source& s : sources) running = running || s.running;
    m["running"] = running;

    QJsonObject profile = profileFor(key);
    m["profileId"] = profile.value("id").toString();
    m["profileName"] = profile.value("name").toString();
    m["favourite"] = store.value("favourite").toBool();
    m["hidden"] = store.value("hidden").toBool();
    return m;
}

QVariantList PlayBackend::buildRows() const
{
    QVariantList rows;
    auto row = [&rows](const QString& title, QVariantList games, int min = 1) {
        if (games.size() >= min) rows.append(QVariantMap{{"title", title}, {"games", games.mid(0, 16)}});
    };
    auto by = [](QVariantList list, auto less) {
        std::stable_sort(list.begin(), list.end(), [&](const QVariant& a, const QVariant& b) { return less(a.toMap(), b.toMap()); });
        return list;
    };
    auto filter = [this](auto test) {
        QVariantList out;
        for (const QVariant& g : m_Games) if (test(g.toMap())) out.append(g);
        return out;
    };
    qint64 now = QDateTime::currentSecsSinceEpoch();

    // what you play
    QVariantList played = by(filter([](const QVariantMap& g) { return g["playMinutes"].toInt() > 0; }),
                             [](const QVariantMap& a, const QVariantMap& b) { return a["lastPlayed"].toLongLong() > b["lastPlayed"].toLongLong(); });
    row("Continue playing", played.mid(0, 10));
    row("Favourites", filter([](const QVariantMap& g) { return g["favourite"].toBool(); }));

    // your tags, weighted by play time: "Because you play role-playing games"
    QMap<QString, double> weight;
    for (const QVariant& v : played) {
        QVariantMap g = v.toMap();
        for (const QString& t : g["tags"].toStringList()) weight[t] += 1 + g["playMinutes"].toInt() / 60.0;
    }
    QStringList top = weight.keys();
    std::sort(top.begin(), top.end(), [&](const QString& a, const QString& b) { return weight[a] > weight[b]; });
    QStringList shownTags;
    for (const QString& tag : top.mid(0, 2)) {
        QVariantList games = by(filter([&](const QVariantMap& g) { return g["tags"].toStringList().contains(tag); }),
                                [](const QVariantMap& a, const QVariantMap& b) { return a["playMinutes"].toInt() < b["playMinutes"].toInt(); });
        QString words = tag.toLower();
        if (!words.endsWith("s") && !words.contains("co-op") && !words.contains("open world")) words += " games";
        row("Because you play " + words, games, 3);
        shownTags << tag;
    }

    row("New in your library", by(filter([now](const QVariantMap& g) {
        return g["playMinutes"].toInt() == 0 && now - g["firstSeen"].toLongLong() < 14 * 86400;
    }), [](const QVariantMap& a, const QVariantMap& b) { return a["firstSeen"].toLongLong() > b["firstSeen"].toLongLong(); }), 2);
    row("Not played in a while", by(filter([now](const QVariantMap& g) {
        return g["playMinutes"].toInt() > 0 && now - g["lastPlayed"].toLongLong() > 30 * 86400;
    }), [](const QVariantMap& a, const QVariantMap& b) { return a["playMinutes"].toInt() > b["playMinutes"].toInt(); }), 2);
    row("Not played yet", filter([](const QVariantMap& g) { return g["playMinutes"].toInt() == 0; }), 2);

    // a few of the library's own tags
    for (const QString& tag : m_Tags) {
        if (shownTags.size() >= 6) break;
        if (shownTags.contains(tag)) continue;
        QVariantList games = filter([&](const QVariantMap& g) { return g["tags"].toStringList().contains(tag); });
        if (games.size() >= 3) {
            row(tag, games, 3);
            shownTags << tag;
        }
    }
    row("All games", m_Games);
    return rows;
}

QVariantList PlayBackend::search(const QString& text, const QStringList& tags) const
{
    QString needle = keyOf(text);
    QVariantList out;
    for (const QVariant& v : m_Games) {
        QVariantMap g = v.toMap();
        if (!needle.isEmpty() && !g["key"].toString().contains(needle) && !keyOf(g["name"].toString()).contains(needle)) continue;
        QStringList gameTags = g["tags"].toStringList();
        bool all = std::all_of(tags.begin(), tags.end(), [&](const QString& t) { return gameTags.contains(t); });
        if (all) out.append(g);
    }
    return out;
}

QVariantMap PlayBackend::game(const QString& key) const
{
    for (const QVariant& v : m_Games) if (v.toMap()["key"] == key) return v.toMap();
    for (const QVariant& v : m_Hidden) if (v.toMap()["key"] == key) return v.toMap();
    return {};
}

QString PlayBackend::keyForName(const QString& name) const
{
    QString key = keyOf(name);
    if (m_Sources.contains(key)) return key;
    for (const QVariant& v : m_Games) {
        QVariantMap g = v.toMap();
        if (keyOf(g["name"].toString()) == key) return g["key"].toString();
    }
    return QString();
}

QVariantList PlayBackend::pcs() const
{
    QVariantList out;
    for (NvComputer* computer : m_Computers->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (computer->pairState == NvComputer::PS_PAIRED) {
            out.append(QVariantMap{{"name", computer->name}, {"uuid", computer->uuid}, {"online", computer->state == NvComputer::CS_ONLINE}});
        }
    }
    return out;
}

// --- identify, art, per-game settings -----------------------------------------------------------------

void PlayBackend::identifySearch(const QString& text)
{
    m_Meta->searchIgdb(text, [this](QJsonArray results) {
        QVariantList list = results.toVariantList();
        for (QVariant& v : list) {
            QVariantMap m = v.toMap();
            m["cover"] = m_Meta->local(m["cover"].toString());
            v = m;
        }
        emit identifyResults(list);
    });
}

void PlayBackend::identify(const QString& key, int igdbId) { m_Meta->identify(key, igdbId); }
void PlayBackend::identifyNone(const QString& key) { m_Meta->identifyNone(key); }

void PlayBackend::artSearch(const QString& key, const QString& kind)
{
    QVariantMap g = game(key);
    QString current = g.value(kind).toString();
    m_Meta->searchArt(key, g.value("name").toString(), kind, [this, kind, current](QJsonArray results) {
        QVariantList list;
        for (const QJsonValue& v : results) {
            QVariantMap m = v.toObject().toVariantMap();
            m["inUse"] = !current.isEmpty() && (m_Meta->local(m["url"].toString()) == current);
            list.append(m);
        }
        emit artResults(kind, list);
    });
}

void PlayBackend::setArt(const QString& key, const QString& kind, const QString& url)
{
    QJsonObject art = gameStore(key).value("art").toObject();
    art[kind] = url;
    m_Meta->local(url);  // start downloading it
    setGameStore(key, "art", art);
}

void PlayBackend::resetArt(const QString& key, const QString& kind)
{
    QJsonObject art = gameStore(key).value("art").toObject();
    art.remove(kind);
    setGameStore(key, "art", art);
}

void PlayBackend::setHidden(const QString& key, bool hidden) { setGameStore(key, "hidden", hidden ? QJsonValue(true) : QJsonValue()); }
void PlayBackend::setFavourite(const QString& key, bool favourite) { setGameStore(key, "favourite", favourite ? QJsonValue(true) : QJsonValue()); }
void PlayBackend::setGameProfile(const QString& key, const QString& profileId)
{
    setGameStore(key, "profile", profileId == DEFAULT_PROFILE ? QJsonValue() : QJsonValue(profileId));
}
void PlayBackend::setGamePc(const QString& key, const QString& pcName) { setGameStore(key, "pc", pcName); }

// --- profiles and keys --------------------------------------------------------------------------------

QVariantList PlayBackend::profiles() const
{
    QJsonObject profiles = m_Store.value("profiles").toObject();
    QJsonObject games = m_Store.value("games").toObject();
    QVariantList out;
    QStringList ids = profiles.keys();
    std::sort(ids.begin(), ids.end(), [](const QString& a, const QString& b) {
        return a == DEFAULT_PROFILE || (b != DEFAULT_PROFILE && a < b);
    });
    for (const QString& id : ids) {
        QVariantMap p = profiles.value(id).toObject().toVariantMap();
        int count = 0;
        for (const QVariant& v : m_Games) {
            QString pid = games.value(v.toMap()["key"].toString()).toObject().value("profile").toString(DEFAULT_PROFILE);
            if (pid == id || (!profiles.contains(pid) && id == DEFAULT_PROFILE)) count++;
        }
        p["games"] = count;
        out.append(p);
    }
    return out;
}

QString PlayBackend::saveProfile(const QVariantMap& profile)
{
    QJsonObject profiles = m_Store.value("profiles").toObject();
    QString id = profile.value("id").toString();
    QJsonObject p;
    if (id.isEmpty() || !profiles.contains(id)) {
        // a new one starts as a copy of Default
        p = profiles.value(DEFAULT_PROFILE).toObject();
        id = QString("p%1").arg(QDateTime::currentMSecsSinceEpoch());
        p["id"] = id;
    }
    else {
        p = profiles.value(id).toObject();
    }
    for (auto it = profile.constBegin(); it != profile.constEnd(); ++it) {
        if (it.key() != "id" && it.key() != "games") p[it.key()] = QJsonValue::fromVariant(it.value());
    }
    profiles[id] = p;
    m_Store["profiles"] = profiles;
    m_SaveTimer.start();
    rebuild();
    return id;
}

void PlayBackend::deleteProfile(const QString& id)
{
    if (id == DEFAULT_PROFILE) return;
    QJsonObject profiles = m_Store.value("profiles").toObject();
    profiles.remove(id);
    m_Store["profiles"] = profiles;
    m_SaveTimer.start();
    rebuild();  // its games go back to Default (profileFor falls back)
}

QVariantMap PlayBackend::keys() const
{
    QVariantMap k = m_Store.value("keys").toObject().toVariantMap();
    k["swapButtons"] = m_Prefs->swapFaceButtons;
    if (!k.contains("padIcons")) k["padIcons"] = "auto";
    return k;
}

void PlayBackend::saveKeys(const QVariantMap& changes)
{
    QJsonObject k = m_Store.value("keys").toObject();
    bool lookUpAgain = false;
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        if (it.key() == "swapButtons") {
            m_Prefs->swapFaceButtons = it.value().toBool();
            m_Prefs->save();
            continue;
        }
        if (it.key() != "padIcons" && k.value(it.key()).toString() != it.value().toString()) lookUpAgain = true;
        k[it.key()] = it.value().toString();
    }
    m_Store["keys"] = k;
    m_SaveTimer.start();
    m_Meta->setKeys(k.value("igdbClientId").toString(), k.value("igdbSecret").toString(), k.value("steamGridDbKey").toString());
    m_Input->setIconOverride(k.value("padIcons").toString("auto"));
    if (lookUpAgain) {
        QList<QPair<QString, QString>> all;
        for (auto it = m_Sources.constBegin(); it != m_Sources.constEnd(); ++it) all.append({it.key(), it.value().first().app.name});
        m_Meta->lookUpMissing(all, true);
    }
    emit changed();
}

void PlayBackend::refreshMeta()
{
    QList<QPair<QString, QString>> all;
    for (auto it = m_Sources.constBegin(); it != m_Sources.constEnd(); ++it) all.append({it.key(), it.value().first().app.name});
    m_Meta->lookUpMissing(all, true);
}

// --- streaming ----------------------------------------------------------------------------------------

QVariantMap PlayBackend::streamInfo(const QString& key) const
{
    QJsonObject p = profileFor(key);
    QStringList parts;
    parts << QString("%1p").arg(p.value("height").toInt()) << QString("%1 fps").arg(p.value("fps").toInt());
    QString codec = p.value("codec").toString();
    parts << (codec == "h264" ? "H.264" : codec == "hevc" ? "HEVC" : codec == "av1" ? "AV1" : "Auto codec");
    parts << p.value("name").toString() + " profile";
    return QVariantMap{{"summary", parts.join(" · ")}};
}

Session* PlayBackend::createSession(const QString& key)
{
    const Source* source = sourceFor(key);
    if (source == nullptr) {
        return nullptr;
    }

    // the profile goes into Moonlight's settings for this stream only; streamEnded() puts them back
    QJsonObject p = profileFor(key);
    m_SavedPrefs = QVariantMap{
        {"width", m_Prefs->width}, {"height", m_Prefs->height}, {"fps", m_Prefs->fps}, {"bitrate", m_Prefs->bitrateKbps},
        {"codec", int(m_Prefs->videoCodecConfig)}, {"hdr", m_Prefs->enableHdr}, {"audio", int(m_Prefs->audioConfig)},
        {"mouse", m_Prefs->absoluteMouseMode},
    };
    if (p.value("width").toInt() > 0) {
        m_Prefs->width = p.value("width").toInt();
        m_Prefs->height = p.value("height").toInt();
    }
    if (p.value("fps").toInt() > 0) m_Prefs->fps = p.value("fps").toInt();
    if (p.value("bitrate").toInt() > 0) m_Prefs->bitrateKbps = p.value("bitrate").toInt();
    QString codec = p.value("codec").toString();
    m_Prefs->videoCodecConfig = codec == "h264" ? StreamingPreferences::VCC_FORCE_H264
                              : codec == "hevc" ? StreamingPreferences::VCC_FORCE_HEVC
                              : codec == "av1" ? StreamingPreferences::VCC_FORCE_AV1 : StreamingPreferences::VCC_AUTO;
    m_Prefs->enableHdr = p.value("hdr").toBool();
    QString audio = p.value("audio").toString();
    m_Prefs->audioConfig = audio == "5.1" ? StreamingPreferences::AC_51_SURROUND : audio == "7.1" ? StreamingPreferences::AC_71_SURROUND : StreamingPreferences::AC_STEREO;
    m_Prefs->absoluteMouseMode = p.value("mouse").toString() == "desktop";

    m_StreamKey = key;
    NvApp app = source->app;
    return new Session(source->computer, app, m_Prefs);
}

void PlayBackend::streamStarted(const QString& key)
{
    m_StreamKey = key;
    m_StreamStart = QDateTime::currentSecsSinceEpoch();
    m_Computers->stopPollingAsync();  // like Moonlight: no polling the PCs while streaming
}

void PlayBackend::streamEnded(const QString& key)
{
    if (!m_SavedPrefs.isEmpty()) {
        m_Prefs->width = m_SavedPrefs["width"].toInt();
        m_Prefs->height = m_SavedPrefs["height"].toInt();
        m_Prefs->fps = m_SavedPrefs["fps"].toInt();
        m_Prefs->bitrateKbps = m_SavedPrefs["bitrate"].toInt();
        m_Prefs->videoCodecConfig = StreamingPreferences::VideoCodecConfig(m_SavedPrefs["codec"].toInt());
        m_Prefs->enableHdr = m_SavedPrefs["hdr"].toBool();
        m_Prefs->audioConfig = StreamingPreferences::AudioConfig(m_SavedPrefs["audio"].toInt());
        m_Prefs->absoluteMouseMode = m_SavedPrefs["mouse"].toBool();
        m_SavedPrefs.clear();
    }
    if (m_StreamStart > 0 && key == m_StreamKey) {
        qint64 now = QDateTime::currentSecsSinceEpoch();
        int minutes = int((now - m_StreamStart + 30) / 60);
        QJsonObject g = gameStore(key);
        setGameStore(key, "minutes", g.value("minutes").toInt() + minutes);
        setGameStore(key, "last", now);
    }
    m_StreamStart = 0;
    m_StreamKey.clear();
    m_Computers->startPolling();

    // what the in-game menu asked for
    PlayMenu::ExitAction action = PlayMenu::takeExitAction();
    if (action == PlayMenu::ExitStopGame) {
        const Source* source = sourceFor(key);
        if (source != nullptr) {
            m_Computers->quitRunningApp(source->computer);
        }
    }
    else if (action == PlayMenu::ExitBackToWork) {
        QTimer::singleShot(300, this, &PlayBackend::backToDot);
    }
}

QString PlayBackend::clipboard() const
{
    return QGuiApplication::clipboard()->text().trimmed();
}

void PlayBackend::backToDot()
{
    save();
    QCoreApplication::quit();
}
