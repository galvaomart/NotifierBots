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

local BUYERS_WEBHOOK = "https://discord.com/api/webhooks/1452638384324477132/CW7VXup_c49nzxrYdVqXsJ_siUIQz3-s3edWkomA1_XoQEUe2s6wocMtHcAal99dTwlU"
local HIGHLIGHTS_WEBHOOK = "https://discord.com/api/webhooks/1450984721835102349/edA21nviAK_1xcHqfVil1REuWpMVq7dLM5nzNwdtenWkZw_2ks1VPR2L88adFid34pA5"

-- ======================
-- FILTER WORDS (ONLY THING THAT MATTERS)
-- ======================
local FILTER_WORDS = {
    "secret",
    "rainbow",
    "diamond"
}

local function blockedName(name)
    local lower = name:lower()
    for _, w in ipairs(FILTER_WORDS) do
        if lower:find(w) then
            return true
        end
    end
    return false
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
-- SCAN ONCE PER SERVER
-- ======================
_G.ELEVATE_SCANNED = _G.ELEVATE_SCANNED or {}
if _G.ELEVATE_SCANNED[JOB_ID] then
    TeleportService:Teleport(PLACE_ID, LocalPlayer)
    return
end
_G.ELEVATE_SCANNED[JOB_ID] = true

-- ======================
-- UTIL
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

local function parseMPS(txt)
    local num, suf = txt:match("%$([%d%.]+)%s*([KMB]?)")
    if not num then return end
    local v = tonumber(num)
    if suf == "K" then v *= 1e3
    elseif suf == "M" then v *= 1e6
    elseif suf == "B" then v *= 1e9 end
    return math.floor(v)
end

-- ======================
-- SCAN SERVER (ONCE)
-- ======================
local function scanServer()
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return {} end

    local results = {}

    for _, gui in ipairs(debris:GetDescendants()) do
        if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui"))
            and gui:GetFullName():find("FastOverheadTemplate")
        then
            local topLabel, mps

            for _, o in ipairs(gui:GetDescendants()) do
                if o:IsA("TextLabel") and o.Text ~= "" then
                    if not topLabel
                        or o.AbsolutePosition.Y < topLabel.AbsolutePosition.Y
                    then
                        topLabel = o
                    end

                    local v = parseMPS(o.Text)
                    if v then
                        mps = v
                    end
                end
            end

            if topLabel and mps and mps >= MIN_MPS
                and not blockedName(topLabel.Text)
            then
                results[#results + 1] = {
                    name = topLabel.Text,
                    mps = mps
                }
            end
        end
    end

    table.sort(results, function(a, b)
        return a.mps > b.mps
    end)

    return results
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
-- SEND LOGS
-- ======================
local hits = scanServer()
if #hits > 0 then
    local top = hits[1]

    local lines = {}
    for i = 2, #hits do
        lines[#lines + 1] =
            string.format("%-22s $%s/s",
                hits[i].name,
                formatMoney(hits[i].mps))
    end

    sendWebhook(HIGHLIGHTS_WEBHOOK, {
        embeds = {{
            title = string.format("%s $%s/s",
                top.name,
                formatMoney(top.mps)),
            description = #lines > 0 and
                ("```text\n" .. table.concat(lines, "\n") .. "\n```")
                or nil,
            color = 0x0D0D0D,
            footer = { text = "Elevate • Highlights" }
        }}
    })

    sendWebhook(BUYERS_WEBHOOK, {
        embeds = {{
            title = string.format("%s $%s/s",
                top.name,
                formatMoney(top.mps)),
            description = string.format(
                "```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d, \"%s\", game.Players.LocalPlayer)\n```",
                PLACE_ID, JOB_ID),
            color = 0xFFFFFF,
            footer = { text = "Elevate • Private Access" }
        }}
    })
end

TeleportService:Teleport(PLACE_ID, LocalPlayer)
