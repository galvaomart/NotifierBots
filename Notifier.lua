-- SERVICES
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- CONFIG
local PLACE_ID = game.PlaceId
local JOB_ID = game.JobId
local MIN_MPS = 10_000_000
local MAX_SCAN_TIME = 5

local BUYERS_WEBHOOK = "https://discord.com/api/webhooks/1452638384324477132/CW7VXup_c49nzxrYdVqXsJ_siUIQz3-s3edWkomA1_XoQEUe2s6wocMtHcAal99dTwlU"
local HIGHLIGHTS_WEBHOOK = "https://discord.com/api/webhooks/1450984721835102349/edA21nviAK_1xcHqfVil1REuWpMVq7dLM5nzNwdtenWkZw_2ks1VPR2L88adFid34pA5"

-- PLAYER
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- REQUEST
local request =
    request
    or http_request
    or (syn and syn.request)
    or (fluxus and fluxus.request)
    or (http and http.request)

_G.AJ_LAST_JOB = _G.AJ_LAST_JOB or nil

-- FORMAT MONEY
local function formatMoney(n)
    if n >= 1e9 then
        return string.format("%.1fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    else
        return string.format("%.1fK", n / 1e3)
    end
end

-- PARSE MPS
local function parseMPS(txt)
    if not txt or not txt:lower():find("/s") then return end

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

-- HARD SERVER HOP LOOP
local function hopNewServer()
    local originalJob = game.JobId

    while true do
        local cursor = ""
        local candidates = {}

        repeat
            local url =
                "https://games.roblox.com/v1/games/" ..
                PLACE_ID ..
                "/servers/Public?sortOrder=Asc&limit=100" ..
                (cursor ~= "" and "&cursor=" .. cursor or "")

            local ok, body = pcall(function()
                return game:HttpGet(url)
            end)
            if not ok then break end

            local data
            ok, data = pcall(function()
                return HttpService:JSONDecode(body)
            end)
            if not ok or type(data) ~= "table" then break end

            cursor = data.nextPageCursor or ""

            if type(data.data) == "table" then
                for _, srv in ipairs(data.data) do
                    if srv.id
                        and srv.playing < srv.maxPlayers
                        and srv.id ~= originalJob
                    then
                        table.insert(candidates, srv.id)
                    end
                end
            end
        until #candidates > 0 or cursor == ""

        if #candidates > 0 and LocalPlayer and LocalPlayer.Parent then
            pcall(function()
                TeleportService:TeleportToPlaceInstance(
                    PLACE_ID,
                    candidates[math.random(#candidates)],
                    LocalPlayer
                )
            end)

            task.wait(2)

            if game.JobId ~= originalJob then
                return
            end
        end

        task.wait(1.5)
    end
end

-- SCAN BRAINROTS
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
                            and not txt:lower():find("/s")
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

-- WEBHOOK
local function sendWebhook(url, payload)
    if not request then return end
    request({
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(payload)
    })
end

-- CLEAN LIST (NO CODE BLOCK, NO EMOJIS)
local function buildOtherList(hits)
    local lines = {}
    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("- %s  $%s/s", hits[i].name, formatMoney(hits[i].mps))
    end

    return #lines > 0 and "```\n" .. table.concat(lines, "\n") .. "\n```" or ""
end


local function sendHighlights(hits)
    local top = hits[1]

    local lines = {}
    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("%-25s $%s/s", hits[i].name, formatMoney(hits[i].mps))
    end

    sendWebhook(HIGHLIGHTS_WEBHOOK, {
        embeds = {{
            title = string.format("%s ($%s/s)", top.name, formatMoney(top.mps)),
            description = "```text\n" .. table.concat(lines, "\n") .. "\n```",
            color = 0x2ecc71,
            footer = {
                text = "Awesome Highlights"
            }
            -- thumbnail = { url = "IMAGE_URL" } -- optional
        }}
    })
end



-- CLEAN BUYERS (NO SERVER INFO SHOWN)
local function sendBuyers(hits)
    local top = hits[1]

    sendWebhook(BUYERS_WEBHOOK, {
        embeds = {{
            title = "Awesome Alert",
            description = string.format(
                "**%s ($%s/s)**\n\n%s\n\nJob ID:\n```%s```",
                top.name,
                formatMoney(top.mps),
                buildOtherList(hits),
                JOB_ID
            ),
            color = 0xf1c40f
        }}
    })
end

-- MAIN FLOW
if _G.AJ_LAST_JOB == JOB_ID then
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
    print(string.format(
        "[HIGHLIGHT] %s — $%s/s (%d total)",
        hits[1].name,
        formatMoney(hits[1].mps),
        #hits
    ))

    sendHighlights(hits)
    sendBuyers(hits)
else
    print("[SCAN] No valid brainrots found")
end

hopNewServer()
