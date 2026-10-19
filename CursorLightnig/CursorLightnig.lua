-- CursorLightnig 1.0.3 - Legion 7.3.5
local addonName = ...
local db, model
local driver = CreateFrame("Frame") -- Independent of the model's visibility.
local lastX, lastY, midX, midY, diagonal
local gameFrame
local step, ofsX, ofsY
local placedX, placedY
local reloadAt
local configuring, wasVisible = false, false
local reloadCount = 0
local MODEL = "spells\\lightningboltivus_missile.mdx"

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66aaffCursorLightnig:|r " .. message)
end

local function Number(value, fallback, low, high)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(low, math.min(high, value))
end

local function Screen()
    -- Preserve the original CursorTrail viewport calibration.
    local ww, wh = WorldFrame:GetSize()
    local ws = WorldFrame:GetEffectiveScale()
    local uw, uh = UIParent:GetSize()
    local us = UIParent:GetEffectiveScale()
    gameFrame = WorldFrame
    if math.floor(ww * ws) ~= math.floor(uw * us)
        or math.floor(wh * ws) ~= math.floor(uh * us) then gameFrame = UIParent end
    local scale = gameFrame:GetEffectiveScale()
    local width, height = gameFrame:GetSize()
    width, height = width * scale, height * scale
    if width <= 0 or height <= 0 then return false end
    if model then
        model:SetParent(gameFrame)
        model:ClearAllPoints()
        model:SetAllPoints(gameFrame)
    end
    midX, midY = width / 2, height / 2
    diagonal = math.sqrt(width * width + height * height)
    return true
end

local function Cursor()
    local frozen = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        or (IsMouselooking and IsMouselooking())
    if not frozen or not lastX or not lastY then
        local x, y = GetCursorPosition()
        if x and y then lastX, lastY = x, y end
    end
end

local function Position()
    if step and step > 0 and lastX and lastY
        and (lastX ~= placedX or lastY ~= placedY) then
        model:SetPosition(0, (lastX - midX) / step + ofsX,
            (lastY - midY) / step + ofsY)
        placedX, placedY = lastX, lastY
    end
end

local function Calibrate()
    if not db or not db.enabled or not Screen() then return end
    local scale = db.scale * 0.05
    model:SetScale(scale)
    step = 471 * 0.0001 * scale * diagonal
    ofsX = (-0.3 * 0.0001 * diagonal + db.offsetX) / db.scale
    ofsY = (4.3 * 0.0001 * diagonal + db.offsetY) / db.scale
    placedX, placedY = nil, nil
    Cursor()
    Position()
    model:SetAlpha(db.alpha)
end

local function CancelRecovery()
    reloadAt = nil
end

local function Schedule(delay)
    if not db or not db.enabled then return end
    local when = GetTime() + (delay or 0.1)
    if not reloadAt or when < reloadAt then reloadAt = when end
end

local function Reload()
    if not db or not db.enabled then return end
    if not Screen() then Schedule(0.5); return end
    reloadAt = nil
    reloadCount = reloadCount + 1
    configuring = true
    model:Show()
    model:SetAlpha(0)
    model:ClearModel()
    model:SetScale(1)
    model:SetPosition(0, 0, 0)
    model:SetModel(MODEL)
    model:SetCustomCamera(1)
    configuring = false
    Calibrate()
    wasVisible = UIParent:IsVisible()
end

model = CreateFrame("PlayerModel", "CursorLightnigModel", UIParent)
model:SetAllPoints(UIParent)
model:SetFrameStrata("TOOLTIP")
model:SetFrameLevel(10000)
model:EnableMouse(false)
model:Hide()

model:SetScript("OnShow", function()
    if db and not db.enabled then model:Hide(); return end
    if not configuring then Schedule(0.1) end
end)
model:SetScript("OnHide", function()
    if not configuring then Schedule(0.1) end
end)

local function SetEnabled(enabled)
    db.enabled = enabled
    CancelRecovery()
    if enabled then Reload() else model:Hide() end
end

driver:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        CursorLightnigDB = type(CursorLightnigDB) == "table" and CursorLightnigDB or {}
        db = CursorLightnigDB
        if type(db.enabled) ~= "boolean" then db.enabled = true end
        db.scale = Number(db.scale, 1, 0.05, 10)
        db.alpha = Number(db.alpha, 1, 0.05, 1)
        db.offsetX = Number(db.offsetX, 0, -10000, 10000)
        db.offsetY = Number(db.offsetY, 0, -10000, 10000)
        SetEnabled(db.enabled)
        return
    end
    if not db then return end
    if event == "PLAYER_LEAVING_WORLD" then
        CancelRecovery()
        configuring = true
        model:Hide()
        configuring = false
        wasVisible = false
        return
    end
    -- Coalesce life-cycle transitions into one recovery.
    CancelRecovery()
    Schedule(0.2)
end)

for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CINEMATIC_STOP", "MOVIE_FINISHED"}) do
    -- Some Legion clients omit optional events.
    pcall(driver.RegisterEvent, driver, event)
end

local inWorld = true
driver:HookScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then inWorld = false
    elseif event == "PLAYER_ENTERING_WORLD" then inWorld = true end
end)

driver:SetScript("OnUpdate", function(_, elapsed)
    if not db or not db.enabled or not inWorld then return end
    local now = GetTime()
    Cursor()
    Position()
    -- UIParent may be hidden temporarily. Recover only when it is visible.
    local visible = UIParent:IsVisible()
    if visible and not wasVisible then Schedule(0.1) end
    wasVisible = visible
    if not visible then return end
    if reloadAt and now >= reloadAt then Reload() end
end)

SLASH_CURSORLIGHTNIG1, SLASH_CURSORLIGHTNIG2 = "/cursorlightnig", "/cl"
SlashCmdList.CURSORLIGHTNIG = function(message)
    if not db then return end
    local args = {}
    for value in (message or ""):gmatch("%S+") do args[#args + 1] = value end
    local command = (args[1] or ""):lower()
    if command == "on" then SetEnabled(true)
    elseif command == "off" then SetEnabled(false)
    elseif command == "reload" then CancelRecovery(); if db.enabled then Reload() end
    elseif command == "scale" or command == "alpha" then
        local value = tonumber(args[2])
        if not value or value ~= value or value == math.huge or value == -math.huge then
            Print("Use /cl " .. command .. " <number>."); return
        end
        db[command] = Number(value, 1, 0.05, command == "scale" and 10 or 1)
        Calibrate()
    elseif command == "offset" then
        local x, y = tonumber(args[2]), tonumber(args[3])
        if not x or not y then Print("Use /cl offset <x> <y>."); return end
        db.offsetX, db.offsetY = Number(x, 0, -10000, 10000), Number(y, 0, -10000, 10000)
        Calibrate()
    elseif command == "resetoffset" then db.offsetX, db.offsetY = 0, 0; Calibrate()
    elseif command == "status" then
        Print("v1.0.3 | reloads=" .. reloadCount .. " | " .. (db.enabled and "ON" or "OFF") .. " | shown=" .. tostring(model:IsShown())
            .. " | visible=" .. tostring(model:IsVisible()) .. " | model=" .. tostring(model:GetModel()))
    else Print("/cl on | off | reload | status | scale <n> | alpha <n> | offset <x> <y> | resetoffset") end
end
