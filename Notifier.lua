-- ======================
-- SERVICES
-- ======================
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- ======================
-- CONFIG
-- ======================
local PLACE_ID = game.PlaceId
local JOB_ID = game.JobId
local MIN_MPS = 10_000_000
local MAX_SCAN_TIME = 4

local BUYERS_WEBHOOK = "https://discord.com/api/webhooks/1452638384324477132/CW7VXup_c49nzxrYdVqXsJ_siUIQz3-s3edWkomA1_XoQEUe2s6wocMtHcAal99dTwlU"
local HIGHLIGHTS_WEBHOOK = "https://discord.com/api/webhooks/1450984721835102349/edA21nviAK_1xcHqfVil1REuWpMVq7dLM5nzNwdtenWkZw_2ks1VPR2L88adFid34pA5"

-- ======================
-- JOB ID ENCRYPTION
-- ======================
local ELEVATE_SECRET = "ELEVATE_2025"

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64encode(data)
    return ((data:gsub('.', function(x)
        local r,bits='',x:byte()
        for i=8,1,-1 do
            r=r..(bits%2^i-bits%2^(i-1)>0 and '1' or '0')
        end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c=0
        for i=1,6 do
            c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0)
        end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

local function xorCrypt(input, key)
    local out = {}
    for i = 1, #input do
        out[i] = string.char(bit32.bxor(
            input:byte(i),
            key:byte(((i - 1) % #key) + 1)
        ))
    end
    return table.concat(out)
end

local function encryptJobId(jobId)
    return base64encode(xorCrypt(jobId, ELEVATE_SECRET))
end

-- ======================
-- PLAYER / REQUEST
-- ======================
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local request =
    request
    or http_request
    or (syn and syn.request)
    or (fluxus and fluxus.request)
    or (http and http.request)

-- ======================
-- MEMORY
-- ======================
_G.ELEVATE_LAST_JOB = _G.ELEVATE_LAST_JOB or nil

-- ======================
-- RARITY FILTER
-- ======================
local RARITY_WORDS = {
    secret=true, mythic=true, legendary=true,
    epic=true, rare=true, uncommon=true, common=true
}

-- ======================
-- UTIL
-- ======================
local function formatMoney(n)
    if n >= 1e9 then return string.format("%.1fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
    else return string.format("%.1fK", n/1e3) end
end

local function parseMPS(txt)
    if not txt or not txt:find("/s") then return end
    local num, suf = txt:match("%$([%d%.]+)%s*([KMB]?)")
    if not num then return end
    local v = tonumber(num)
    if not v then return end
    if suf=="K" then v*=1e3 elseif suf=="M" then v*=1e6 elseif suf=="B" then v*=1e9 end
    return math.floor(v)
end

-- ======================
-- FAST SCAN (NO MIXING)
-- ======================
local function scanBrainrots()
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return {} end

    local found, seen = {}, {}

    for _, gui in ipairs(debris:GetDescendants()) do
        if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui"))
            and gui:GetFullName():find("FastOverheadTemplate")
        then
            local mps, name

            for _, o in ipairs(gui:GetDescendants()) do
                if o:IsA("TextLabel") then
                    local v = parseMPS(o.Text)
                    if v then mps = v break end
                end
            end

            if mps then
                local best, bestLen = nil, 0
                for _, o in ipairs(gui:GetDescendants()) do
                    if o:IsA("TextLabel") then
                        local t = o.Text
                        if t and t ~= ""
                            and not t:find("/s")
                            and not t:find("%$")
                            and not t:match("^%d")
                            and not t:lower():find("stolen")
                            and not RARITY_WORDS[t:lower()]
                        then
                            if #t > bestLen then
                                bestLen = #t
                                best = t
                            end
                        end
                    end
                end
                name = best
            end

            if name and mps and mps >= MIN_MPS then
                local id = name .. mps
                if not seen[id] then
                    seen[id] = true
                    found[#found+1] = { name = name, mps = mps }
                end
            end
        end
    end

    table.sort(found, function(a,b) return a.mps > b.mps end)
    return found
end

-- ======================
-- WEBHOOK (DESIGN UNCHANGED)
-- ======================
local function sendWebhook(url, payload)
    if not request then return end
    pcall(request, {
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(payload)
    })
end

local function sendHighlights(hits)
    local top = hits[1]
    if not top then return end

    local lines = {}
    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("%-22s $%s/s", hits[i].name, formatMoney(hits[i].mps))
    end

    local embed = {
        title = string.format("%s — $%s/s", top.name, formatMoney(top.mps)),
        color = 0x0D0D0D,
        footer = { text = "Elevate • Highlights" }
    }

    if #lines > 0 then
        embed.description = "```text\n" .. table.concat(lines, "\n") .. "\n```"
    end

    sendWebhook(HIGHLIGHTS_WEBHOOK, { embeds = { embed } })
end

local function sendBuyers(hits)
    local top = hits[1]
    if not top then return end

    local encryptedJob = encryptJobId(JOB_ID)

    local embed = {
        title = string.format("%s — $%s/s", top.name, formatMoney(top.mps)),
        description = "Job ID:\n```" .. encryptedJob .. "```",
        color = 0xFFFFFF,
        footer = { text = "Elevate • Private Access" }
    }

    sendWebhook(BUYERS_WEBHOOK, { embeds = { embed } })
end

-- ======================
-- SERVER HOP (FIXED: NO RESTRICTED LOOPS)
-- ======================
local tried = {}

local function fetchServers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. PLACE_ID .. "/servers/Public?sortOrder=Asc&limit=100"
    if cursor then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end

    local ok, body = pcall(game.HttpGet, game, url)
    if not ok or not body then return nil end

    local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok2 or type(data) ~= "table" then return nil end
    return data
end

local function hopNewServer()
    local current = game.JobId

    local cursor = nil
    for _ = 1, 8 do
        local data = fetchServers(cursor)
        if not data or type(data.data) ~= "table" then
            task.wait(0.25)
        else
            cursor = data.nextPageCursor

            for _, srv in ipairs(data.data) do
                local sid = srv.id
                if sid
                    and sid ~= current
                    and not tried[sid]
                    and srv.playing
                    and srv.maxPlayers
                    and srv.playing < srv.maxPlayers
                then
                    tried[sid] = true

                    local ok = pcall(function()
                        TeleportService:TeleportToPlaceInstance(PLACE_ID, sid, LocalPlayer)
                    end)

                    task.wait(0.35)

                    if ok then
                        task.wait(1)
                        return
                    end
                end
            end
        end

        if not cursor then break end
    end

    -- fallback: let Roblox pick a public server
    pcall(function()
        TeleportService:Teleport(PLACE_ID, LocalPlayer)
    end)

    task.wait(1)
    hopNewServer()
end

TeleportService.TeleportInitFailed:Connect(function()
    task.wait(0.35)
    hopNewServer()
end)

-- ======================
-- MAIN
-- ======================
if _G.ELEVATE_LAST_JOB == JOB_ID then
    hopNewServer()
    return
end

local hits = {}
local start = os.clock()

while os.clock() - start < MAX_SCAN_TIME do
    hits = scanBrainrots()
    if #hits > 0 then break end
    task.wait(0.2)
end

if #hits > 0 then
    sendHighlights(hits)
    sendBuyers(hits)
end

_G.ELEVATE_LAST_JOB = JOB_ID
hopNewServer()
