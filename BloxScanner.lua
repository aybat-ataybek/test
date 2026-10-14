--[[






      █████╗  ██╗   ██╗ ██████╗   █████╗  ████████╗
     ██╔══██╗ ╚██╗ ██╔╝ ██╔══██╗ ██╔══██╗ ╚══██╔══╝
     ███████║  ╚████╔╝  ██████╔╝ ███████║    ██║
     ██╔══██║   ╚██╔╝   ██╔══██╗ ██╔══██║    ██║
     ██║  ██║    ██║    ██████╔╝ ██║  ██║    ██║
     ╚═╝  ╚═╝    ╚═╝    ╚═════╝  ╚═╝  ╚═╝    ╚═╝







]]
-- ===== Your settings (everything else is in DEFAULTS below) =====
getgenv()._anti_reportabuse = false
getgenv()._anti_robux_prompt = false
getgenv()._whitelist = {
    "roblox.com",
    "rbxcdn.com",
}

-- Scripts you trust, listed by the URL you pass to game:HttpGet.
-- Put the URL as a string. Do NOT write loadstring(...)() here: that would
-- run the script right now, before the scanner is loaded.
getgenv()._Scripts_whitelist = {
    "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source",
}

-- Icon: a direct link to a PNG/JPEG, or an asset id such as
-- "rbxassetid://83768500686029". If a link fails, that asset id is used.
getgenv()._icon_asset = "https://kappa.lol/eZqOim"
-- ================================================================

local genv = getgenv()

-- Re-execution guard. If the scanner was unloaded earlier, just switch it back
-- on instead of stacking a second set of hooks on top of the first.
local State = genv.__BloxScannerState
if State then
    if State.alive then
        warn("Already loaded; skipping re-execution to avoid stacking hooks.")
    else
        State.alive = true
        warn("Re-enabled. Hooks from the first run are still installed.")
    end
    return
end
State = { alive = true }
genv.__BloxScannerState = State
genv.__BloxScannerLoaded = true

-- All options live here. Set any of them in getgenv() BEFORE running the
-- script (e.g. getgenv()._anti_afk = false) to override the default.
-- Nothing is written into getgenv(); defaults are resolved on read, so a flag
-- can still be toggled live at any time.
local DEFAULTS = {
    _blockwebhook          = true,
    _sanitize_ip           = true,
    _log_blocks            = true,
    _anti_kick             = true,
    _scan_loadstring       = true,
    _verbose_soft_warnings = false,

    _block_bare_ip         = true,
    _block_relay_hosts     = true,

    _strict_webhook        = false,
    _game_context_aware    = true,
    _warn_actor_risk       = true,
    _anti_afk              = true,

    -- clipboard / disk exfiltration channels
    _block_clipboard_exfil = true,
    _block_writefile_exfil = true,

}

-- Cfg._name -> user value from getgenv(), else the default.
-- After BloxScannerUnload() every lookup returns false, so every check that
-- reads Cfg at call time switches itself off.
local Cfg = setmetatable({}, {
    __index = function(_, key)
        if not State.alive then return false end
        local v = genv[key]
        if v == nil then v = DEFAULTS[key] end
        return v
    end,
})

local realGame = cloneref(game)
local HttpService = cloneref(game:GetService("HttpService"))
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Market = game:GetService("MarketplaceService")

local function safeClone(fn, fallback)
    if type(clonefunction) == "function" and type(fn) == "function" then
        local ok, cloned = pcall(clonefunction, fn)
        if ok and type(cloned) == "function" then
            return cloned
        end
    end
    return fallback or fn
end

local sfind  = safeClone(string.find)
local slower = safeClone(string.lower)
local smatch = safeClone(string.match)
local gsub   = safeClone(string.gsub)
local rnd    = safeClone(math.random)

local _pcall   = safeClone(pcall)
local _pairs   = safeClone(pairs)
local _ipairs  = safeClone(ipairs)
local _type    = safeClone(type)
local _tostring = safeClone(tostring)
local _warn    = safeClone(warn)

local COOKIE_SIG = "warning:-do-not-share-this."

local function urlDecode(s)
    if type(s) ~= "string" then return s end
    local ok, out = pcall(function()
        return (gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
    end)
    return ok and out or s
end

local function getHost(url)
    if type(url) ~= "string" then return "" end
    local rest = gsub(url, "^%w[%w%+%.%-]*://", "")
    local authority = smatch(rest, "^([^/?#]+)") or rest
    authority = smatch(authority, "@(.+)$") or authority
    local host = smatch(authority, "^([^:]+)") or authority
    host = gsub(host, "%.$", "")
    return slower(host)
end

local function hostMatches(host, suffix)
    return host == suffix
        or (#host > #suffix and host:sub(-(#suffix + 1)) == "." .. suffix)
end

local function isWhitelisted(host)
    if not host or host == "" then return false end
    for _, w in ipairs(Cfg._whitelist or {}) do
        w = slower(w)
        if hostMatches(host, w) then
            return true
        end
    end
    return false
end

local function fakeIPv4()
    local a = rnd(1, 223); if a == 127 then a = 128 end
    return ("%d.%d.%d.%d"):format(a, rnd(0, 255), rnd(0, 255), rnd(1, 254))
end

local function fakeIPv6()
    return ("fd00:%x:%x:%x:%x:%x:%x:%x"):format(
        rnd(0, 0xffff), rnd(0, 0xffff), rnd(0, 0xffff), rnd(0, 0xffff),
        rnd(0, 0xffff), rnd(0, 0xffff), rnd(0, 0xffff)
    )
end

local function getCallingScriptName()
    if type(getcallingscript) ~= "function" then
        return "unknown (getcallingscript unavailable)"
    end
    local ok, scr = pcall(getcallingscript)
    if not ok or not scr then return "unknown" end
    local nameOk, fullName = pcall(function() return scr:GetFullName() end)
    if nameOk and fullName then return fullName end
    local n2ok, n2 = pcall(function() return scr.Name end)
    if n2ok and n2 then return tostring(n2) end
    return "unknown"
end

local function isCallFromRealGameScript()
    if type(getcallingscript) ~= "function" then return false end
    local ok, scr = pcall(getcallingscript)
    if not ok or not scr then return false end
    local descOk, isDesc = pcall(function() return scr:IsDescendantOf(game) end)
    return descOk and isDesc == true
end

local BLACKLIST = {
    "grabify", "iplogger", "cliip", "blasze", "stopify", "goo.by", "2no.co",
    "yip.su", "leakix", "spylogger", "ip-tracker", "ip-track", "ip-grab",
    "ip-collect", "ip-sniff", "ip-harvest", "ip-capture", "ip-gather",
    "ip-api", "ipify", "apiip", "ipwho", "ipinfo", "ipgeolocation", "ipdata",
    "ipapi", "ipstack", "ip2location", "maxmind", "db-ip", "country.is",
    "ipxapi", "radar", "whoisxmlapi", "geoapify", "iplocate", "iptrackertool",
    "api-ninjas", "apifreaks", "geo.ipify", "findip", "freeipapi", "neutrinoapi",
    "hackertarget", "api.ip.sb", "ipinfodb", "getgeoapi", "geoplugin", "ipregistry",
    "abstractapi", "extreme-ip-lookup", "geolocation-db", "checkip.amazonaws",
    "api.myip", "wtfismyip", "icanhazip", "ifconfig", "ident.me", "httpbin.org",
    "abuseipdb", "virustotal", "otx.alienvault", "threatcrowd", "urlscan",
    "whatismyipaddress", "myip.ms", "ip-detect", "ipchicken", "ip-address.org",
    "ip-score", "ipqualityscore", "scamalytics", "ipscore", "ipintel",
    "ipblacklist", "dnslytics", "viewdns", "yougetsignal", "iplocation.net",
    "geotargeting", "geobytes", "geocode", "maps.googleapis",
    "nominatim.openstreetmap", "ipvigilante", "ip-geolocation.io", "ip-api.io",
    "ip-info.io", "ip-lookup.net", "ip-details.com", "ip-tracker.org",
    "iplogger.com.ua", "iplogger.org.ua", "iplogger.net", "ip-logger.com",
    "logip.net", "trackip.net", "ip-tracker.net", "ipgrabber", "ipgraber",
    "iplis.ru", "iplog.co", "maper.info", "ps3cfw.com", "wl.gl", "bc.ax",
    "ed.tc", "ezstat.ru", "02ip.ru", "browserleaks", "whoer", "ipleak",
    "canarytokens", "roproxy",
    "roware.space", "globalcheats.cc", "darkscripts", "egorikusa",
    "hookbin", "pipedream", "webhook-test.com",
    "webhook.site", "webhook.in", "hook.io",
    "pushover.net", "ntfy.sh", "gotify.net", "matrix.org",
    "requestbin", "leancoding", "beeceptor", "requestcatcher", "run.mocky.io",
}

local SuspiciousTLDs = { "tk", "ml", "ga", "cf", "gq" }

local BLACKLIST_LABEL_SUBSTRING = {
    "grabify", "iplogger", "ip-logger", "spylogger", "ipgrabber", "ipgraber",
    "iploggger", "blasze", "canarytoken", "webhook-test", "requestbin",
    "beeceptor", "requestcatcher", "hookbin", "pipedream", "webhook.site",
    "egorikusa", "darkscripts", "globalcheats", "roware",
}

local EXACT_DOMAIN_SET = {
    ["5.gp"] = true,
    ["7.ly"] = true,
    ["adf.ly"] = true,
    ["adfly-bot.online"] = true,
    ["adfoc.us"] = true,
    ["ahref.tech"] = true,
    ["ajc1.cn"] = true,
    ["alanlindsay.net"] = true,
    ["ampnode.host"] = true,
    ["anonfiles.download"] = true,
    ["anonymousforum.pw"] = true,
    ["aruljohn.com"] = true,
    ["asianrbtrade.net"] = true,
    ["atharori.net"] = true,
    ["barefoot.pics"] = true,
    ["bathtub.pics"] = true,
    ["battlė.net"] = true,
    ["bbcbloggers.co.uk"] = true,
    ["bbcnews.today"] = true,
    ["bc.vc"] = true,
    ["bit.do"] = true,
    ["bitly-bot.com"] = true,
    ["biturl.io"] = true,
    ["bmwforum.co"] = true,
    ["boot4free.com"] = true,
    ["booter.icu"] = true,
    ["bootyou.net"] = true,
    ["bucks.as"] = true,
    ["bvog.com"] = true,
    ["catsnthing.com"] = true,
    ["catsnthings.fun"] = true,
    ["cheapcinema.club"] = true,
    ["cloudfsx.com"] = true,
    ["cnyc99.com"] = true,
    ["community.hackersclub.net"] = true,
    ["crabrave.pw"] = true,
    ["critical-boot.com"] = true,
    ["csgopot.zone"] = true,
    ["cubeupload.xyz"] = true,
    ["cur.lv"] = true,
    ["curiouscat.club"] = true,
    ["cutt.ly"] = true,
    ["cyberh1.xyz"] = true,
    ["dank.host"] = true,
    ["datasig.io"] = true,
    ["datauth.io"] = true,
    ["dateing.club"] = true,
    ["ddos.city"] = true,
    ["deviantartt.ga"] = true,
    ["deviantartt.ml"] = true,
    ["discordcrypt.xyz"] = true,
    ["discörd.com"] = true,
    ["disçordapp.com"] = true,
    ["disċordapp.com"] = true,
    ["downthe.design"] = true,
    ["dr.tl"] = true,
    ["dropbox.desi"] = true,
    ["dropboxx.cf"] = true,
    ["dropboxx.ga"] = true,
    ["dropboxx.lm"] = true,
    ["dxrbc.cn"] = true,
    ["exec-true.eu"] = true,
    ["exploit-db.xyz"] = true,
    ["files.uploads.ws"] = true,
    ["foot.wiki"] = true,
    ["fortnight.space"] = true,
    ["fortnite-stats.site"] = true,
    ["fortnitechat.site"] = true,
    ["fotocerdas.com"] = true,
    ["freeanonymous.host"] = true,
    ["freebooter.pro"] = true,
    ["freegiftcards.co"] = true,
    ["fuglekos.com"] = true,
    ["gamer.hair"] = true,
    ["gamer.tattoo"] = true,
    ["gamergirl.pro"] = true,
    ["gameskeys.shop"] = true,
    ["gaming-at-my.best"] = true,
    ["gamingfun.me"] = true,
    ["go.budurl.co"] = true,
    ["gtadb.net"] = true,
    ["gyazo.nl"] = true,
    ["gyazoo.ga"] = true,
    ["gyazoo.xyz"] = true,
    ["hackernews.online"] = true,
    ["hackforu.ms"] = true,
    ["hackfȯrums.com"] = true,
    ["hackfȯrums.net"] = true,
    ["hbotv.co"] = true,
    ["hdblog.tech"] = true,
    ["headshot.monster"] = true,
    ["hondachat.com"] = true,
    ["hostingonline.desi"] = true,
    ["hs.vc"] = true,
    ["hwhssc.cn"] = true,
    ["i.imger.me"] = true,
    ["iany.pl"] = true,
    ["ikwyd.com"] = true,
    ["imagehost.pics"] = true,
    ["imageshack.ml"] = true,
    ["imageshare.best"] = true,
    ["imagevault.cloud"] = true,
    ["imger.me"] = true,
    ["imghost.pics"] = true,
    ["imgurl.us"] = true,
    ["imgúr.com"] = true,
    ["ip-puller.com"] = true,
    ["ip-trap.com"] = true,
    ["ip.jlynx.net"] = true,
    ["ipddoser.xyz"] = true,
    ["iplo.ru"] = true,
    ["ipsnatcher.com"] = true,
    ["joinmy.site"] = true,
    ["l-imgur.pl"] = true,
    ["leakforum.ga"] = true,
    ["linkify.me"] = true,
    ["linkit.cf"] = true,
    ["login.anal-porn.info"] = true,
    ["lovebird.guru"] = true,
    ["maifile.cn"] = true,
    ["mailble.com"] = true,
    ["mapper.info"] = true,
    ["massive.boats"] = true,
    ["massive.mom"] = true,
    ["media.appspot.com"] = true,
    ["minecraft-skins.xyz"] = true,
    ["minecräft.com"] = true,
    ["mjzssc.cn"] = true,
    ["my-alts.eu"] = true,
    ["my.su"] = true,
    ["myiptest.com"] = true,
    ["mymassive.store"] = true,
    ["mymassive.top"] = true,
    ["mymassive.yachts"] = true,
    ["myprivate.pics"] = true,
    ["networkstresser.com"] = true,
    ["nnmssc.cn"] = true,
    ["noodshare.pics"] = true,
    ["orboot.pw"] = true,
    ["orcahub.com"] = true,
    ["otherhalf.life"] = true,
    ["ouo.io"] = true,
    ["oxystress.eu"] = true,
    ["panel.teamspeak.bz"] = true,
    ["parlament.usa.cc"] = true,
    ["paypal.sellbitcoins.com"] = true,
    ["photovault.pics"] = true,
    ["pichost.pics"] = true,
    ["picshost.pics"] = true,
    ["plz.life"] = true,
    ["postimage.co"] = true,
    ["printscr.ga"] = true,
    ["privatexmpp.me"] = true,
    ["prntsc.cf"] = true,
    ["progaming.monster"] = true,
    ["proxyfill.co"] = true,
    ["publicwiki.m"] = true,
    ["publicwiki.me"] = true,
    ["quickmessage.io"] = true,
    ["quickmessage.us"] = true,
    ["r1p.pw"] = true,
    ["restresser.com"] = true,
    ["rikiki.net"] = true,
    ["rëddït.com"] = true,
    ["sciencefuture.tk"] = true,
    ["screenshare.host"] = true,
    ["screenshare.pics"] = true,
    ["screenshot.best"] = true,
    ["sexy18.webcam"] = true,
    ["shareit.pics"] = true,
    ["shipment.website"] = true,
    ["shorte.st"] = true,
    ["shrekis.life"] = true,
    ["shört.co"] = true,
    ["skidpaste.org"] = true,
    ["skypecracker.xyz"] = true,
    ["skypegrab.net"] = true,
    ["slsh.us"] = true,
    ["snipe.blue"] = true,
    ["soo.gd"] = true,
    ["spoofing.host"] = true,
    ["spottyfly.com"] = true,
    ["spötify.com"] = true,
    ["starbucks.bio"] = true,
    ["starbucksisbadforyou.com"] = true,
    ["starbucksiswrong.com"] = true,
    ["steamtools.co"] = true,
    ["stock-images.0o.si"] = true,
    ["stonks.boats"] = true,
    ["stonks.fun"] = true,
    ["strawpoll.ga"] = true,
    ["strawpolll.ga"] = true,
    ["stresser.science"] = true,
    ["sugma.mom"] = true,
    ["särahah.eu"] = true,
    ["särahah.pl"] = true,
    ["sĸype.com"] = true,
    ["taveo.net"] = true,
    ["thisdomainislong.lol"] = true,
    ["tigercore.eu"] = true,
    ["tiny.cc"] = true,
    ["tldr.ly"] = true,
    ["tnfbc.cn"] = true,
    ["toes.beauty"] = true,
    ["toldyouso.lol"] = true,
    ["toldyouso.pics"] = true,
    ["toolce.cn"] = true,
    ["topcdn.biz"] = true,
    ["topstreaming.us"] = true,
    ["transferfiles.cloud"] = true,
    ["trulove.guru"] = true,
    ["ts3free.top"] = true,
    ["tvshare.co"] = true,
    ["twitch-stats.stream"] = true,
    ["twitte.ga"] = true,
    ["twiţter.com"] = true,
    ["vbooter.org"] = true,
    ["vdos-s.com"] = true,
    ["videoblog.tech"] = true,
    ["viphackforum.xyz"] = true,
    ["viphackforums.xyz"] = true,
    ["watches-my.stream"] = true,
    ["webprofile.me"] = true,
    ["wzurl.me"] = true,
    ["xda-developers.io"] = true,
    ["xda-developers.us"] = true,
    ["xxox.co.uk"] = true,
    ["youramonkey.com"] = true,
    ["yourmy.monster"] = true,
    ["youshouldclick.us"] = true,
    ["youutube.gq"] = true,
    ["yoütu.be"] = true,
    ["yoütübe.co"] = true,
    ["yoütübe.com"] = true,
    ["ythingy.com"] = true,
    ["yum.mom"] = true,
    ["yòutube.com"] = true,
    ["yȯutube.com"] = true,
    ["zjrbc.cn"] = true,
    ["zzb.bz"] = true,
    ["ìṃgur.com"] = true,
    ["ġooģle.com"] = true,
}

local function isExactBlacklisted(host)
    if not host or host == "" then return false end
    if EXACT_DOMAIN_SET[host] then return true end
    local rest = host
    while true do
        local dot = sfind(rest, ".", 1, true)
        if not dot then break end
        rest = rest:sub(dot + 1)
        if rest == "" then break end
        if EXACT_DOMAIN_SET[rest] then return true end
    end
    return false
end

local WebhookPatterns = {
    { "discord.com", "/api/webhooks" },
    { "discordapp.com", "/api/webhooks" },
    { "telegram.org", "/bot" },
    { "api.telegram.org", "/bot" },
    { "hooks.slack.com", "/services" },
    { "slack.com", "/services" },
    { "teams.microsoft.com", "/webhook" },
    { "guilded.gg", "/api/webhooks" },
    { "hooks.hyra.io", "" },
    { "hooks.guilded.gg", "" },
    { "zapier.com", "/hooks" },
    { "make.com", "/webhook" },
    { "n8n.cloud", "" },
    { "automate.io", "" },
    { "integromat.com", "" },
}

local RelayHostSuffixes = {
    "vercel.app", "onrender.com", "koyeb.app", "workers.dev", "deno.dev",
    "replit.dev", "repl.co", "railway.app", "up.railway.app", "glitch.me",
    "fly.dev", "netlify.app", "pages.dev", "cyclic.app", "adaptable.app",
    "herokuapp.com", "trycloudflare.com", "loca.lt", "serveo.net",
    "ngrok.io", "ngrok-free.app", "ngrok.app", "telebit.io", "cloudno.de",
}

local KnownExfilHosts = {
    ["proxykoyeb.onrender.com"] = true,
    ["rubix-scanner.vercel.app"] = true,
    ["proxy-plum-beta.vercel.app"] = true,
}

local SensitiveBodyFields = {

    "roblosec" .. "urity", "getauthticket", "authticket", "auth_ticket",
    ".robloxsecurity", "securitytoken", "x-csrf-token", "csrftoken",
    "cookie", "cookies", "sessionid", "session_id", "refreshtoken",
    "accesstoken", "access_token",

    "clientid", "client_id", "sessionlogid", "playsessionid",
    "hwid", "hardwareid", "machineid", "identityhash",

    "inventory", "backpack_items", "iteminventory", "ownedgamepasses",
    "collectibles", "limiteds", "totalrap", "networth",
}

local BenignBodyFields = {
    "score", "highscore", "high_score", "record", "leaderboard",
    "time", "elapsed", "duration", "kills", "deaths", "wins", "losses",
    "level", "stage", "wave", "round", "checkpoint", "progress",
    "version", "status", "started", "finished", "completed",
}

local function countFieldHits(bodyStr, fields)
    if type(bodyStr) ~= "string" or bodyStr == "" then return 0, nil end
    local bl = bodyStr:lower()

    local presentKeys = {}

    for k in bl:gmatch('"([^"]+)"%s*:') do
        presentKeys[k] = true
    end

    for k in bl:gmatch('[&%?]([%w_%-%.]+)=') do
        presentKeys[k] = true
    end
    for k in bl:gmatch('^([%w_%-%.]+)=') do
        presentKeys[k] = true
    end

    local hits, firstHit = 0, nil
    for _, f in ipairs(fields) do

        if presentKeys[f] then
            hits = hits + 1
            firstHit = firstHit or f
        else

            for k in pairs(presentKeys) do
                if sfind(k, f, 1, true) then
                    hits = hits + 1
                    firstHit = firstHit or f
                    break
                end
            end
        end
    end
    return hits, firstHit
end

local function webhookBodyVerdict(bodyStr)
    local sensitive, which = countFieldHits(bodyStr, SensitiveBodyFields)
    if sensitive > 0 then
        return true, "sensitive field in body: \"" .. tostring(which) ..
                     "\" (total matches: " .. sensitive .. ")"
    end

    return false, nil
end

local LocationFields = {
    "country", "region", "city", "zip", "postal",
    "lat", "latitude", "lon", "longitude", "timezone",
    "isp", "org", "as", "asn", "country_code", "region_code",
    "continent", "continent_code", "ip", "ipaddress", "ip_address",
    "query", "origin", "ipv4", "ipv6", "publicip", "public_ip"
}

local SuspiciousHeaders = {
    "^x%-forwarded%-for", "^x%-real%-ip", "^cf%-connecting%-ip",
    "^x%-client%-ip", "^forwarded$", "^true%-client%-ip",
    "%-ip$", "^ip$", "^ipaddress$", "^ip_address$",
    "^publicip$", "^public_ip$", "^remoteip$", "^remote_ip$"
}

local CodeBlacklistHard = {
    "getcookiesa" .. "sync",
    "roblosecur" .. "ity",
    "webhookrou" .. "ter",
    "getdiscu" .. "ser",
    "cmd" .. ".exe",
    ":50" .. "00/",
    "smallhitswebh" .. "ook",
    "__sab_run_on" .. "ce",
    "stealerst" .. "ock",
}

local CodeBlacklistSoft = {
    "stealer", "stolen", "ratt", "all your items", "linkingservice",
    "grabify", "iplogger", "ipify", "canihazip", "checkip", "externalip",
    "tobi's", "myip", "ipconfig", "trade", "mailbox",
    "discordid",

    "getplayers()) do", "for _, plr in pairs(game.players",
    "discord.com/api/webhooks", "discordapp.com/api/webhooks",
}

local CodeSignaturePatterns = {
    { pattern = "webhook%s*=%s*[\"']", label = "webhook assignment", hard = false },
    { pattern = "%d+%.%d+%.%d+%.%d+:%d+/", label = "raw IP:port URL", hard = false },
}

local ENV_INJECTION_MARKERS = {
    "get" .. "fenv(",
    "_g" .. "." .. "scan",
    "_g" .. "." .. "join",
    "fenv" .. "." .. "webhook",
    "genv" .. "." .. "webhook",

    "genv" .. "." .. "scripturl",
    "fenv" .. "." .. "scripturl",
    "starscripts" .. "config",
    "genv" .. "." .. "discordid",
    "fenv" .. "." .. "username",
}

local isBlocked
local lastWebhookReason = nil

local GameContextWords = {}

do
    local ok = pcall(function()
        local name = ""
        pcall(function()
            local info = Market and Market:GetProductInfo(realGame.PlaceId)
            if info and info.Name then name = tostring(info.Name) end
        end)
        if name == "" then

            pcall(function() name = tostring(realGame.Name or "") end)
        end
        name = name:lower()

        local forgivable = {
            "steal", "stealer", "stealing", "brainrot", "trade", "trading",
            "rob", "robbery", "heist", "grab", "snatch", "loot", "mailbox",
            "murder", "kill", "hack", "obby", "simulator", "tycoon", "pet",
        }
        for _, w in ipairs(forgivable) do
            if sfind(name, w, 1, true) then
                GameContextWords[w] = true
            end
        end
        if next(GameContextWords) ~= nil and Cfg._log_blocks then
            local list = {}
            for w in pairs(GameContextWords) do list[#list + 1] = w end
            warn(("Game context \"%s\": the words {%s} are not treated as evidence in this game.")
                 :format(name, table.concat(list, ", ")))
        end
    end)
    if not ok then GameContextWords = {} end
end

local function isForgivenByGameContext(word)
    if not Cfg._game_context_aware then return false end
    return GameContextWords[word:lower()] == true
end

local DEFAULT_ICON_ASSET = "rbxassetid://83768500686029"
local ICON_FOLDER = "BloxScanner"

-- Captured now, before request/writefile get wrapped further down.
local rawRequest = http_request or (syn and syn.request) or request

local iconCache = {}    -- url -> asset string, or false if loading failed
local iconPending = {}  -- url -> true while a download is in flight

local function ensureFolder(path)
    pcall(function()
        if not isfolder(path) then
            makefolder(path)
        end
    end)
end

-- Roblox ImageLabel only understands PNG and JPEG, so anything else
-- (an HTML page, WebP, GIF) is rejected instead of written to disk.
local function imageExtension(data)
    if type(data) ~= "string" or #data < 12 then return nil end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
    if data:sub(1, 3) == "\255\216\255" then return "jpg" end
    return nil
end

-- Short stable file name for a URL.
local function urlKey(url)
    local h = 5381
    for i = 1, #url do h = (h * 33 + url:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function toAsset(path)
    local f = getcustomasset or getsynasset or (syn and syn.crypt and syn.crypt.customasset)
    if not f then return nil end
    local ok, asset = pcall(f, path)
    if ok and type(asset) == "string" and asset ~= "" then return asset end
    return nil
end

-- URL -> file in ./workspace/BloxScanner -> getcustomasset(). Runs once per
-- URL per session; the result is cached. Returns nil on any failure.
local function downloadImage(url)
    if iconPending[url] then
        local t0 = os.clock()
        while iconPending[url] and os.clock() - t0 < 8 do task.wait() end
    end
    local cached = iconCache[url]
    if cached ~= nil then return cached or nil end

    iconPending[url] = true
    local result = false

    local ok = pcall(function()
        if type(isBlocked) == "function" and isBlocked(url, nil, nil, false) then
            warn("downloadImage: URL blocked by filter, icon not loaded: " .. tostring(url))
            return
        end
        if not rawRequest then return end

        local reqOk, res = pcall(rawRequest, { Url = url, Method = "GET" })
        local body = reqOk and type(res) == "table" and res.Body or nil
        local ext = imageExtension(body)
        if not ext then
            warn("downloadImage: the link is not a direct PNG/JPEG image, using the default icon: " .. tostring(url))
            return
        end

        ensureFolder(ICON_FOLDER)
        local path = ICON_FOLDER .. "/icon_" .. urlKey(url) .. "." .. ext
        -- writefile may be wrapped later; use the original so our own image
        -- writes are never second-guessed by the exfiltration guard.
        local w = genv.__BloxScannerOrigWritefile or writefile
        if not pcall(w, path, body) then return end

        result = toAsset(path) or false
    end)

    iconCache[url] = ok and result or false
    iconPending[url] = nil
    return iconCache[url] or nil
end

local CONFIG = {
    SLIDE_IN_TIME = 0.4,
    SLIDE_OUT_TIME = 0.05,
    SCALE_TIME = 0.11,
    SCALE_DOWN = 0.96,
    START_Y = -1,
    END_Y = 59,
    DEFAULT_DURATION = 2,
    BACKGROUND_COLOR = Color3.fromHex("#23262C"),
    TEXT_COLOR = Color3.fromRGB(247, 247, 248),
    WIDTH_OFFSET = -24,
    TITLE_SIZE = 20,
    SUBTITLE_SIZE = 15,
    ICON_SIZE = 40,
    ICON_TEXT_SIZE = 26,
    REMOVE_PREVIOUS = true,
    CORNER_RADIUS = 6,
    MIN_HEIGHT = 55,
    TOAST_HEIGHT_FULL = 77,
    TOAST_HEIGHT_SMALL = 55,
    DEFAULT_ICON = Cfg._icon_asset or DEFAULT_ICON_ASSET,
}

-- If the icon is a link, fetch it in the background now so the first toast
-- does not have to wait for the download.
if type(CONFIG.DEFAULT_ICON) == "string" and CONFIG.DEFAULT_ICON:match("^https?://") then
    task.spawn(downloadImage, CONFIG.DEFAULT_ICON)
end

local currentToast = nil
local _lastToastKey = nil
local _lastToastTime = 0

local function NotifyToast(config)
    config = config or {}

    local dedupKey = tostring(config.title) .. "||" .. tostring(config.content or config.subtitle)
    local now = tick()
    if dedupKey == _lastToastKey and (now - _lastToastTime) < 1 then
        return
    end
    _lastToastKey = dedupKey
    _lastToastTime = now

    if CONFIG.REMOVE_PREVIOUS and currentToast and currentToast.Parent then
        currentToast:Destroy()
    end

    local toastId = "Toast_" .. HttpService:GenerateGUID(false)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = toastId
    screenGui.DisplayOrder = 9
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.AutoLocalize = false
    screenGui.ResetOnSpawn = false
    screenGui.ScreenInsets = Enum.ScreenInsets.None
    screenGui.Parent = CoreGui

    currentToast = screenGui

    local container = Instance.new("TextButton")
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position = UDim2.new(0.5, 0, 0, CONFIG.START_Y)
    container.BackgroundTransparency = 1
    container.Text = ""
    container.Parent = screenGui

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MaxSize = Vector2.new(400, math.huge)
    sizeConstraint.Parent = container

    local bg = Instance.new("Frame")
    bg.BackgroundColor3 = CONFIG.BACKGROUND_COLOR
    bg.BackgroundTransparency = 0
    bg.BorderSizePixel = 0
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS)
    corner.Parent = bg

    local innerFrame = Instance.new("Frame")
    innerFrame.BackgroundTransparency = 1
    innerFrame.Size = UDim2.new(1, 0, 1, 0)
    innerFrame.Parent = bg

    local hList = Instance.new("UIListLayout")
    hList.Padding = UDim.new(0, 12)
    hList.FillDirection = Enum.FillDirection.Horizontal
    hList.SortOrder = Enum.SortOrder.LayoutOrder
    hList.VerticalAlignment = Enum.VerticalAlignment.Center
    hList.Parent = innerFrame

    local msgFrame = Instance.new("Frame")
    msgFrame.BackgroundTransparency = 1
    msgFrame.Size = UDim2.new(1, 0, 1, 0)
    msgFrame.LayoutOrder = 2
    msgFrame.Parent = innerFrame

    local vList = Instance.new("UIListLayout")
    vList.Padding = UDim.new(0, 12)
    vList.SortOrder = Enum.SortOrder.LayoutOrder
    vList.VerticalAlignment = Enum.VerticalAlignment.Center
    vList.Parent = msgFrame

    local textFrame = Instance.new("Frame")
    textFrame.BackgroundTransparency = 1
    textFrame.Size = UDim2.new(1, -48, 0, 0)
    textFrame.AutomaticSize = Enum.AutomaticSize.Y
    textFrame.Parent = msgFrame

    local vList2 = Instance.new("UIListLayout")
    vList2.SortOrder = Enum.SortOrder.LayoutOrder
    vList2.VerticalAlignment = Enum.VerticalAlignment.Center
    vList2.Parent = textFrame

    local title = Instance.new("TextLabel")
    title.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
    title.TextColor3 = CONFIG.TEXT_COLOR
    title.TextSize = CONFIG.TITLE_SIZE
    title.TextWrapped = true
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 0)
    title.AutomaticSize = Enum.AutomaticSize.Y
    title.RichText = true
    title.LayoutOrder = 1
    title.Text = config.title or ""
    title.Parent = textFrame

    local subtitle = Instance.new("TextLabel")
    subtitle.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
    subtitle.TextColor3 = CONFIG.TEXT_COLOR
    subtitle.TextSize = CONFIG.SUBTITLE_SIZE
    subtitle.TextWrapped = true
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.BackgroundTransparency = 1
    subtitle.Size = UDim2.new(1, 0, 0, 0)
    subtitle.AutomaticSize = Enum.AutomaticSize.Y
    subtitle.RichText = true
    subtitle.LayoutOrder = 2
    subtitle.Text = config.content or config.subtitle or ""
    subtitle.Parent = textFrame

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.Parent = innerFrame

    local scaler = Instance.new("UIScale")
    scaler.Scale = 1
    scaler.Parent = container

    local showIcon = config.icon and config.icon ~= ""
    local iconObj

    if showIcon then
        local isUrl = type(config.icon) == "string" and config.icon:match("^https?://")
        local isAsset = type(config.icon) == "string" and (config.icon:match("^rbxassetid://") or config.icon:match("^rbxasset://")) or type(config.icon) == "number"

        if isUrl then
            local asset = downloadImage(config.icon) or DEFAULT_ICON_ASSET
            iconObj = Instance.new("ImageLabel")
            iconObj.Image = asset
            iconObj.BackgroundTransparency = 1
            iconObj.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
            iconObj.LayoutOrder = 1
            iconObj.Parent = innerFrame
        elseif isAsset then
            local id = type(config.icon) == "number" and "rbxassetid://" .. config.icon or config.icon
            iconObj = Instance.new("ImageLabel")
            iconObj.Image = id
            iconObj.BackgroundTransparency = 1
            iconObj.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
            iconObj.LayoutOrder = 1
            iconObj.Parent = innerFrame
        else
            iconObj = Instance.new("TextLabel")
            iconObj.FontFace = Font.new("rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json", Enum.FontWeight.Bold)
            iconObj.Text = config.icon
            iconObj.TextColor3 = CONFIG.TEXT_COLOR
            iconObj.TextSize = CONFIG.ICON_TEXT_SIZE
            iconObj.TextXAlignment = Enum.TextXAlignment.Center
            iconObj.TextYAlignment = Enum.TextYAlignment.Center
            iconObj.BackgroundTransparency = 1
            iconObj.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
            iconObj.LayoutOrder = 1
            iconObj.Parent = innerFrame
        end
    end

    local textOffset = showIcon and -48 or 0
    textFrame.Size = UDim2.new(1, textOffset, 0, 0)

    local hasTitle = title.Text ~= ""
    local hasSubtitle = subtitle.Text ~= ""
    local toastHeight = (hasTitle and hasSubtitle) and CONFIG.TOAST_HEIGHT_FULL or CONFIG.TOAST_HEIGHT_SMALL
    toastHeight = math.max(toastHeight, CONFIG.MIN_HEIGHT)

    container.Size = UDim2.new(1, CONFIG.WIDTH_OFFSET, 0, toastHeight)
    bg.Size = UDim2.new(1, 0, 1, 0)
    innerFrame.Size = UDim2.new(1, 0, 1, 0)
    msgFrame.Size = UDim2.new(1, 0, 1, 0)

    local minHeightConstraint = Instance.new("UISizeConstraint")
    minHeightConstraint.MinSize = Vector2.new(0, CONFIG.MIN_HEIGHT)
    minHeightConstraint.Parent = container

    task.wait()

    local actualHeight = container.AbsoluteSize.Y
    local dynamicShowY = CONFIG.END_Y / 2.818 + (actualHeight / 2)

    container.Position = UDim2.new(0.5, 0, 0, CONFIG.START_Y)

    TweenService:Create(container, TweenInfo.new(CONFIG.SLIDE_IN_TIME, Enum.EasingStyle.Quint), {
        Position = UDim2.new(0.5, 0, 0, dynamicShowY)
    }):Play()

    local function hideToast()
        TweenService:Create(container, TweenInfo.new(CONFIG.SLIDE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 0, CONFIG.START_Y)
        }):Play()
        task.delay(CONFIG.SLIDE_OUT_TIME, function()
            if currentToast == screenGui then currentToast = nil end
            screenGui:Destroy()
        end)
    end

    task.delay(config.duration or CONFIG.DEFAULT_DURATION, function()
        if screenGui and screenGui.Parent then hideToast() end
    end)

    container.MouseButton1Down:Connect(function()
        TweenService:Create(scaler, TweenInfo.new(CONFIG.SCALE_TIME), { Scale = CONFIG.SCALE_DOWN }):Play()
    end)

    container.MouseButton1Up:Connect(function()
        TweenService:Create(scaler, TweenInfo.new(CONFIG.SCALE_TIME), { Scale = 1 }):Play()
    end)

    container.MouseButton1Click:Connect(function()
        hideToast()
        if config.callback then config.callback() end
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(scaler, TweenInfo.new(CONFIG.SCALE_TIME), { Scale = 1 }):Play()
    end)
end

local function logBlock(tag, url)
    if not Cfg._log_blocks then return end
    local source = getCallingScriptName()

    local consoleTitle
    if tag == "STEALER" then
        consoleTitle = "STEALER - BLOCKED"
    elseif tag == "RELAY" then

        consoleTitle = "WEBHOOK RELAY (heuristic) - BLOCKED"
    elseif tag == "BARE_IP" then
        consoleTitle = "RAW IP ENDPOINT - BLOCKED"
    else
        consoleTitle = "IP LOGGER - BLOCKED"
    end

    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ " .. consoleTitle .. " ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("URL : " .. tostring(url))
    warn("Host : " .. getHost(urlDecode(url)))
    warn("Source script : " .. source)
    if lastWebhookReason then
        warn("Reason : " .. lastWebhookReason)
        lastWebhookReason = nil
    end
    warn("╚═════════━━━ • ━━━═════════╝")

    NotifyToast({
        title = consoleTitle,
        content = "Learn more in the console...",
        duration = 5,
        icon = CONFIG.DEFAULT_ICON
    })
end

local function logKick()
    if not Cfg._log_blocks then return end
    local source = getCallingScriptName()
    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ STEALER - BLOCKED ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("Source script : " .. source)
    warn("Reason : a stealer (or other Lua script) attempted to kick you")
    warn("╚═════════━━━ • ━━━═════════╝")

    NotifyToast({
        title = "STEALER - BLOCKED",
        content = "Learn more in the console...",
        duration = 5,
        icon = CONFIG.DEFAULT_ICON
    })
end

local function logReportAbuse()
    if not Cfg._log_blocks then return end
    local source = getCallingScriptName()
    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ REPORTABUSE - BLOCKED ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("Source script : " .. source)
    warn("Reason : script tried to call Players:ReportAbuse() on your behalf")
    warn("╚═════════━━━ • ━━━═════════╝")

    NotifyToast({
        title = "REPORTABUSE - BLOCKED",
        content = "A script tried to file a report using your account. Blocked.",
        duration = 6,
        icon = CONFIG.DEFAULT_ICON
    })
end

local function logRobuxPrompt(methodName, productId, ownerName, price)
    if not Cfg._log_blocks then return end
    local source = getCallingScriptName()
    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ ROBUX PROMPT - BLOCKED ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("Method : " .. tostring(methodName))
    warn("Product ID : " .. tostring(productId))
    warn("Owner : " .. tostring(ownerName))
    warn("Price (Robux) : " .. tostring(price))
    warn("Source script : " .. source)
    warn("Reason : script tried to open a Robux purchase prompt without your input")
    warn("╚═════════━━━ • ━━━═════════╝")

    NotifyToast({
        title = "ROBUX PROMPT - BLOCKED",
        content = "Source: " .. source .. " — details in console.",
        duration = 6,
        icon = CONFIG.DEFAULT_ICON
    })
end

-- Added (point 7): unified logger for clipboard / disk exfiltration
local function logExfil(channel, reason)
    if not Cfg._log_blocks then return end
    local source = getCallingScriptName()
    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ STEALER - BLOCKED ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("Channel : " .. tostring(channel))
    warn("Source script : " .. source)
    warn("Reason : " .. tostring(reason))
    warn("╚═════════━━━ • ━━━═════════╝")

    NotifyToast({
        title = "STEALER - BLOCKED",
        content = tostring(channel) .. " exfiltration blocked. Details in console.",
        duration = 6,
        icon = CONFIG.DEFAULT_ICON
    })
end

-- Added (point 7): hard-signature test for raw credential payloads.
-- Kept deliberately narrow (cookie / auth ticket only) so legitimate
-- clipboard copies and config/image writes are not false-flagged.
local function payloadHasHardCredential(s)
    if type(s) ~= "string" or s == "" then return false, nil end
    local low = slower(s)
    if sfind(low, COOKIE_SIG, 1, true) then return true, "roblox cookie signature" end
    if sfind(low, "roblosecur" .. "ity", 1, true) then return true, "roblox cookie" end
    if sfind(low, "getauthticket", 1, true) or sfind(low, "authticket", 1, true) then
        return true, "auth ticket"
    end
    return false, nil
end

local function hasSuspiciousHeaders(headers)
    if type(headers) ~= "table" then return false end
    for k in pairs(headers) do
        local lk = slower(tostring(k))
        for _, pat in ipairs(SuspiciousHeaders) do
            if smatch(lk, pat) then return true end
        end
    end
    return false
end

local function scanForLocationFields(t, depth)
    depth = depth or 0
    if depth > 4 or type(t) ~= "table" then return false end
    for k, v in pairs(t) do
        for _, field in ipairs(LocationFields) do
            if slower(tostring(k)) == field then return true end
        end
        if type(v) == "table" then
            if scanForLocationFields(v, depth + 1) then return true end
        end
    end
    return false
end

local function bodyLeaksLocationFields(body)
    if type(body) ~= "string" or body == "" then return false end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(decoded) ~= "table" then return false end
    return scanForLocationFields(decoded)
end

isBlocked = function(url, body, headers, isPost)
    if not State.alive then return false, nil end
    if type(url) ~= "string" or url == "" then return false, nil end
    local dUrl = urlDecode(url)
    local host = getHost(dUrl)
    local path = smatch(dUrl, "://[^/]+(/[^?]*)") or ""
    local ul = slower(dUrl)
    local pl = slower(path)
    local bl = slower(type(body) == "string" and urlDecode(body) or "")

    local COOKIE_SIG_WORD_2 = "roblosecur" .. "ity"
    if sfind(ul, COOKIE_SIG, 1, true) or sfind(ul, COOKIE_SIG_WORD_2, 1, true) or
       sfind(bl, COOKIE_SIG, 1, true) or sfind(bl, COOKIE_SIG_WORD_2, 1, true) then
        if not hostMatches(host, "roblox.com") then
            return true, "STEALER"
        end
    end

    if isWhitelisted(host) then
        return false, nil
    end

    if isExactBlacklisted(host) then
        return true, "LOGGER"
    end

    if KnownExfilHosts[host] then
        return true, "STEALER"
    end

    if Cfg._block_bare_ip then
        local a, b, c, d = smatch(host, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        if a then
            a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
            if a <= 255 and b <= 255 and c <= 255 and d <= 255 then

                local isLocal = (a == 127) or (a == 10) or
                                (a == 192 and b == 168) or
                                (a == 172 and b >= 16 and b <= 31)
                if not isLocal then
                    return true, "BARE_IP"
                end
            end
        end
    end

    if Cfg._block_relay_hosts then
        local isRelayHost = false
        for _, suffix in ipairs(RelayHostSuffixes) do
            if hostMatches(host, suffix) then
                isRelayHost = true
                break
            end
        end

        if isRelayHost then

            local shouldBlock, why = webhookBodyVerdict(bl)

            if not shouldBlock and not isPost then
                local qs = pl:match("%?(.*)$")
                if qs then
                    shouldBlock, why = webhookBodyVerdict(qs)
                    if shouldBlock then
                        why = "GET query string → " .. tostring(why)
                    end
                end
            end

            if shouldBlock then
                lastWebhookReason = why
                return true, "RELAY"
            end
            if Cfg._verbose_soft_warnings then
                warn(("Allowed request to relay platform (no sensitive data): %s (%s)")
                     :format(tostring(host), isPost and "POST" or "GET"))
            end
        end
    end

    if Cfg._blockwebhook and isPost then
        for _, pat in ipairs(WebhookPatterns) do
            local hostSuffix, pathSub = pat[1], pat[2]
            local hostOk = hostMatches(host, hostSuffix)
            if hostOk and (pathSub == "" or sfind(pl, pathSub, 1, true)) then

                if Cfg._strict_webhook then

                    return true, "WEBHOOK"
                end

                local shouldBlock, why = webhookBodyVerdict(bl)
                if shouldBlock then
                    lastWebhookReason = why
                    return true, "WEBHOOK"
                end

                if Cfg._verbose_soft_warnings then
                    warn("Allowed webhook (no sensitive data): " .. tostring(host))
                end
            end
        end
    end

    local hostLabels = {}
    for label in host:gmatch("[^%.]+") do
        hostLabels[#hostLabels + 1] = label
    end

    for _, p in ipairs(BLACKLIST) do
        if hostMatches(host, p) then
            return true, "LOGGER"
        end
        for _, label in ipairs(hostLabels) do
            if label == p then
                return true, "LOGGER"
            end
        end
    end

    for _, label in ipairs(hostLabels) do
        for _, p in ipairs(BLACKLIST_LABEL_SUBSTRING) do
            if sfind(label, p, 1, true) then
                return true, "LOGGER"
            end
        end
    end

    for _, tld in ipairs(SuspiciousTLDs) do
        if hostMatches(host, tld) then
            return true, "LOGGER"
        end
    end

    if hasSuspiciousHeaders(headers) then
        return true, "STEALER"
    end

    if bodyLeaksLocationFields(body) then
        return true, "LOGGER"
    end

    return false, nil
end

-- =========================================================================
-- Added (point 6): mask integer / hex IP values.
--
-- Scoped ONLY to values that sit under an IP-context key (ip, ipv4, host,
-- addr, publicip ...). A blanket replacement of any 32-bit integer would
-- destroy Roblox UserIds, scores and timestamps, which fall in the same
-- numeric range — so this stays key-anchored on purpose.
-- =========================================================================
local IP_VALUE_KEYS = {
    "ip", "ipv4", "ipaddress", "ip_address", "publicip", "public_ip",
    "clientip", "client_ip", "remoteip", "remote_ip", "addr", "address",
    "host", "query", "origin",
}

local function intToIPv4(n)
    n = tonumber(n)
    if not n or n < 0 or n > 4294967295 or n ~= math.floor(n) then return nil end
    local a = math.floor(n / 16777216) % 256
    local b = math.floor(n / 65536) % 256
    local c = math.floor(n / 256) % 256
    local d = n % 256
    return a, b, c, d
end

local function looksLikeHostedIPInt(n)
    -- Reject obviously non-IP integers to limit false positives:
    -- very small values and values that decode to reserved/local ranges.
    local a, b = intToIPv4(n)
    if not a then return false end
    if a == 0 or a == 127 or a == 10 then return false end
    if a == 192 and b == 168 then return false end
    if a == 172 and b >= 16 and b <= 31 then return false end
    -- Require the top octet to be a plausible public first octet.
    if a >= 1 and a <= 223 then return true end
    return false
end

local function maskIntHexIPsInKeyedValues(s, replacement)
    if type(s) ~= "string" or s == "" then return s, 0 end
    local changed = 0

    for _, key in ipairs(IP_VALUE_KEYS) do
        -- JSON numeric value:  "ip": 3232235521
        s = s:gsub('("' .. key .. '"%s*:%s*)(%d+)', function(pre, num)
            if #num >= 7 and looksLikeHostedIPInt(num) then
                changed = changed + 1
                return pre .. replacement
            end
            return pre .. num
        end)
        -- JSON hex string value: "ip":"0xC0A80001"
        s = s:gsub('("' .. key .. '"%s*:%s*")(0[xX]%x+)(")', function(pre, hx, post)
            local n = tonumber(hx)
            if n and looksLikeHostedIPInt(n) then
                changed = changed + 1
                return pre .. replacement .. post
            end
            return pre .. hx .. post
        end)
        -- Query-string numeric value:  &ip=3232235521  / ?ip=...
        s = s:gsub('([%?&]' .. key .. '=)(%d+)', function(pre, num)
            if #num >= 7 and looksLikeHostedIPInt(num) then
                changed = changed + 1
                return pre .. replacement
            end
            return pre .. num
        end)
    end

    return s, changed
end

local function sanitizeBody(bodyStr, host)
    if type(bodyStr) ~= "string" or bodyStr == "" then return bodyStr end
    if not Cfg._sanitize_ip then return bodyStr end

    if host and isWhitelisted(host) then return bodyStr end

    local ipv4, ipv6 = fakeIPv4(), fakeIPv6()

    local VersionKeys = {
        "version", "ver", "build", "buildnumber", "build_number",
        "sdk", "sdkversion", "revision", "rev", "release",
        "clientversion", "client_version", "appversion", "app_version",
        "gameversion", "game_version", "placeversion", "schema",
    }
    local stash, stashN = {}, 0
    local work = bodyStr

    for _, key in ipairs(VersionKeys) do

        work = work:gsub('("' .. key .. '"%s*:%s*")([^"]*)(")', function(pre, val, post)
            if val:match("^[%d%.]+$") then
                stashN = stashN + 1

                local token = "VERSTASHTOKEN" .. stashN .. "ENDSTASH"
                stash[token] = val
                return pre .. token .. post
            end
            return pre .. val .. post
        end)
    end

    local out = work:gsub("(%d+)%.(%d+)%.(%d+)%.(%d+)", function(a, b, c, d)
        for _, oct in ipairs({ a, b, c, d }) do
            if #oct > 3 then return nil end
            local n = tonumber(oct)
            if not n or n > 255 then return nil end
        end
        return ipv4
    end)

    local function looksLikeIPv6(s)

        local dcount = select(2, s:gsub("::", ""))
        if dcount > 1 then return false end
        local groups, empty = 0, 0
        for g in s:gmatch("[^:]*") do
            if g == "" then
                empty = empty + 1
            else
                if #g > 4 then return false end
                groups = groups + 1
            end
        end
        if dcount == 0 then

            return groups == 8
        end

        return groups >= 2 and groups < 8
    end

    out = out:gsub("%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?:%x%x?%x?%x?",
        function(m)
            if looksLikeIPv6(m) then return ipv6 end
            return nil
        end)

    out = out:gsub("%x%x?%x?%x?::[%x:]*%x", function(m)
        if looksLikeIPv6(m) then return ipv6 end
        return nil
    end)

    -- Added (point 6): mask integer / hex IPs that sit under IP-context keys.
    out = maskIntHexIPsInKeyedValues(out, ipv4)

    if stashN > 0 then
        for token, val in pairs(stash) do
            out = out:gsub(token, val)
        end
    end

    return out
end

-- Source text of every whitelisted script that was downloaded through
-- game:HttpGet. loadstring() skips the scan for exactly this text.
local TrustedSources = {}

local function isTrustedScriptUrl(url)
    if type(url) ~= "string" then return false end
    for _, u in ipairs(Cfg._Scripts_whitelist or {}) do
        if u == url then return true end
    end
    return false
end

local function blockCode(source, reason)
    warn("╔═════════━━━ • ━━━═════════╗")
    warn("[ STEALER - BLOCKED ]")
    warn("Time : " .. os.date("%H:%M:%S"))
    warn("Source script : " .. source)
    warn("Reason : " .. reason)
    warn("╚═════════━━━ • ━━━═════════╝")
    NotifyToast({
        title = "STEALER - BLOCKED",
        content = "Learn more in the console...",
        duration = 5,
        icon = CONFIG.DEFAULT_ICON
    })
    return newcclosure(function() end)
end

if Cfg._scan_loadstring and hookfunction and type(loadstring) == "function" then
    local origLoadstring
    origLoadstring = hookfunction(loadstring, newcclosure(function(code, chunkname)
        if not Cfg._scan_loadstring or TrustedSources[code] then
            return origLoadstring(code, chunkname)
        end
        local codeStr = tostring(code):lower()
        local source = getCallingScriptName()

        for _, word in ipairs(CodeBlacklistHard) do
            if sfind(codeStr, word, 1, true) then
                return blockCode(source, 'hard signature "' .. word .. '"')
            end
        end

        for _, word in ipairs(CodeBlacklistSoft) do
            if sfind(codeStr, word, 1, true) then

                if isForgivenByGameContext(word) then

                else
                    if Cfg._verbose_soft_warnings then
                        warn(("Notice: loadstring from \"%s\" contains suspicious word \"%s\". Code was NOT blocked; this is a warning only.")
                        :format(source, word))
                    end
                    break
                end
            end
        end

        for _, sig in ipairs(CodeSignaturePatterns) do
            local matched = smatch(codeStr, sig.pattern)
            if matched then
                if sig.hard then
                    return blockCode(source, 'pattern signature "' .. sig.label .. '"')
                else
                    if Cfg._verbose_soft_warnings then
                        warn(("Notice: loadstring from \"%s\" contains suspicious pattern \"%s\". Code was NOT blocked; this is a warning only.")
                            :format(source, sig.label))
                    end
                end
            end
        end

        if sfind(codeStr, "webhook", 1, true) then
            for _, marker in ipairs(ENV_INJECTION_MARKERS) do
                if sfind(codeStr, marker, 1, true) then
                    if Cfg._verbose_soft_warnings then
                        warn(("Notice: loadstring from \"%s\" contains a webhook plus marker \"%s\". Code was NOT blocked; this is a warning only.")
                            :format(source, marker))
                    end
                    break
                end
            end
        end

        return origLoadstring(code, chunkname)
    end))
end

local oldNamecall
local namecallHookOk, namecallHookErr = pcall(function()
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = { ... }
    local url = args[1]
    local body = args[2]

    if method == "HttpGet" or method == "HttpGetAsync" or method == "GetAsync" then
        if isTrustedScriptUrl(url) then
            local result = oldNamecall(self, ...)
            if type(result) == "string" then TrustedSources[result] = true end
            return result
        end
        local blocked, tag = isBlocked(url, nil, nil, false)
        if blocked then
            logBlock(tag, url)
            return ""
        end
        local result = oldNamecall(self, ...)
        if type(result) == "string" then
            local respHost = getHost(urlDecode(url))
            -- Added (point 4): a downloaded chunk can itself be a second-stage
            -- stealer. Refuse the response if it carries a cookie/auth signature,
            -- instead of handing stolen-credential code to loadstring.
            if State.alive and not isWhitelisted(respHost) then
                local low = slower(result)
                if sfind(low, COOKIE_SIG, 1, true)
                   or sfind(low, "roblosecur" .. "ity", 1, true)
                   or sfind(low, "getauthticket", 1, true) then
                    logBlock("STEALER", url)
                    return ""
                end
            end
            return sanitizeBody(result, respHost)
        end
        return result

    elseif method == "GetObjects" then
        if type(url) == "string" and (sfind(url, "http://", 1, true) or sfind(url, "https://", 1, true)) then
            local blocked, tag = isBlocked(url, nil, nil, false)
            if blocked then
                logBlock(tag, url)
                return {}
            end
            if Cfg._verbose_soft_warnings then
                _warn("GetObjects called with an external URL: " .. _tostring(url))
            end
        end
        return oldNamecall(self, ...)

    elseif method == "HttpPost" or method == "HttpPostAsync" or method == "PostAsync" then
        local blocked, tag = isBlocked(url, body, nil, true)
        if blocked then
            logBlock(tag, url)
            return ""
        end
        return oldNamecall(self, ...)

    elseif method == "RequestAsync" and type(url) == "table" then
        local reqUrl = url.Url or url.url
        local reqBody = url.Body or url.body
        local reqHeaders = url.Headers or url.headers
        local reqMethod = string.upper(tostring(url.Method or "GET"))
        local isPost = (reqMethod ~= "GET")
        local blocked, tag = isBlocked(reqUrl, reqBody, reqHeaders, isPost)
        if blocked then
            logBlock(tag, reqUrl)
            return {
                Success = false,
                StatusCode = 403,
                StatusMessage = "Blocked",
                Body = "",
                Headers = {}
            }
        end
        local result = oldNamecall(self, ...)
        if type(result) == "table" then
            local newResult = {}
            for k, v in pairs(result) do newResult[k] = v end
            if newResult.Body then newResult.Body = sanitizeBody(newResult.Body, getHost(urlDecode(reqUrl))) end
            if newResult.body then newResult.body = sanitizeBody(newResult.body, getHost(urlDecode(reqUrl))) end
            return newResult
        end
        return result

    elseif method == "ReportAbuse" and Cfg._anti_reportabuse and not checkcaller() then
        logReportAbuse()
        return
    end

    return oldNamecall(self, ...)
    end))
end)

if not namecallHookOk then
    warn("CRITICAL: failed to install the __namecall hook (Section 10). Error: " .. tostring(namecallHookErr))
end

local kickHookTarget

local function checkActorEvasionRisk()
    if not Cfg._warn_actor_risk then return end

    local ok = _pcall(function()
        local hasActorSupport = (type(getactors) == "function")
                             or (type(run_on_actor) == "function")
                             or (type(create_comm_channel) == "function")

        local actorCount = 0
        if type(getactors) == "function" then
            local ok2, actors = _pcall(getactors)
            if ok2 and type(actors) == "table" then
                actorCount = #actors
            end
        end

        if actorCount > 0 then

            _warn(("Warning: %d Actor(s) detected in this game. Actors run in "
                .. "separate Lua states, so hooks do not apply inside them and a "
                .. "script running in one can bypass this protection. Be extra "
                .. "careful with scripts here.%s")
                :format(actorCount,
                    hasActorSupport and " (Your executor supports Actor access, so this vector is available here.)" or ""))
        end
    end)
    return ok
end

task.spawn(function()
    task.wait(3)
    _pcall(checkActorEvasionRisk)
end)

if Cfg._anti_kick then
    local kickHookOk, kickHookErr = pcall(function()
        local p = game:GetService("Players").LocalPlayer
        local o = getrawmetatable(game)
        local s = o.__namecall
        local w = newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if m == "Kick" and self == p and Cfg._anti_kick then
                logKick()
                return
            end
            return s(self, ...)
        end)
        setreadonly(o, false)
        o.__namecall = w
        setreadonly(o, true)
        kickHookTarget = w
    end)

    if not kickHookOk then
        warn("Failed to install the anti-kick hook. Error: " .. tostring(kickHookErr))
    end
end

local function wrapExecutorRequest(fn)
    if type(fn) ~= "function" then return fn end
    return function(opts, ...)
        if type(opts) ~= "table" then return fn(opts, ...) end
        local reqUrl = opts.Url or opts.URL or opts.url
        local reqBody = opts.Body or opts.body
        local reqHeaders = opts.Headers or opts.headers
        local reqMethod = string.upper(tostring(opts.Method or opts.method or "GET"))
        local isPost = (reqMethod ~= "GET")
        local blocked, tag = isBlocked(reqUrl, reqBody, reqHeaders, isPost)
        if blocked then
            logBlock(tag, reqUrl)
            return { Success = false, StatusCode = 403, StatusMessage = "Blocked", Body = "", Headers = {} }
        end
        local result = fn(opts, ...)
        if type(result) == "table" then
            local newResult = {}
            for k, v in pairs(result) do newResult[k] = v end
            local respHost = getHost(urlDecode(reqUrl))
            if newResult.Body then newResult.Body = sanitizeBody(newResult.Body, respHost) end
            if newResult.body then newResult.body = sanitizeBody(newResult.body, respHost) end
            return newResult
        end
        return result
    end
end

local HookStatus = {}

local function tryHookGlobal(name, getter, setter)
    local ok, fn = pcall(getter)
    if not ok or type(fn) ~= "function" then
        HookStatus[name] = "не найдена"
        return
    end
    local wrapped = wrapExecutorRequest(fn)
    local applied = pcall(setter, wrapped)
    if not applied then
        HookStatus[name] = "ошибка установки"
        return
    end
    local verifyOk, current = pcall(getter)
    if verifyOk and current == wrapped then
        HookStatus[name] = "ok"
    else
        HookStatus[name] = "не применилось (возможно readonly)"
    end
end

tryHookGlobal("request", function() return request end, function(w) getgenv().request = w; _G.request = w end)
tryHookGlobal("http_request", function() return http_request end, function(w) getgenv().http_request = w; _G.http_request = w end)
tryHookGlobal("syn.request", function() return syn and syn.request end, function(w) syn.request = w end)
tryHookGlobal("Fluxus.request", function() return Fluxus and Fluxus.request end, function(w) Fluxus.request = w end)
tryHookGlobal("KRNL_LOADED.request", function() return KRNL_LOADED and KRNL_LOADED.request end, function(w) KRNL_LOADED.request = w end)

if type(WebSocket) == "table" and type(WebSocket.connect) == "function" then
    local origConnect = WebSocket.connect
    local function newConnect(url, ...)
        local blocked, tag = isBlocked(url, nil, nil, false)
        if blocked then
            logBlock(tag, url)
            return nil
        end
        local sock = origConnect(url, ...)
        if sock and type(sock) == "table" and type(sock.Send) == "function" then
            local origSend = sock.Send
            local function newSend(self, message)
                -- Added (point 5): run the full filter + sanitizer on every
                -- outbound frame, not just a cookie-signature check. A socket is
                -- treated as a POST channel to the connected URL.
                if type(message) == "string" then
                    local blk, btag = isBlocked(url, message, nil, true)
                    if blk then
                        logBlock(btag or "STEALER", url)
                        return
                    end
                    message = sanitizeBody(message, getHost(urlDecode(url)))
                end
                return origSend(self, message)
            end
            pcall(function() sock.Send = newSend end)
        end
        return sock
    end
    pcall(function() WebSocket.connect = newConnect end)
end

-- =========================================================================
-- Added (point 7): guard non-network exfiltration channels.
--
-- Covers clipboard (setclipboard / toclipboard) and disk (writefile).
-- Blocks only on HARD credential signatures (cookie / auth ticket) to keep
-- false positives near zero — legitimate scripts copy text and write config
-- or image files constantly. The script's own PNG writes use the saved
-- original reference (see downloadImage), so they are never affected.
-- =========================================================================
do
    if Cfg._block_clipboard_exfil then
        local clipTargets = {
            { name = "setclipboard",
              get = function() return setclipboard end,
              set = function(w) getgenv().setclipboard = w; _G.setclipboard = w end },
            { name = "toclipboard",
              get = function() return toclipboard end,
              set = function(w) getgenv().toclipboard = w; _G.toclipboard = w end },
        }
        for _, t in ipairs(clipTargets) do
            local ok, fn = pcall(t.get)
            if ok and type(fn) == "function" then
                local orig = fn
                local wrapped = function(data, ...)
                    local bad, why
                    if Cfg._block_clipboard_exfil then bad, why = payloadHasHardCredential(data) end
                    if bad then
                        logExfil("clipboard (" .. t.name .. ")", why)
                        return
                    end
                    return orig(data, ...)
                end
                pcall(t.set, wrapped)
            end
        end
    end

    if Cfg._block_writefile_exfil then
        local ok, origWrite = pcall(function() return writefile end)
        if ok and type(origWrite) == "function" then
            -- Preserve the real function so the script's own image writes bypass
            -- the guard (referenced by downloadImage).
            genv.__BloxScannerOrigWritefile = origWrite
            local wrapped = function(path, data, ...)
                local bad, why
                if Cfg._block_writefile_exfil then bad, why = payloadHasHardCredential(data) end
                if bad then
                    logExfil("writefile", why .. " → " .. tostring(path))
                    return
                end
                return origWrite(path, data, ...)
            end
            pcall(function() getgenv().writefile = wrapped; _G.writefile = wrapped end)
        end
    end
end

local protectedFunctions = {}

if Cfg._anti_reportabuse and type(hookfunction) == "function" then
    local ok, origReportAbuse = pcall(function()
        return hookfunction(Players.ReportAbuse, newcclosure(function(self, ...)
            if Cfg._anti_reportabuse and not checkcaller() then
                logReportAbuse()
                return
            end
            return protectedFunctions.ReportAbuse.orig(self, ...)
        end))
    end)
    if ok then
        protectedFunctions.ReportAbuse = { orig = origReportAbuse, wrapped = Players.ReportAbuse }
    else
        warn("Failed to hook ReportAbuse: " .. tostring(origReportAbuse))
    end
end

if Cfg._anti_robux_prompt and type(hookfunction) == "function" then
    local robuxMethods = {
        "PromptPurchase", "PromptGamePassPurchase", "PromptProductPurchase",
        "PromptBundlePurchase", "PromptPremiumPurchase", "PromptSubscriptionPurchase",
        "PerformPurchase", "PerformPurchaseV2",
    }

    for _, methodName in ipairs(robuxMethods) do
        local hasTarget, target = pcall(function() return Market[methodName] end)
        if hasTarget and type(target) == "function" then
            local ok, origFn = pcall(function()
                return hookfunction(target, newcclosure(function(self, ...)

                    if not Cfg._anti_robux_prompt or checkcaller() or isCallFromRealGameScript() then
                        return protectedFunctions[methodName].orig(self, ...)
                    end

                    local args = { ... }
                    local productId = args[2] or args[1]
                    local ownerName, price = "unknown", "unknown"

                    pcall(function()
                        local info = Market:GetProductInfo(productId)
                        if info then
                            price = info.PriceInRobux or "unknown"
                            if info.CreatorTargetId then
                                local nameOk, n = pcall(function()
                                    return Players:GetNameFromUserIdAsync(info.CreatorTargetId)
                                end)
                                if nameOk then ownerName = n end
                            end
                        end
                    end)

                    logRobuxPrompt(methodName, productId, ownerName, price)
                    return
                end))
            end)
            if ok then
                protectedFunctions[methodName] = { orig = origFn, wrapped = target }
            end
        end
    end
end

if Cfg._anti_afk then
    local antiAfkOk, antiAfkErr = pcall(function()
        local VirtualUser = game:GetService("VirtualUser")
        local plr = game:GetService("Players").LocalPlayer

        if genv.__BloxScannerAntiAfk then
            pcall(function() genv.__BloxScannerAntiAfk:Disconnect() end)
            genv.__BloxScannerAntiAfk = nil
        end

        genv.__BloxScannerAntiAfk = plr.Idled:Connect(function()

            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end)

    if not antiAfkOk then
        warn("Anti-AFK could not be enabled: " .. tostring(antiAfkErr))
    end
end

genv.BloxScannerUnload = function()
    -- Flip the switch every hook reads (Cfg returns false while not alive).
    -- The user's own flags in getgenv() are left untouched, so a re-run
    -- brings the scanner back with the same settings.
    State.alive = false

    if genv.__BloxScannerAntiAfk then
        pcall(function() genv.__BloxScannerAntiAfk:Disconnect() end)
        genv.__BloxScannerAntiAfk = nil
    end

    warn("Unloaded. All checks are now disabled. Run the script again to re-enable, or rejoin to fully remove hooks.")
end
