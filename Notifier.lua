-- SERVICES
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- CONFIG
local PLACE_ID = game.PlaceId
local JOB_ID = game.JobId
local MIN_MPS = 10000000
local MAX_SCAN_TIME = 5

local BUYERS_WEBHOOK = "https://discord.com/api/webhooks/1452638384324477132/CW7VXup_c49nzxrYdVqXsJ_siUIQz3-s3edWkomA1_XoQEUe2s6wocMtHcAal99dTwlU"
local HIGHLIGHTS_WEBHOOK = "https://discord.com/api/webhooks/1450984721835102349/edA21nviAK_1xcHqfVil1REuWpMVq7dLM5nzNwdtenWkZw_2ks1VPR2L88adFid34pA5"

-- PLAYER (CRASH SAFE)
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- REQUEST
local request =
    request
    or http_request
    or (syn and syn.request)
    or (fluxus and fluxus.request)
    or (http and http.request)

-- GLOBAL MEMORY
_G.AJ_LAST_JOB = _G.AJ_LAST_JOB or nil

-- ======================
-- LOGGING (CLEAN)
-- ======================
local function log(tag, msg)
    print(string.format("[AJ | %s] %s", tag, msg))
end

-- FORMAT MONEY
local function formatMoney(n)
    if not n then return "0" end
    if n >= 1e9 then
        return string.format("%.1fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    else
        return string.format("%.1fK", n / 1e3)
    end
end

-- PARSE MPS (SAFE)
local function parseMPS(txt)
    if not txt or not txt:find("/s") then return end

    local num, suf = txt:match("%$([%d%.]+)%s*([KMB]?)")
    if not num then return end

    local v = tonumber(num)
    if not v then return end

    if suf == "K" then
        v = v * 1e3
    elseif suf == "M" then
        v = v * 1e6
    elseif suf == "B" then
        v = v * 1e9
    end

    return math.floor(v)
end

-- ======================
-- SERVER HOP (SAFE)
-- ======================
local function hopNewServer()
    local originalJob = game.JobId
    log("HOP", "Searching new server")

    while true do
        local cursor = ""
        local candidates = {}

        repeat
            local url =
                "https://games.roblox.com/v1/games/" ..
                PLACE_ID ..
                "/servers/Public?sortOrder=Asc&limit=100" ..
                (cursor ~= "" and "&cursor=" .. cursor or "")

            local ok, body = pcall(game.HttpGet, game, url)
            if not ok or not body then break end

            local data
            ok, data = pcall(HttpService.JSONDecode, HttpService, body)
            if not ok or type(data) ~= "table" then break end

            cursor = data.nextPageCursor or ""

            if type(data.data) == "table" then
                for _, srv in ipairs(data.data) do
                    if srv.id and srv.playing < srv.maxPlayers and srv.id ~= originalJob then
                        table.insert(candidates, srv.id)
                    end
                end
            end
        until #candidates > 0 or cursor == ""

        if #candidates > 0 and LocalPlayer and LocalPlayer.Parent then
            local target = candidates[math.random(#candidates)]
            log("HOP", "Teleporting")

            pcall(TeleportService.TeleportToPlaceInstance, TeleportService, PLACE_ID, target, LocalPlayer)
            task.wait(2)

            if game.JobId ~= originalJob then
                return
            end
        end

        task.wait(1.5)
    end
end

-- ======================
-- SCAN BRAINROTS (SAFE)
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
            local bestName, bestLen = nil, 0

            for _, obj in ipairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    local txt = obj.Text
                    if txt and txt ~= "" then
                        local val = parseMPS(txt)
                        if val then
                            mps = val
                        elseif not txt:lower():find("stolen")
                            and not txt:find("/s")
                            and not txt:find("%$")
                            and not txt:match("^%d")
                        then
                            if #txt > bestLen then
                                bestLen = #txt
                                bestName = txt
                            end
                        end
                    end
                end
            end

            if bestName and mps and mps >= MIN_MPS then
                local id = bestName .. mps
                if not seen[id] then
                    seen[id] = true
                    table.insert(found, { name = bestName, mps = mps })
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
-- WEBHOOK (SAFE)
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
-- HIGHLIGHTS (YOUR STYLE)
-- ======================
local function sendHighlights(hits)
    if not hits[1] then return end

    local top = hits[1]
    local lines = {}

    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("%-25s $%s/s", hits[i].name, formatMoney(hits[i].mps))
    end

    local embed = {
        title = string.format("%s ($%s/s)", top.name, formatMoney(top.mps)),
        color = 0x2ecc71,
        footer = { text = "Awesome Highlights ~ Purchase in Dashboard" }
    }

    -- ONLY add description if there are other brainrots
    if #lines > 0 then
        embed.description =
            "```text\n" .. table.concat(lines, "\n") .. "\n```"
    end

    sendWebhook(HIGHLIGHTS_WEBHOOK, {
        embeds = { embed }
    })
end


local function sendBuyers(hits)
    if not hits[1] then return end

    local top = hits[1]
    sendWebhook(BUYERS_WEBHOOK, {
        embeds = {{
            title = "Awesome Alert",
            description = string.format(
                "%s ($%s/s)\n\nJob ID:\n```%s```",
                top.name,
                formatMoney(top.mps),
                JOB_ID
            ),
            color = 0xf1c40f
        }}
    })
end

-- ======================
-- MAIN FLOW (SAFE)
-- ======================
if _G.AJ_LAST_JOB == JOB_ID then
    log("SKIP", "Same server detected")
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

_G.AJ_LAST_JOB = JOB_ID

if #hits > 0 then
    log("HIGHLIGHT", string.format(
        "%s — $%s/s (%d total)",
        hits[1].name,
        formatMoney(hits[1].mps),
        #hits
    ))

    sendHighlights(hits)
    sendBuyers(hits)
else
    log("SCAN", "No valid brainrots found")
end

hopNewServer()
