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
local MAX_SCAN_TIME = 5

local BUYERS_WEBHOOK = "https://discord.com/api/webhooks/1452638384324477132/CW7VXup_c49nzxrYdVqXsJ_siUIQz3-s3edWkomA1_XoQEUe2s6wocMtHcAal99dTwlU"
local HIGHLIGHTS_WEBHOOK = "https://discord.com/api/webhooks/1450984721835102349/edA21nviAK_1xcHqfVil1REuWpMVq7dLM5nzNwdtenWkZw_2ks1VPR2L88adFid34pA5"

-- ======================
-- JOB ID ENCRYPTION
-- ======================
local ELEVATE_SECRET = "ELEVATE_2025"

local function xorCrypt(input, key)
    local out = {}
    for i = 1, #input do
        local c = string.byte(input, i)
        local k = string.byte(key, ((i - 1) % #key) + 1)
        out[i] = string.char(bit32.bxor(c, k))
    end
    return table.concat(out)
end

local function encryptJobId(jobId)
    return HttpService:Base64Encode(xorCrypt(jobId, ELEVATE_SECRET))
end

-- ======================
-- PLAYER
-- ======================
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ======================
-- REQUEST
-- ======================
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
-- FORMAT MONEY
-- ======================
local function formatMoney(n)
    if n >= 1e9 then
        return string.format("%.1fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    else
        return string.format("%.1fK", n / 1e3)
    end
end

-- ======================
-- PARSE MPS
-- ======================
local function parseMPS(txt)
    if not txt or not txt:find("/s") then return end
    local num, suf = txt:match("%$([%d%.]+)%s*([KMB]?)")
    if not num then return end

    local v = tonumber(num)
    if not v then return end

    if suf == "K" then v *= 1e3
    elseif suf == "M" then v *= 1e6
    elseif suf == "B" then v *= 1e9 end

    return math.floor(v)
end

-- ======================
-- SERVER HOP
-- ======================
local function hopNewServer()
    local currentJob = game.JobId

    for _ = 1, 5 do
        local url =
            "https://games.roblox.com/v1/games/" ..
            PLACE_ID ..
            "/servers/Public?sortOrder=Asc&limit=100"

        local ok, body = pcall(game.HttpGet, game, url)
        if not ok or not body then task.wait(0.4) continue end

        local data
        ok, data = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok or not data.data then task.wait(0.4) continue end

        local servers = {}
        for _, srv in ipairs(data.data) do
            if srv.id ~= currentJob and srv.playing < srv.maxPlayers then
                servers[#servers + 1] = srv.id
            end
        end

        if #servers > 0 then
            TeleportService:TeleportToPlaceInstance(
                PLACE_ID,
                servers[math.random(#servers)],
                LocalPlayer
            )
            task.wait(1)
            return
        end
    end

    task.wait(0.75)
    hopNewServer()
end

TeleportService.TeleportInitFailed:Connect(function()
    task.wait(0.5)
    hopNewServer()
end)

-- ======================
-- SCAN BRAINROTS
-- ======================
local function scanBrainrots()
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return {} end

    local found, seen = {}, {}

    for _, gui in ipairs(debris:GetDescendants()) do
        if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui"))
            and gui:GetFullName():find("FastOverheadTemplate")
        then
            local mps
            local name, len = nil, 0

            for _, obj in ipairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    local t = obj.Text
                    if t and t ~= "" then
                        local v = parseMPS(t)
                        if v then
                            mps = v
                        elseif not t:lower():find("stolen")
                            and not t:find("/s")
                            and not t:find("%$")
                            and not t:match("^%d")
                            and #t > len
                        then
                            name, len = t, #t
                        end
                    end
                end
            end

            if name and mps and mps >= MIN_MPS then
                local id = name .. mps
                if not seen[id] then
                    seen[id] = true
                    found[#found + 1] = { name = name, mps = mps }
                end
            end
        end
    end

    table.sort(found, function(a, b)
        return a.mps > b.mps
    end)

    return found
end

-- ======================
-- WEBHOOK
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

-- ======================
-- HIGHLIGHTS (BLACK)
-- ======================
local function sendHighlights(hits)
    local top = hits[1]
    if not top then return end

    local lines = {}
    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("%-22s $%s/s", hits[i].name, formatMoney(hits[i].mps))
    end

    local embed = {
        title = top.name,
        description = "$" .. formatMoney(top.mps) .. "/s",
        color = 0x0D0D0D,
        footer = { text = "Elevate • Highlights" }
    }

    if #lines > 0 then
        embed.description =
            embed.description ..
            "\n\n```text\n" .. table.concat(lines, "\n") .. "\n```"
    end

    sendWebhook(HIGHLIGHTS_WEBHOOK, { embeds = { embed } })
end

-- ======================
-- BUYERS (WHITE)
-- ======================
local function sendBuyers(hits)
    local top = hits[1]
    if not top then return end

    local encryptedJob = encryptJobId(JOB_ID)

    local embed = {
        title = top.name,
        description =
            "$" .. formatMoney(top.mps) .. "/s\n\n" ..
            "Job ID:\n```" .. encryptedJob .. "```",
        color = 0xFFFFFF,
        footer = { text = "Elevate • Private Access" }
    }

    sendWebhook(BUYERS_WEBHOOK, { embeds = { embed } })
end

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
    task.wait(0.25)
end

_G.ELEVATE_LAST_JOB = JOB_ID

if #hits > 0 then
    sendHighlights(hits)
    sendBuyers(hits)
end

hopNewServer()
