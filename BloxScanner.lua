

-- :) i love you, thank you for using script

if getgenv().__BloxScannerLoaded then
    warn("Already loaded; skipping re-execution to avoid stacking hooks.")
    return
end
getgenv().__BloxScannerLoaded = true

local function setDefault(key, value)
    if getgenv()[key] == nil then
        getgenv()[key] = value
    end
end

setDefault("_blockwebhook",          true)
setDefault("_sanitize_ip",           true)
setDefault("_log_blocks",            true)
setDefault("_anti_kick",             true)
setDefault("_scan_loadstring",       true)
setDefault("_verbose_soft_warnings", false)

setDefault("_anti_reportabuse",      false)
setDefault("_anti_robux_prompt",     false)

setDefault("_block_bare_ip",         true)
setDefault("_block_relay_hosts",     true)

setDefault("_strict_webhook",        false)
setDefault("_game_context_aware",    true)
setDefault("_warn_actor_risk",       true)

setDefault("_anti_afk",              true)

-- true  = a single device-identifying field (hwid, machineid...) sent to a relay/tunnel host is blocked.
-- false = needs 2+ such fields (key/licence systems send just hwid, so they are allowed with a notice).
setDefault("_strict_identity",       false)

-- v3 options
setDefault("_protect_real_ip",       true)   -- block requests that contain YOUR real IP
setDefault("_fake_real_ip",          false)  -- true = swap your real IP for a decoy instead of blocking (request()/RequestAsync only)
setDefault("_scan_cookie_encodings", true)   -- cookie leaks hidden as hex / base64 / reversed / multi-encoded
setDefault("_block_discord_tokens",  true)
setDefault("_block_jwt",             false)  -- JWT is also used by normal APIs, so off by default
setDefault("_learn_from_responses",  true)   -- block hosts whose response looks like an IP-logger page
setDefault("_c2_scoring",            true)   -- score punycode / tunnel / DGA-looking hosts
setDefault("_protect_filesystem",    true)   -- cookie writes to disk + mass-deletion lockdown
setDefault("_watch_hooks",           true)   -- warn if another script removes our request hooks
setDefault("_guard_restore",         false)  -- hook restorefunction so our hooks cannot be undone (test on your executor first)
setDefault("_restore_prehooked",     false)  -- restorefunction() on request/http_request that were hooked before us

setDefault("_icon_asset", "rbxassetid://83768500686029")

setDefault("_whitelist", {
    "roblox.com", "rbxcdn.com",
})

setDefault("_loadstring_whitelist", {})

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

-- original request function, captured before we wrap anything (used for the one-time own-IP lookup)
local rawRequest = safeClone(
    (type(request) == "function" and request)
    or (type(http_request) == "function" and http_request)
    or (type(syn) == "table" and syn.request)
    or (type(http) == "table" and http.request)
    or (type(fluxus) == "table" and fluxus.request)
    or nil
)

-- Was something hooked before BloxScanner? (only reported in verbose mode: some executors hook internally)
pcall(function()
    local isHooked = (type(isfunctionhooked) == "function" and isfunctionhooked)
                  or (type(ishookedfunction) == "function" and ishookedfunction)
    if not isHooked then return end
    local list = {
        { "request", request }, { "http_request", http_request },
        { "hookfunction", hookfunction }, { "hookmetamethod", hookmetamethod },
        { "loadstring", loadstring }, { "restorefunction", restorefunction },
    }
    for _, it in ipairs(list) do
        if type(it[2]) == "function" then
            local ok, hooked = pcall(isHooked, it[2])
            if ok and hooked then
                if getgenv()._verbose_soft_warnings then
                    warn(("Notice: %s was already hooked before BloxScanner loaded. Another script ran first - load BloxScanner from autoexec."):format(it[1]))
                end
                if getgenv()._restore_prehooked and type(restorefunction) == "function"
                   and (it[1] == "request" or it[1] == "http_request") then
                    pcall(restorefunction, it[2])
                end
            end
        end
    end
end)

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

local function isWhitelisted(host)
    if not host or host == "" then return false end
    for _, w in ipairs(getgenv()._whitelist or {}) do
        w = slower(w)
        if host == w or (#host > #w and host:sub(-(#w + 1)) == "." .. w) then
            return true
        end
    end
    return false
end

-- Hosts that only proxy public Roblox APIs. GET requests to them are allowed
-- (cookie / token checks still apply, and POST is still fully checked).
local READONLY_API_HOSTS = { "roproxy.com" }

local function isReadOnlyApiHost(host)
    for _, s in ipairs(READONLY_API_HOSTS) do
        if host == s or (#host > #s and host:sub(-(#s + 1)) == "." .. s) then
            return true
        end
    end
    return false
end

local noticed = {}
local function noticeOnce(key, msg)
    if noticed[key] then return end
    noticed[key] = true
    if getgenv()._log_blocks then warn(msg) end
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
    "canarytokens",
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

-- extra logger / IP-lookup / lookalike domains
for _, d in ipairs({
    "checkip.amazonaws.com",
    "checkip.dyndns.org",
    "checkip.synology.com",
    "checkip.dns.he.net",
    "myexternalip.com",
    "ip.sb",
    "api.my-ip.io",
    "my-ip.io",
    "whatismyip.com",
    "whatsmyip.net",
    "extreme-ip-check.com",
    "getmyip.co",
    "getmyip.org",
    "ip-whois.io",
    "ipwhois.app",
    "whatismyip.akamai.com",
    "api.myip.com",
    "myip.com",
    "myip.dnsomatic.com",
    "tnx.nl",
    "ip.nux.ro",
    "curlmyip.com",
    "ipecho.net",
    "freegeoip.app",
    "showmyip.com",
    "cmyip.com",
    "ip4.me",
    "l2.io",
    "ip.anysrc.net",
    "ip.chinaz.com",
    "ip.cn",
    "ip.tool.la",
    "ip.taobao.com",
    "geoiptool.com",
    "myip.opendns.com",
    "check-my-ip.net",
    "checkmyip.com",
    "seeip.org",
    "api.seeip.org",
    "ipv4.seeip.org",
    "ipv6.seeip.org",
    "eth0.me",
    "api.bigdatacloud.net",
    "ipfind.io",
    "ip2location-io.com",
    "api.ip2location-io.com",
    "ip.tyk.nu",
    "ip.me",
    "ip.pe.kr",
    "fortnite.club",
    "gamertag.shop",
    "locations.quest",
    "partpicker.shop",
    "shhh.lol",
    "sportshub.bar",
    "location.cyou",
    "mymap.icu",
    "mymap.quest",
    "mapss.icu",
    "map-s.online",
    "crypto-o.click",
    "cryp-o.online",
    "customer.autos",
    "account.beauty",
    "photospace.life",
    "mymassive.pics",
    "photovault.store",
    "imagehub.fun",
    "picturestash.mom",
    "clickthis.photo",
    "sharevault.cloud",
    "picshare.mom",
    "picshare.hair",
    "imagestash.pics",
    "xtube.chat",
    "myprivate.yachts",
    "screensnaps.top",
    "customersupport.click",
    "mypicparade.pics",
    "iptrackeronline.com",
    "tracemyip.com",
    "tracemyip.org",
    "screenshot.click",
    "shorter.me",
    "grabb.site",
    "grabifyicu.com",
    "iplist.ru",
    "cob.soy",
}) do
    EXACT_DOMAIN_SET[d] = true
end

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

-- STRONG: one match is enough to block (credentials / session data).
local StrongBodyFields = {
    "roblosec" .. "urity", "getauthticket", "authticket", "auth_ticket",
    ".robloxsecurity", "securitytoken", "x-csrf-token", "csrftoken",
    "cookie", "cookies", "sessionid", "session_id", "refreshtoken",
    "accesstoken", "access_token",
}

-- WEAK: identify the device / account but are also sent by normal key and
-- licence systems. One match = allowed + notice; two or more = blocked
-- (or one match when getgenv()._strict_identity = true).
local WeakBodyFields = {
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

-- returns: shouldBlock, reason, weakFieldSeen
-- strictWeak = true is used for real webhook endpoints (Discord, Telegram...)
-- where even a single identifying field is suspicious.
local function webhookBodyVerdict(bodyStr, strictWeak)
    local strong, which = countFieldHits(bodyStr, StrongBodyFields)
    if strong > 0 then
        return true, "sensitive field in body: \"" .. tostring(which) ..
                     "\" (total matches: " .. strong .. ")", nil
    end

    local weak, weakWhich = countFieldHits(bodyStr, WeakBodyFields)
    local threshold = (strictWeak or getgenv()._strict_identity) and 1 or 2
    if weak >= threshold then
        return true, "device-identifying field in body: \"" .. tostring(weakWhich) ..
                     "\" (total matches: " .. weak .. ")", nil
    end
    if weak > 0 then
        return false, nil, weakWhich
    end
    return false, nil, nil
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

local Stats = { requests = 0, blocked = 0 }
getgenv().BloxScannerStats = Stats

-- ======================= cookie leak detection (encoded forms) ================
local COOKIE_PREFIX = "_|WARNING:-DO-NOT-SHARE-THIS"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

-- needles that appear inside ANY base64 text containing the cookie, for the 3 possible alignments
local COOKIE_NEEDLES = {}
do
    local dropStart = { [0] = 0, [1] = 2, [2] = 3 }
    for pad = 0, 2 do
        local enc = b64encode(("A"):rep(pad) .. COOKIE_PREFIX)
        enc = enc:gsub("=+$", "")
        local needle = enc:sub(dropStart[pad] + 1, #enc - 2)
        if #needle >= 12 then COOKIE_NEEDLES[#COOKIE_NEEDLES + 1] = needle end
    end
end

local COOKIE_HEX = (COOKIE_PREFIX:gsub(".", function(c) return ("%02x"):format(c:byte()) end)):lower()
local MAX_SCAN_LEN = 400000

local function fullUrlDecode(s)
    local cur = s
    for _ = 1, 4 do
        local nxt = urlDecode(cur)
        if nxt == cur then break end
        cur = nxt
    end
    return cur
end

-- returns a short label of the encoding found, or nil
local function cookieEncodedLeak(str)
    if type(str) ~= "string" or #str < 20 or #str > MAX_SCAN_LEN then return nil end
    local lowered = slower(str)
    if sfind(lowered, COOKIE_SIG, 1, true) then return "plain" end

    local decoded = fullUrlDecode(str)
    if decoded ~= str and sfind(slower(decoded), COOKIE_SIG, 1, true) then return "url-encoded" end

    if sfind(lowered, COOKIE_HEX, 1, true) then return "hex" end
    for _, needle in ipairs(COOKIE_NEEDLES) do
        if sfind(str, needle, 1, true) then return "base64" end
    end
    if sfind(slower(str:reverse()), COOKIE_SIG, 1, true) then return "reversed" end
    return nil
end

-- ======================= token detection (linear, no pattern backtracking) =====
local function tokenLeak(str)
    if type(str) ~= "string" or #str < 30 or #str > MAX_SCAN_LEN then return nil end
    local wantDiscord = getgenv()._block_discord_tokens
    local wantJwt = getgenv()._block_jwt
    if not (wantDiscord or wantJwt) then return nil end
    local checked = 0
    for tok in str:gmatch("[%w_%-%.]+") do
        local len = #tok
        if len >= 30 and len <= 140 then
            checked = checked + 1
            if checked > 400 then break end
            if wantJwt and tok:sub(1, 3) == "eyJ" then
                local a, b, c = smatch(tok, "^([%w_%-]+)%.([%w_%-]+)%.([%w_%-]+)$")
                if a then return "JWT/OAuth token" end
            end
            if wantDiscord then
                local u, t, h = smatch(tok, "^([%w_%-]+)%.([%w_%-]+)%.([%w_%-]+)$")
                if u and #u >= 20 and #u <= 30 and #t >= 5 and #t <= 8 and #h >= 25 and #h <= 40 then
                    return "Discord token"
                end
                if tok:sub(1, 4) == "mfa." and len >= 24 then return "Discord MFA token" end
            end
        end
    end
    return nil
end

local function headersToString(headers)
    if type(headers) ~= "table" then return nil end
    local parts, n = {}, 0
    for k, v in pairs(headers) do
        n = n + 1
        if n > 60 then break end
        parts[#parts + 1] = tostring(k) .. ": " .. tostring(v)
    end
    return table.concat(parts, "\n")
end

-- ======================= your real IP =========================================
local UserIP = nil

local function fetchUserIP()
    if type(rawRequest) ~= "function" then return end
    for _, u in ipairs({ "https://api.ipify.org", "https://icanhazip.com", "https://checkip.amazonaws.com" }) do
        local ok, res = pcall(rawRequest, { Url = u, Method = "GET" })
        if ok and type(res) == "table" and type(res.Body) == "string" then
            local cand = res.Body:gsub("%s+", "")
            if smatch(cand, "^%d+%.%d+%.%d+%.%d+$") or (smatch(cand, "^[%x:]+$") and select(2, cand:gsub(":", "")) >= 2) then
                UserIP = cand
                return
            end
        end
    end
end

if getgenv()._protect_real_ip and rawRequest then
    task.spawn(function() pcall(fetchUserIP) end)
end

local function ipBoundaryOk(str, s, e)
    local before = str:sub(s - 1, s - 1)
    local after = str:sub(e + 1, e + 1)
    if before ~= "" and smatch(before, "[%w%.:]") then return false end
    if after ~= "" and smatch(after, "[%w:]") then return false end
    if after == "." and smatch(str:sub(e + 2, e + 2), "%d") then return false end
    return true
end

local function containsUserIP(str)
    if not UserIP or type(str) ~= "string" or str == "" or #str > MAX_SCAN_LEN then return false end
    local pos = 1
    while true do
        local s, e = sfind(str, UserIP, pos, true)
        if not s then return false end
        if ipBoundaryOk(str, s, e) then return true end
        pos = e + 1
    end
end

local decoyIP
local function swapUserIP(str)
    if not UserIP or type(str) ~= "string" or str == "" or #str > MAX_SCAN_LEN then return str, false end
    decoyIP = decoyIP or ((rnd() < 0.5) and fakeIPv4() or fakeIPv6())
    local out, pos, changed = {}, 1, false
    while true do
        local s, e = sfind(str, UserIP, pos, true)
        if not s then out[#out + 1] = str:sub(pos); break end
        if ipBoundaryOk(str, s, e) then
            out[#out + 1] = str:sub(pos, s - 1)
            out[#out + 1] = decoyIP
            changed = true
        else
            out[#out + 1] = str:sub(pos, e)
        end
        pos = e + 1
    end
    return table.concat(out), changed
end

-- copy of a request options table with url/body/headers replaced (keeps the caller's field names)
local function copyOptsWith(opts, nu, nb, nh)
    local c = {}
    for k, v in pairs(opts) do c[k] = v end
    if nu ~= nil then
        if c.Url ~= nil then c.Url = nu elseif c.URL ~= nil then c.URL = nu else c.url = nu end
    end
    if nb ~= nil then
        if c.Body ~= nil then c.Body = nb else c.body = nb end
    end
    if nh ~= nil then
        if c.Headers ~= nil then c.Headers = nh else c.headers = nh end
    end
    return c
end

-- returns newUrl, newBody, newHeaders, changed
local function swapRealIP(reqUrl, reqBody, reqHeaders)
    local changed = false
    local nu, nb, nh = reqUrl, reqBody, reqHeaders
    if type(reqUrl) == "string" then
        local r, ch = swapUserIP(reqUrl); if ch then nu, changed = r, true end
    end
    if type(reqBody) == "string" then
        local r, ch = swapUserIP(reqBody); if ch then nb, changed = r, true end
    end
    if type(reqHeaders) == "table" then
        local copy, hch = {}, false
        for k, v in pairs(reqHeaders) do
            if type(v) == "string" then
                local r, ch = swapUserIP(v)
                copy[k] = r
                if ch then hch = true end
            else
                copy[k] = v
            end
        end
        if hch then nh, changed = copy, true end
    end
    return nu, nb, nh, changed
end

local function wantFakeIP()
    return getgenv()._protect_real_ip and getgenv()._fake_real_ip and UserIP ~= nil
end

-- ======================= C2 / suspicious infrastructure scoring ================
local function shannonEntropy(s)
    if #s == 0 then return 0 end
    local freq, len = {}, #s
    for i = 1, len do
        local b = s:byte(i)
        freq[b] = (freq[b] or 0) + 1
    end
    local e = 0
    for _, c in pairs(freq) do
        local p = c / len
        e = e - p * math.log(p, 2)
    end
    return e
end

local function hostInSuffixList(host, list)
    for _, suffix in ipairs(list) do
        if host == suffix or host:sub(-(#suffix + 1)) == "." .. suffix then return true end
    end
    return false
end

local function hasNonStandardPort(url)
    local authority = smatch(url, "^%w[%w%+%.%-]*://([^/?#]+)")
    if not authority or authority:find("%[", 1) then return false end
    local port = tonumber(smatch(authority, ":(%d+)$"))
    return port ~= nil and port ~= 80 and port ~= 443
end

local function scoreC2(url, host, body, isPost)
    local score, why = 0, {}
    if sfind(host, "xn--", 1, true) then
        score = score + 2; why[#why + 1] = "punycode/lookalike domain"
    end
    local tunnel = hostInSuffixList(host, RelayHostSuffixes)
    if tunnel then
        score = score + 1; why[#why + 1] = "tunnel / free-hosting platform"
        if hasNonStandardPort(url) then score = score + 2; why[#why + 1] = "non-standard port" end
    end
    local label = smatch(host, "^([^%.]+)")
    if label and #label >= 20 and shannonEntropy(label) > 4.3 then
        score = score + 1; why[#why + 1] = "random-looking host name"
    end
    if isPost and type(body) == "string" and #body > 200 and #body < 200000 then
        if shannonEntropy(body:sub(1, 4096)) > 7.2 then
            score = score + 1; why[#why + 1] = "encrypted/random payload"
        end
    end
    return score, table.concat(why, ", ")
end

-- ======================= per-host upload volume (notice only) ==================
local HostBytes = {}
local function trackUpload(host, body)
    if type(body) ~= "string" or #body == 0 then return end
    local total = (HostBytes[host] or 0) + #body
    HostBytes[host] = total
    if total > 262144 then
        noticeOnce("vol:" .. host, ("Notice: more than 256 KB uploaded to %s this session (not blocked)."):format(host))
    end
end

-- hosts learned from responses (IP-logger pages, geolocation JSON)
local RuntimeBlocked = {}

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
        if next(GameContextWords) ~= nil and getgenv()._log_blocks then
            local list = {}
            for w in pairs(GameContextWords) do list[#list + 1] = w end
            warn(("Game context \"%s\": the words {%s} are not treated as evidence in this game.")
                 :format(name, table.concat(list, ", ")))
        end
    end)
    if not ok then GameContextWords = {} end
end

local function isForgivenByGameContext(word)
    if not getgenv()._game_context_aware then return false end
    return GameContextWords[word:lower()] == true
end

local imageCounter = 0

local function ensureFolder(path)
    pcall(function()
        if not isfolder(path) then
            makefolder(path)
        end
    end)
end

local function autoDeleteFile(filepath)
    task.delay(10, function()
        pcall(function()
            if isfile(filepath) then
                delfile(filepath)
            end
        end)
    end)
end

local function downloadImage(url)
    if isBlocked and type(isBlocked) == "function" then
        local blocked = isBlocked(url, nil, nil, false)
        if blocked then
            warn("downloadImage: URL blocked by filter, icon not loaded: " .. tostring(url))
            return nil
        end
    end

    local req = http_request or (syn and syn.request) or request
    if not req then return nil end

    local folderPath = "./temp/img"
    ensureFolder(folderPath)
    imageCounter = imageCounter + 1
    local filename = folderPath .. "/" .. imageCounter .. ".png"

    local success, res = pcall(function()
        return req({Url = url, Method = "GET"}).Body
    end)

    if success and res then
        pcall(function() writefile(filename, res) end)
        autoDeleteFile(filename)
        if getcustomasset then
            return getcustomasset(filename)
        elseif syn and syn.crypt and syn.crypt.customasset then
            return syn.crypt.customasset(filename)
        end
    end
    return nil
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
    DEFAULT_ICON = getgenv()._icon_asset or "rbxassetid://83768500686029",
}

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
            local asset = downloadImage(config.icon)
            if asset then
                iconObj = Instance.new("ImageLabel")
                iconObj.Image = asset
                iconObj.BackgroundTransparency = 1
                iconObj.Size = UDim2.new(0, CONFIG.ICON_SIZE, 0, CONFIG.ICON_SIZE)
                iconObj.LayoutOrder = 1
                iconObj.Parent = innerFrame
            end
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

local lastLog, lastLogN = {}, 0
local BlockHistory = {}
getgenv().BloxScannerPrintLog = function()
    if #BlockHistory == 0 then warn("BloxScanner: nothing blocked yet.") return end
    for i, e in ipairs(BlockHistory) do
        warn(("[%d] %s | %s | %s"):format(i, e.time, e.tag, e.url))
    end
end

local function logBlock(tag, url)
    Stats.blocked = Stats.blocked + 1
    BlockHistory[#BlockHistory + 1] = { time = os.date("%H:%M:%S"), tag = tostring(tag), url = tostring(url):sub(1, 200) }
    if #BlockHistory > 100 then table.remove(BlockHistory, 1) end
    if not getgenv()._log_blocks then return end

    -- the same block repeated within 3 seconds is shown only once
    do
        local key = tostring(tag) .. "|" .. tostring(url)
        local now = os.clock()
        if lastLog[key] and now - lastLog[key] < 3 then
            lastWebhookReason = nil
            return
        end
        lastLogN = lastLogN + 1
        if lastLogN > 200 then lastLog, lastLogN = {}, 1 end
        lastLog[key] = now
    end
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
    if not getgenv()._log_blocks then return end
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
    if not getgenv()._log_blocks then return end
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
    if not getgenv()._log_blocks then return end
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
    if type(url) ~= "string" or url == "" then return false, nil end
    local dUrl = urlDecode(url)
    local host = getHost(dUrl)
    local path = smatch(dUrl, "://[^/]+(/[^?]*)") or ""
    local ul = slower(dUrl)
    local pl = slower(path)
    local bl = slower(type(body) == "string" and urlDecode(body) or "")
    Stats.requests = Stats.requests + 1

    if getgenv()._scan_cookie_encodings and not (host == "roblox.com" or host:sub(-11) == ".roblox.com") then
        local kind = cookieEncodedLeak(url) or cookieEncodedLeak(body) or cookieEncodedLeak(headersToString(headers))
        if kind then
            lastWebhookReason = "Roblox cookie in the request (" .. kind .. ")"
            return true, "STEALER"
        end
    end

    local COOKIE_SIG_WORD_2 = "roblosecur" .. "ity"
    if sfind(ul, COOKIE_SIG, 1, true) or sfind(ul, COOKIE_SIG_WORD_2, 1, true) or
       sfind(bl, COOKIE_SIG, 1, true) or sfind(bl, COOKIE_SIG_WORD_2, 1, true) then
        if not (host == "roblox.com" or host:sub(-11) == ".roblox.com") then
            return true, "STEALER"
        end
    end

    if isWhitelisted(host) then
        return false, nil
    end

    -- read-only Roblox API proxies (roproxy): allow plain GET lookups
    if not isPost and isReadOnlyApiHost(host) then
        local qs = pl:match("%?(.*)$")
        local bad = qs and webhookBodyVerdict(qs, true)
        if not bad then
            return false, nil
        end
    end

    if isExactBlacklisted(host) then
        return true, "LOGGER"
    end

    if KnownExfilHosts[host] then
        return true, "STEALER"
    end

    if RuntimeBlocked[host] then
        lastWebhookReason = "this host returned an IP-logger style response earlier in this session"
        return true, "LOGGER"
    end

    if getgenv()._block_discord_tokens or getgenv()._block_jwt then
        local what = tokenLeak(url) or tokenLeak(body) or tokenLeak(headersToString(headers))
        if what then
            lastWebhookReason = what .. " found in the outgoing request"
            return true, "STEALER"
        end
    end

    if getgenv()._protect_real_ip and UserIP and not wantFakeIP() then
        if containsUserIP(url) or containsUserIP(body) or containsUserIP(headersToString(headers)) then
            lastWebhookReason = "your real IP address is inside the outgoing request"
            return true, "LOGGER"
        end
    end

    if getgenv()._block_bare_ip then
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

    if getgenv()._block_relay_hosts then
        local isRelayHost = false
        for _, suffix in ipairs(RelayHostSuffixes) do
            if host == suffix or host:sub(-(#suffix + 1)) == "." .. suffix then
                isRelayHost = true
                break
            end
        end

        if isRelayHost then

            local shouldBlock, why, weak = webhookBodyVerdict(bl)

            if not shouldBlock and not isPost then
                local qs = pl:match("%?(.*)$")
                if qs then
                    local qsWeak
                    shouldBlock, why, qsWeak = webhookBodyVerdict(qs)
                    weak = weak or qsWeak
                    if shouldBlock then
                        why = "GET query string → " .. tostring(why)
                    end
                end
            end

            if shouldBlock then
                lastWebhookReason = why
                return true, "RELAY"
            end
            if weak then
                noticeOnce("weak:" .. host,
                    ("Notice: %s received a device-identifying field (\"%s\"). Allowed - this looks like a key/licence system. "
                     .. "Set getgenv()._strict_identity = true to block this kind of request."):format(host, tostring(weak)))
            end
            if getgenv()._verbose_soft_warnings then
                warn(("Allowed request to relay platform (no sensitive data): %s (%s)")
                     :format(tostring(host), isPost and "POST" or "GET"))
            end
        end
    end

    if getgenv()._c2_scoring then
        local score, why = scoreC2(dUrl, host, body, isPost)
        if score >= 4 then
            lastWebhookReason = "possible C2 / exfiltration infrastructure: " .. why
            return true, "RELAY"
        elseif score >= 3 then
            noticeOnce("c2:" .. host, ("Notice: %s looks unusual (%s). Allowed - score %d/4."):format(host, why, score))
        end
    end
    if isPost then trackUpload(host, body) end

    if getgenv()._blockwebhook and isPost then
        for _, pat in ipairs(WebhookPatterns) do
            local hostSuffix, pathSub = pat[1], pat[2]
            local hostMatches = (host == hostSuffix or host:sub(-(#hostSuffix + 1)) == "." .. hostSuffix)
            if hostMatches and (pathSub == "" or sfind(pl, pathSub, 1, true)) then

                if getgenv()._strict_webhook then

                    return true, "WEBHOOK"
                end

                local shouldBlock, why = webhookBodyVerdict(bl, true)
                if shouldBlock then
                    lastWebhookReason = why
                    return true, "WEBHOOK"
                end

                if getgenv()._verbose_soft_warnings then
                    warn("Allowed webhook (no sensitive data): " .. tostring(host))
                end
            end
        end
    end

    local hostLabels = {}
    for label in host:gmatch("[^%.]+") do
        hostLabels[#hostLabels + 1] = label
    end

    local paddedHost = "." .. host .. "."
    for _, p in ipairs(BLACKLIST) do
        if host == p or host:sub(-(#p + 1)) == "." .. p then
            return true, "LOGGER"
        end
        -- multi-label entries ("checkip.amazonaws") match as whole labels inside the host
        if sfind(p, ".", 1, true) and sfind(paddedHost, "." .. p .. ".", 1, true) then
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
        if host:sub(-(#tld + 1)) == "." .. tld then
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

local function looksLikeLuaCode(s)
    local head = s:sub(1, 4000)
    if sfind(head, "game:GetService", 1, true) or sfind(head, "getgenv()", 1, true)
       or sfind(head, "loadstring", 1, true) or sfind(head, "return function", 1, true) then
        return true
    end
    return sfind(head, "local ", 1, true) ~= nil
       and (sfind(head, "function", 1, true) ~= nil or sfind(head, "\nend", 1, true) ~= nil)
end

local function sanitizeBody(bodyStr, host)
    if type(bodyStr) ~= "string" or bodyStr == "" then return bodyStr end
    if not getgenv()._sanitize_ip then return bodyStr end

    if host and isWhitelisted(host) then return bodyStr end
    -- scripts fetched for loadstring must stay byte-for-byte intact
    if looksLikeLuaCode(bodyStr) then return bodyStr end

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

    if stashN > 0 then
        for token, val in pairs(stash) do
            out = out:gsub(token, val)
        end
    end

    return out
end

-- ======================= response inspection (learn IP-logger hosts) ==========
local CODE_HOSTS = {
    "githubusercontent.com", "github.com", "gitlab.com", "pastebin.com", "paste.ee",
    "bitbucket.org", "rentry.co", "hastebin.com", "gist.github.com",
}
local GIVEAWAYS = {
    "ip logger", "iplogger", "grabify", "ip grabber", "grab your ip", "track your ip",
    "logs your ip address", "captures your ip", "ip tracking service",
}
local LOC_SOFT = {
    country = 1, region = 1, city = 1, zip = 1, postal = 1, lat = 1, latitude = 1, lon = 1,
    longitude = 1, timezone = 1, country_code = 1, region_code = 1, continent = 1,
    continent_code = 1, currency = 1, calling_code = 1, area_code = 1, metro_code = 1, organization = 1,
}
local LOC_HARD = {
    isp = 1, org = 1, asn = 1, ip = 1, ipaddress = 1, ip_address = 1, query = 1,
    origin = 1, ipv4 = 1, ipv6 = 1, publicip = 1, public_ip = 1,
}

local function locationSchemaHits(decoded)
    local soft, hard = 0, 0
    local function walk(t, depth)
        if depth > 4 then return end
        for k, v in pairs(t) do
            if type(k) == "string" then
                local lk = slower(k)
                if LOC_HARD[lk] then hard = hard + 1; soft = soft + 1
                elseif LOC_SOFT[lk] then soft = soft + 1 end
            end
            if type(v) == "table" then walk(v, depth + 1) end
        end
    end
    pcall(walk, decoded, 0)
    return soft, hard
end

-- returns a reason string when the response looks like an IP-logger / geolocation page
local function inspectResponse(host, body)
    if not getgenv()._learn_from_responses then return nil end
    if type(body) ~= "string" or body == "" or host == "" then return nil end
    if isWhitelisted(host) or RuntimeBlocked[host] then return nil end
    if hostInSuffixList(host, CODE_HOSTS) then return nil end
    if #body > 60000 or looksLikeLuaCode(body) then return nil end

    -- logger landing pages are tiny; long API/list responses may just mention these words
    if #body <= 3000 then
        local lowered = slower(body)
        for _, phrase in ipairs(GIVEAWAYS) do
            if sfind(lowered, phrase, 1, true) then
                RuntimeBlocked[host] = true
                return 'response contains "' .. phrase .. '"'
            end
        end
    end

    local first = body:sub(1, 1)
    if first == "{" or first == "[" then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and type(decoded) == "table" then
            local soft, hard = locationSchemaHits(decoded)
            if soft >= 5 and hard >= 1 then
                RuntimeBlocked[host] = true
                return ("response is a geolocation record (%d location fields)"):format(soft)
            end
        end
    end
    return nil
end

-- Lower-cases the code and undoes cheap obfuscation tricks that hide
-- signatures: "a".."b" concatenation, \ddd / \xHH escapes, string.char(...).
local function codeNormalize(src)
    local ok, res = pcall(function()
        local s = src:lower()
        if #s > 3000000 then return s end
        s = gsub(s, "\\x(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        s = gsub(s, "\\(%d%d?%d?)", function(d)
            local n = tonumber(d)
            if n and n < 256 then return string.char(n) end
        end)
        s = gsub(s, "string%.char%s*%(([%d%s,]+)%)", function(list)
            local parts = {}
            for n in list:gmatch("%d+") do
                local v = tonumber(n)
                if not v or v > 255 then return nil end
                parts[#parts + 1] = string.char(v)
            end
            return '"' .. table.concat(parts) .. '"'
        end)
        for _ = 1, 4 do
            local before = s
            s = gsub(s, "[\"']%s*%.%.%s*[\"']", "")
            if s == before then break end
        end
        return s
    end)
    if ok and type(res) == "string" then return res end
    return src:lower()
end

local function codeSha256(code)
    if type(crypt) == "table" and type(crypt.hash) == "function" then
        local ok, h = pcall(crypt.hash, code, "sha256")
        if ok and type(h) == "string" then return h:lower() end
    end
    return nil
end

if getgenv()._scan_loadstring and hookfunction and type(loadstring) == "function" then
    local origLoadstring

    local function blockCode(reason)
        local source = getCallingScriptName()
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

    origLoadstring = hookfunction(loadstring, newcclosure(function(code, chunkname)
        if not getgenv()._scan_loadstring or type(code) ~= "string" then
            return origLoadstring(code, chunkname)
        end

        -- Whitelist:
        --   "sha256:<hex>"  -> exact script, skips ALL checks (needs crypt.hash)
        --   any other text  -> must appear in the first 300 chars; skips only the
        --                      soft (warning-only) checks. Hard signatures always run,
        --                      so a stealer cannot pass by pasting a trusted word.
        local softTrusted = false
        local wl = getgenv()._loadstring_whitelist
        if type(wl) == "table" and #wl > 0 then
            local head = slower(code:sub(1, 300))
            local hash
            for _, w in ipairs(wl) do
                if type(w) == "string" and w ~= "" then
                    if slower(w:sub(1, 7)) == "sha256:" then
                        if hash == nil then hash = codeSha256(code) or false end
                        if hash and hash == slower(w:sub(8)) then
                            return origLoadstring(code, chunkname)
                        end
                    elseif sfind(head, slower(w), 1, true) then
                        softTrusted = true
                    end
                end
            end
        end

        local norm = codeNormalize(code)
        local compact = gsub(norm, "[%s%c]", "")

        for _, word in ipairs(CodeBlacklistHard) do
            if sfind(norm, word, 1, true) or sfind(compact, word, 1, true) then
                return blockCode('hard signature "' .. word .. '"')
            end
        end

        if softTrusted then
            return origLoadstring(code, chunkname)
        end

        for _, sig in ipairs(CodeSignaturePatterns) do
            if sig.hard and smatch(norm, sig.pattern) then
                return blockCode('pattern signature "' .. sig.label .. '"')
            end
        end

        if getgenv()._verbose_soft_warnings then
            local source = getCallingScriptName()

            for _, word in ipairs(CodeBlacklistSoft) do
                if sfind(norm, word, 1, true) and not isForgivenByGameContext(word) then
                    warn(("Notice: loadstring from \"%s\" contains suspicious word \"%s\". Code was NOT blocked; this is a warning only.")
                        :format(source, word))
                    break
                end
            end

            for _, sig in ipairs(CodeSignaturePatterns) do
                if not sig.hard and smatch(norm, sig.pattern) then
                    warn(("Notice: loadstring from \"%s\" contains suspicious pattern \"%s\". Code was NOT blocked; this is a warning only.")
                        :format(source, sig.label))
                end
            end

            if sfind(norm, "webhook", 1, true) then
                for _, marker in ipairs(ENV_INJECTION_MARKERS) do
                    if sfind(norm, marker, 1, true) then
                        warn(("Notice: loadstring from \"%s\" contains a webhook plus marker \"%s\". Code was NOT blocked; this is a warning only.")
                            :format(source, marker))
                        break
                    end
                end
            end
        end

        return origLoadstring(code, chunkname)
    end))
end

local localUserId = player and player.UserId

-- Works for the real LocalPlayer and for cloneref'd copies of it.
local function isLocalPlayer(inst)
    if inst == player then return true end
    local ok, res = _pcall(function()
        return inst.ClassName == "Player" and inst.UserId == localUserId
    end)
    return ok and res == true
end

local WATCHED_METHODS = {
    HttpGet = true, HttpGetAsync = true, GetAsync = true, GetObjects = true,
    HttpPost = true, HttpPostAsync = true, PostAsync = true,
    RequestAsync = true, ReportAbuse = true, Kick = true,
}

local oldNamecall
local namecallHookOk, namecallHookErr = pcall(function()
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()

        -- hot path: almost every call leaves here without allocating anything
        if not WATCHED_METHODS[method] then
            return oldNamecall(self, ...)
        end

        local url, body = ...

        if method == "Kick" then
            if getgenv()._anti_kick and isLocalPlayer(self) then
                logKick()
                return
            end
            return oldNamecall(self, ...)

        elseif method == "ReportAbuse" then
            if getgenv()._anti_reportabuse and not checkcaller() then
                logReportAbuse()
                return
            end
            return oldNamecall(self, ...)

        elseif method == "HttpGet" or method == "HttpGetAsync" or method == "GetAsync" then
            local blocked, tag = isBlocked(url, nil, nil, false)
            if blocked then
                logBlock(tag, url)
                return ""
            end
            local result = oldNamecall(self, ...)
            if type(result) == "string" then
                local respHost = getHost(urlDecode(url))
                local why = inspectResponse(respHost, result)
                if why then
                    lastWebhookReason = why
                    logBlock("LOGGER", url)
                    return ""
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
                if getgenv()._verbose_soft_warnings then
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

            local swappedOpts = nil
            if wantFakeIP() then
                local nu, nb, nh, changed = swapRealIP(reqUrl, reqBody, reqHeaders)
                if changed then
                    swappedOpts = copyOptsWith(url, nu, nb, nh)
                    reqUrl, reqBody, reqHeaders = nu, nb, nh
                end
            end

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
            local result
            if swappedOpts then
                result = oldNamecall(self, swappedOpts)
            else
                result = oldNamecall(self, ...)
            end
            if type(result) == "table" then
                local respBody = result.Body or result.body
                local why = inspectResponse(getHost(urlDecode(reqUrl)), respBody)
                if why then
                    lastWebhookReason = why
                    logBlock("LOGGER", reqUrl)
                    return { Success = false, StatusCode = 403, StatusMessage = "Blocked", Body = "", Headers = {} }
                end
                local newResult = {}
                for k, v in pairs(result) do newResult[k] = v end
                if newResult.Body then newResult.Body = sanitizeBody(newResult.Body, getHost(urlDecode(reqUrl))) end
                if newResult.body then newResult.body = sanitizeBody(newResult.body, getHost(urlDecode(reqUrl))) end
                return newResult
            end
            return result
        end

        return oldNamecall(self, ...)
    end))
end)

if not namecallHookOk then
    warn("CRITICAL: failed to install the __namecall hook. Error: " .. tostring(namecallHookErr))
end

local function checkActorEvasionRisk()
    if not getgenv()._warn_actor_risk then return end

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

-- Player.Kick(player) (dot-call) does not go through __namecall.
-- Hooked with hookfunction; the __namecall hook above covers player:Kick().
if getgenv()._anti_kick and type(hookfunction) == "function" and player then
    local kickHookOk, kickHookErr = pcall(function()
        local origKick
        origKick = hookfunction(player.Kick, newcclosure(function(self, ...)
            if getgenv()._anti_kick and isLocalPlayer(self) then
                logKick()
                return
            end
            return origKick(self, ...)
        end))
    end)

    if not kickHookOk then
        warn("Could not hook Player.Kick for dot-calls (player:Kick() is still blocked). Error: " .. tostring(kickHookErr))
    end
end

local function wrapExecutorRequest(fn)
    if type(fn) ~= "function" then return fn end
    return newcclosure(function(opts, ...)
        if type(opts) ~= "table" then return fn(opts, ...) end
        local reqUrl = opts.Url or opts.URL or opts.url
        local reqBody = opts.Body or opts.body
        local reqHeaders = opts.Headers or opts.headers
        local reqMethod = string.upper(tostring(opts.Method or opts.method or "GET"))
        local isPost = (reqMethod ~= "GET")

        if wantFakeIP() then
            local nu, nb, nh, changed = swapRealIP(reqUrl, reqBody, reqHeaders)
            if changed then
                opts = copyOptsWith(opts, nu, nb, nh)
                reqUrl, reqBody, reqHeaders = nu, nb, nh
            end
        end

        local blocked, tag = isBlocked(reqUrl, reqBody, reqHeaders, isPost)
        if blocked then
            logBlock(tag, reqUrl)
            return { Success = false, StatusCode = 403, StatusMessage = "Blocked", Body = "", Headers = {} }
        end
        local result = fn(opts, ...)
        if type(result) == "table" then
            local why = inspectResponse(getHost(urlDecode(reqUrl)), result.Body or result.body)
            if why then
                lastWebhookReason = why
                logBlock("LOGGER", reqUrl)
                return { Success = false, StatusCode = 403, StatusMessage = "Blocked", Body = "", Headers = {} }
            end
            local newResult = {}
            for k, v in pairs(result) do newResult[k] = v end
            local respHost = getHost(urlDecode(reqUrl))
            if newResult.Body then newResult.Body = sanitizeBody(newResult.Body, respHost) end
            if newResult.body then newResult.body = sanitizeBody(newResult.body, respHost) end
            return newResult
        end
        return result
    end)
end

local HookStatus = {}
local HookWatch = {}

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
        HookWatch[#HookWatch + 1] = { name = name, getter = getter, wrapped = wrapped, warned = false }
    else
        HookStatus[name] = "не применилось (возможно readonly)"
    end
end

tryHookGlobal("request", function() return request end, function(w) getgenv().request = w; _G.request = w end)
tryHookGlobal("http_request", function() return http_request end, function(w) getgenv().http_request = w; _G.http_request = w end)
tryHookGlobal("syn.request", function() return syn and syn.request end, function(w) syn.request = w end)
tryHookGlobal("http.request", function() return http and http.request end, function(w) http.request = w end)
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
                if type(message) == "string" and (cookieEncodedLeak(message) or tokenLeak(message)) then
                    logBlock("STEALER", url)
                    return
                end
                return origSend(self, message)
            end
            pcall(function() sock.Send = newSend end)
        end
        return sock
    end
    pcall(function() WebSocket.connect = newConnect end)
end

local protectedFunctions = {}

if getgenv()._anti_reportabuse and type(hookfunction) == "function" then
    local ok, origReportAbuse = pcall(function()
        return hookfunction(Players.ReportAbuse, newcclosure(function(self, ...)
            if not checkcaller() then
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

if getgenv()._anti_robux_prompt and type(hookfunction) == "function" then
    local robuxMethods = {
        "PromptPurchase", "PromptGamePassPurchase", "PromptProductPurchase",
        "PromptBundlePurchase", "PromptPremiumPurchase", "PromptSubscriptionPurchase",
        "PerformPurchase", "PerformPurchaseV2",
    }

    for _, methodName in ipairs(robuxMethods) do
        local target = Market[methodName]
        if type(target) == "function" then
            local ok, origFn = pcall(function()
                return hookfunction(target, newcclosure(function(self, ...)

                    if checkcaller() or isCallFromRealGameScript() then
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

if getgenv()._anti_afk then
    local antiAfkOk, antiAfkErr = pcall(function()
        local VirtualUser = game:GetService("VirtualUser")
        local plr = game:GetService("Players").LocalPlayer

        if getgenv().__BloxScannerAntiAfk then
            pcall(function() getgenv().__BloxScannerAntiAfk:Disconnect() end)
            getgenv().__BloxScannerAntiAfk = nil
        end

        getgenv().__BloxScannerAntiAfk = plr.Idled:Connect(function()

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

-- ======================= filesystem protection ===============================
if getgenv()._protect_filesystem then
    for _, fname in ipairs({ "writefile", "appendfile" }) do
        local orig = getgenv()[fname]
        if type(orig) == "function" then
            local wrapped = newcclosure(function(path, content, ...)
                if getgenv()._protect_filesystem and type(content) == "string" then
                    local kind = cookieEncodedLeak(content)
                    if kind then
                        lastWebhookReason = "a script tried to save your Roblox cookie to a file (" .. kind .. ")"
                        logBlock("STEALER", "file write: " .. tostring(path))
                        return
                    end
                end
                return orig(path, content, ...)
            end)
            pcall(function() getgenv()[fname] = wrapped end)
        end
    end

    local deleteTimes, lockedUntil = {}, 0
    for _, fname in ipairs({ "delfile", "deletefile", "delfolder", "deletefolder" }) do
        local orig = getgenv()[fname]
        if type(orig) == "function" then
            local wrapped = newcclosure(function(path, ...)
                if getgenv()._protect_filesystem then
                    local now = os.clock()
                    if now < lockedUntil then
                        lastWebhookReason = "deletion lockdown is active (mass deletion was detected)"
                        logBlock("STEALER", "delete blocked: " .. tostring(path))
                        return
                    end
                    if type(path) == "string" then
                        local p = slower(path)
                        if p == "" or p == "/" or p == "*" or p == "." or p == "workspace" then
                            lockedUntil = now + 60
                            lastWebhookReason = "attempt to wipe the whole workspace"
                            logBlock("STEALER", "delete blocked: " .. tostring(path))
                            return
                        end
                    end
                    deleteTimes[#deleteTimes + 1] = now
                    while #deleteTimes > 0 and now - deleteTimes[1] > 2 do table.remove(deleteTimes, 1) end
                    if #deleteTimes >= 8 then
                        lockedUntil = now + 60
                        lastWebhookReason = ("%d files deleted within 2 seconds - lockdown for 60 s"):format(#deleteTimes)
                        logBlock("STEALER", "delete blocked: " .. tostring(path))
                        return
                    end
                end
                return orig(path, ...)
            end)
            pcall(function() getgenv()[fname] = wrapped end)
        end
    end
end

-- ======================= restorefunction guard (opt-in) ======================
if getgenv()._guard_restore and type(restorefunction) == "function" and type(hookfunction) == "function" then
    local protectedTargets = {}
    if type(loadstring) == "function" then protectedTargets[loadstring] = true end
    pcall(function() protectedTargets[Players.ReportAbuse] = true end)
    pcall(function() if player then protectedTargets[player.Kick] = true end end)
    for _, mName in ipairs({ "PromptPurchase", "PromptGamePassPurchase", "PromptProductPurchase",
        "PromptBundlePurchase", "PromptPremiumPurchase", "PromptSubscriptionPurchase",
        "PerformPurchase", "PerformPurchaseV2" }) do
        pcall(function() protectedTargets[Market[mName]] = true end)
    end
    local oldRestore
    local okRestore = pcall(function()
        oldRestore = hookfunction(restorefunction, newcclosure(function(target, ...)
            if getgenv()._guard_restore and protectedTargets[target] then
                lastWebhookReason = "a script tried to remove one of BloxScanner's hooks with restorefunction()"
                logBlock("STEALER", "restorefunction")
                return
            end
            return oldRestore(target, ...)
        end))
    end)
    if not okRestore then warn("Could not install the restorefunction guard.") end
end

-- ======================= hook watchdog =======================================
if #HookWatch > 0 then
    task.spawn(function()
        while getgenv().__BloxScannerLoaded do
            task.wait(5)
            if getgenv()._watch_hooks then
                for _, h in ipairs(HookWatch) do
                    local ok, current = pcall(h.getter)
                    if ok and current == h.wrapped then
                        h.warned = false
                    elseif not h.warned then
                        h.warned = true
                        warn(("Warning: the '%s' hook was replaced by another script. Requests through it are NOT checked any more. Treat this session as unprotected."):format(h.name))
                    end
                end
            end
        end
    end)
end

getgenv().BloxScannerUnload = function()
    local flags = {
        "_blockwebhook", "_sanitize_ip", "_anti_kick", "_log_blocks",
        "_anti_reportabuse", "_anti_robux_prompt", "_block_bare_ip",
        "_block_relay_hosts", "_strict_webhook", "_game_context_aware",
        "_warn_actor_risk", "_anti_afk",
        "_verbose_soft_warnings", "_scan_loadstring", "_strict_identity",
        "_protect_real_ip", "_scan_cookie_encodings", "_block_discord_tokens", "_block_jwt",
        "_learn_from_responses", "_c2_scoring", "_protect_filesystem", "_watch_hooks",
        "_guard_restore", "_restore_prehooked", "_fake_real_ip",
    }
    for _, f in ipairs(flags) do
        getgenv()[f] = false
    end

    if getgenv().__BloxScannerAntiAfk then
        pcall(function() getgenv().__BloxScannerAntiAfk:Disconnect() end)
        getgenv().__BloxScannerAntiAfk = nil
    end

    getgenv().__BloxScannerLoaded = nil
    warn("Unloaded. All checks are now disabled. Rejoin to fully remove installed hooks.")
end

