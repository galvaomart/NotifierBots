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
    if not txt then return end
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
-- SCAN SERVER (2-ABOVE RULE)
-- ======================
local function scanServer()
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return {} end

    local results, seen = {}, {}

    for _, gui in ipairs(debris:GetDescendants()) do
        if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui"))
            and gui:GetFullName():find("FastOverheadTemplate")
        then
            local mps, mpsLabel
            local labels = {}

            -- collect labels + find MPS
            for _, o in ipairs(gui:GetDescendants()) do
                if o:IsA("TextLabel") and o.Text ~= "" then
                    labels[#labels + 1] = o
                    local v = parseMPS(o.Text)
                    if v then
                        mps = v
                        mpsLabel = o
                    end
                end
            end

            if mps and mps >= MIN_MPS and mpsLabel then
                -- sort labels top → bottom
                table.sort(labels, function(a, b)
                    return a.AbsolutePosition.Y < b.AbsolutePosition.Y
                end)

                -- find index of MPS label
                for i = 1, #labels do
                    if labels[i] == mpsLabel and i >= 3 then
                        local name = labels[i - 2].Text
                        local id = name .. mps
                        if not seen[id] then
                            seen[id] = true
                            results[#results + 1] = {
                                name = name,
                                mps = mps
                            }
                        end
                        break
                    end
                end
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
            description = #lines > 0
                and ("```text\n" .. table.concat(lines, "\n") .. "\n```")
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
