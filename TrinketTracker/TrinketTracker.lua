-- TrinketTracker 1.2.1 - World of Warcraft Legion 7.3.5
-- Visual tracker only: never equips or activates items.
local addonName = ...
local TT = CreateFrame("Frame")
local db, frames = nil, {}
local runtime = {}
local glowClock, updateClock, equipmentClock = 0, 0, 0
local testUntil = 0
local seenAuras = {}

local DEFAULTS = {
    [13] = { x = -36, y = -190, scale = 1 },
    [14] = { x = 36, y = -190, scale = 1 },
}

-- Verified item data from GearScan / Legion spell information.
-- An unknown effect is shown honestly rather than inventing an ICD.
-- kind = use: on-use item; proc: player buff proc; damage: target proc;
-- passive: stats only. 'icd' always means time from PROC START, not
-- the number of seconds left after its buff ends.
local KNOWN = {
    [137541] = { name = "Moonlit Prism", kind = "use", aura = 215648,
                 buffDuration = 20, maxStacks = 20, useCooldown = 90 },
    [137485] = { name = "Infernal Writ", kind = "proc", aura = 215816,
                 buffDuration = 20, maxStacks = 20, icd = 20,
                 infernalStacks = true },
    [117358] = { name = "Mithril Wristwatch", kind = "proc", aura = 127923,
                 buffDuration = 10, icd = 55 },
    [139326] = { name = "Wriggling Sinew", kind = "use", aura = 222046,
                 buffDuration = 30, maxStacks = 10, useCooldown = 120 },
    [139321] = { name = "Swarming Plaguehive", kind = "damage" },
    [121311] = { name = "Nightmare Bloom", kind = "passive" },
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff55d9ffTrinketTracker|r: " .. tostring(msg))
end

local function Debug(msg)
    if db and db.debug then Print("[DEBUG] " .. msg) end
end

local function TimeText(seconds)
    if not seconds or seconds <= 0 then return "0" end
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
    end
    if seconds >= 10 then return tostring(math.ceil(seconds)) end
    return string.format("%.1f", seconds)
end

local function GetAura(spellID)
    if not spellID then return nil end
    for i = 1, 40 do
        -- Legion 7.3.5 has 'rank' as the second UnitBuff return value.
        local name, rank, icon, count, debuffType, duration,
              expiration, caster, stealable, personal, id = UnitBuff("player", i)
        if not name then break end
        if id == spellID then
            return {
                name = name, icon = icon, stacks = count or 0,
                duration = duration or 0, expiration = expiration or 0,
            }
        end
    end
    return nil
end

local function GetEffect(itemID)
    if not itemID then return nil end
    local base = KNOWN[itemID]
    local custom = db and db.bindings and db.bindings[tostring(itemID)]
    if not base then return custom end
    if not custom then return base end

    -- Keep previously saved bindings. In v1.0 an omitted ICD was stored
    -- as 0: for a verified item, keep the known positive ICD instead.
    -- This also works if the player confirmed the proc using AutoLearn.
    local merged = {}
    for k, v in pairs(base) do merged[k] = v end
    for k, v in pairs(custom) do
        if k ~= "icd" or (tonumber(v) or 0) > 0 or not base.icd then
            merged[k] = v
        end
    end
    return merged
end

local function DetectKind(itemID, effect, slot)
    if not itemID then return "empty" end
    if effect and effect.kind then return effect.kind end
    -- On-use is not reliably deducible for every item from GetItemSpell.
    -- IsUsableItem is a useful hint but is not treated as absolute proof.
    local spellName = GetItemSpell(itemID)
    local usable = IsUsableItem(itemID)
    local start, duration = GetInventoryItemCooldown("player", slot)
    if (start or 0) > 0 and (duration or 0) > 1.5 then
        return "use"
    end
    if spellName and usable then return "use" end
    return "unknown"
end

local function SetupGlow(w)
    w.edges = {}
    local function Edge(anchor1, anchor2, x, y, width, height)
        local t = w:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.1, 1, 0.35, 0.8)
        t:SetBlendMode("ADD")
        t:SetSize(width, height)
        t:SetPoint(anchor1, w, anchor2, x, y)
        t:Hide()
        w.edges[#w.edges + 1] = t
    end
    Edge("TOP", "TOP", 0, 2, 53, 3)
    Edge("BOTTOM", "BOTTOM", 0, -2, 53, 3)
    Edge("LEFT", "LEFT", -2, 0, 3, 53)
    Edge("RIGHT", "RIGHT", 2, 0, 3, 53)
end

local function SetGlow(w, mode)
    w.glowMode = mode
    for _, edge in ipairs(w.edges) do
        if mode == "ready" then
            edge:SetColorTexture(0.1, 1, 0.35, 0.95)
            edge:Show()
        elseif mode == "active" then
            edge:SetColorTexture(1, 0.7, 0.05, 0.95)
            edge:Show()
        else
            edge:Hide()
        end
    end
end

local function SavePosition(w)
    local cx, cy = w:GetCenter()
    local px, py = UIParent:GetCenter()
    if cx and cy and px and py then
        db.positions[w.slot].x = math.floor(cx - px + 0.5)
        db.positions[w.slot].y = math.floor(cy - py + 0.5)
    end
end

local function ApplyPosition(w)
    local p = db.positions[w.slot]
    w:ClearAllPoints()
    w:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    w:SetScale(p.scale)
end

local function MakeFrame(slot)
    local w = CreateFrame("Frame", "TrinketTrackerSlot" .. slot, UIParent)
    w.slot = slot
    w:SetSize(52, 52)
    w:SetFrameStrata("MEDIUM")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(w)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    w.icon = icon

    local shade = w:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", w, "TOPLEFT", -2, 2)
    shade:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 2, -2)
    shade:SetColorTexture(0, 0, 0, 1)

    w.center = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.center:SetPoint("CENTER", w, "CENTER", 0, 0)
    w.center:SetTextColor(1, 1, 1)
    w.center:SetShadowOffset(1, -1)

    w.stacks = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.stacks:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 2)
    w.stacks:SetTextColor(1, 1, 1)
    w.stacks:SetShadowOffset(1, -1)

    w.extra = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.extra:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 2, 2)
    w.extra:SetTextColor(1, 0.85, 0.3)
    w.extra:SetShadowOffset(1, -1)

    w.heading = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.heading:SetPoint("TOP", w, "TOP", 0, -2)
    w.heading:SetTextColor(1, 1, 1)
    w.heading:SetShadowOffset(1, -1)

    w.slotText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.slotText:SetPoint("BOTTOM", w, "TOP", 0, 6)
    w.slotText:SetText(slot == 13 and "Trinket 1" or "Trinket 2")
    w.slotText:Hide()

    SetupGlow(w)

    w:SetScript("OnDragStart", function(self)
        if db and db.unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if db then SavePosition(self) end
    end)
    w:SetScript("OnEnter", function(self)
        local id = GetInventoryItemID("player", self.slot)
        if id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetInventoryItem("player", self.slot)
            GameTooltip:Show()
        end
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frames[slot] = w
    runtime[slot] = { itemID = nil, wasActive = false }
    return w
end

local function ConfigureEdit()
    for _, slot in ipairs({13, 14}) do
        local w = frames[slot]
        w:EnableMouse(db.unlocked)
        w.slotText:SetShown(db.unlocked)
    end
end

local function WatchEquipment()
    for _, slot in ipairs({13, 14}) do
        local id = GetInventoryItemID("player", slot)
        local state = runtime[slot]
        if id ~= state.itemID then
            state.itemID = id
            state.wasActive = false
            state.procStarted = nil
            state.estimatedEnd = nil
            state.lastStacks = nil
            Debug("Slot " .. slot .. " now has item " .. tostring(id))
        end
        local texture = GetInventoryItemTexture("player", slot)
        frames[slot].icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function UpdateAurasDebug()
    if not db or not db.debug then return end
    local current = {}
    for i = 1, 40 do
        local name, rank, icon, count, dtype, dur, expires,
              caster, stealable, personal, id = UnitBuff("player", i)
        if not name then break end
        if id then
            current[id] = true
            if not seenAuras[id] then
                Debug("New buff: " .. name .. " (spellID " .. id .. ")")
            end
        end
    end
    seenAuras = current
end

local function UpdateSlot(slot, now)
    local w, state = frames[slot], runtime[slot]
    local itemID = state.itemID
    w.center:SetText("")
    w.stacks:SetText("")
    w.extra:SetText("")
    w.heading:SetText("")
    w.icon:SetDesaturated(false)
    w.icon:SetVertexColor(1, 1, 1)
    SetGlow(w, nil)

    if not itemID then
        w.icon:SetDesaturated(true)
        w.icon:SetVertexColor(0.4, 0.4, 0.4)
        w.center:SetText("-")
        return
    end

    if testUntil > now then
        if slot == 13 then
            w.heading:SetText("TEST")
            w.center:SetText(TimeText(testUntil - now))
            w.stacks:SetText("12")
            SetGlow(w, "active")
        else
            w.heading:SetText("TEST")
            w.icon:SetDesaturated(true)
            w.icon:SetVertexColor(0.6, 0.6, 0.6)
            w.center:SetText(TimeText(testUntil - now))
        end
        return
    end

    local effect = GetEffect(itemID)
    local kind = DetectKind(itemID, effect, slot)
    local buff = effect and GetAura(effect.aura) or nil
    local start, duration, enabled = GetInventoryItemCooldown("player", slot)
    local cd = math.max(0, (start or 0) + (duration or 0) - now)
    if (duration or 0) <= 1.5 then cd = 0 end

    if buff then
        if not state.wasActive then
            state.procStarted = now
            state.estimatedEnd = nil
            state.lastStacks = nil
            Debug("Effect active on " .. itemID .. ": " .. buff.name)
        end
        state.wasActive = true
        local left = math.max(0, buff.expiration - now)
        if effect and effect.infernalStacks and buff.stacks > 0 then
            -- Burning Intensity can report a refreshing 20 s aura.
            -- Estimate the actual finish from the 1 stack/second progression.
            if state.lastStacks ~= buff.stacks or not state.estimatedEnd then
                state.estimatedEnd = now + math.max(0, 21 - buff.stacks)
                state.lastStacks = buff.stacks
            end
            left = math.max(0, state.estimatedEnd - now)
            w.heading:SetText("BUFF")
        else
            w.heading:SetText("BUFF")
        end
        w.center:SetText(TimeText(left))
        if buff.stacks > 1 then
            w.stacks:SetText(tostring(buff.stacks))
        end
        if kind == "use" and cd > 0 then
            w.extra:SetText(TimeText(cd))
        elseif kind == "proc" and effect and (tonumber(effect.icd) or 0) > 0 then
            local remaining = state.procStarted and
                math.max(0, state.procStarted + effect.icd - now) or 0
            if remaining > 0 then
                w.extra:SetText(TimeText(remaining))
            end
        end
        SetGlow(w, "active")
        return
    end

    if state.wasActive then
        state.wasActive = false
        Debug("Effect ended on " .. tostring(itemID))
    end

    if kind == "use" then
        if cd > 0 then
            w.icon:SetDesaturated(true)
            w.icon:SetVertexColor(0.65, 0.65, 0.65)
            w.center:SetText(TimeText(cd))
            w.heading:SetText("CD")
        else
            w.heading:SetText("READY")
            SetGlow(w, "ready")
        end
    elseif kind == "proc" then
        w.icon:SetDesaturated(true)
        w.icon:SetVertexColor(0.65, 0.65, 0.65)
        local icd = effect and tonumber(effect.icd) or 0
        local remaining = state.procStarted and math.max(0, state.procStarted + icd - now) or 0
        if remaining > 0 then
            w.center:SetText(TimeText(remaining))
            w.heading:SetText("")
        else
            w.heading:SetText("PROC")
        end
    elseif kind == "damage" then
        w.icon:SetDesaturated(true)
        w.icon:SetVertexColor(0.7, 0.7, 0.7)
        w.heading:SetText("DMG PROC")
        -- Swarming Plaguehive has a target DoT, not a player buff.
        -- No unverified spell ID or ICD countdown is displayed.
    elseif kind == "passive" then
        w.heading:SetText("PASSIVE")
    else
        w.icon:SetDesaturated(true)
        w.icon:SetVertexColor(0.7, 0.7, 0.7)
        w.heading:SetText("UNKNOWN")
        -- Unknown proc -> never invent a numeric internal cooldown.
        if cd > 0 then w.center:SetText(TimeText(cd)) end
    end
end

local function UpdateAll()
    if not db then return end
    WatchEquipment()
    local now = GetTime()
    for _, slot in ipairs({13, 14}) do
        UpdateSlot(slot, now)
    end
end

local function Help()
    Print("/ttracker unlock | lock | reset | test | status | debug | auras")
    Print("/ttracker scale 1.2 (both) or /ttracker scale 13 1.2 (one slot)")
    Print("/ttracker bind 13 <spellID> <use|proc|passive> [ICD]")
    Print("/ttracker unbind 13  (remove override for the equipped trinket)")
    Print("/ttracker database  (show verified item mappings)")
end

local function SetScale(slot, scale)
    if slot ~= 13 and slot ~= 14 then return end
    db.positions[slot].scale = scale
    ApplyPosition(frames[slot])
end

SLASH_TRINKETTRACKER1 = "/ttracker"
SLASH_TRINKETTRACKER2 = "/trinkettracker"
SlashCmdList["TRINKETTRACKER"] = function(input)
    if not db then return end
    local args = {}
    for part in string.gmatch(input or "", "%S+") do
        args[#args + 1] = part
    end
    local cmd = (args[1] or ""):lower()

    if cmd == "unlock" then
        db.unlocked = true
        ConfigureEdit()
        Print("Unlocked: drag each icon with left mouse button.")
    elseif cmd == "lock" then
        db.unlocked = false
        ConfigureEdit()
        Print("Locked: icons no longer capture mouse clicks.")
    elseif cmd == "reset" then
        for _, slot in ipairs({13, 14}) do
            db.positions[slot] = {x = DEFAULTS[slot].x, y = DEFAULTS[slot].y, scale = 1}
            ApplyPosition(frames[slot])
        end
        Print("Positions and scales reset.")
    elseif cmd == "scale" then
        local slot, scale
        if args[3] then
            slot = tonumber(args[2])
            scale = tonumber(args[3])
        else
            scale = tonumber(args[2])
        end
        if not scale or scale < 0.5 or scale > 3 or (slot and slot ~= 13 and slot ~= 14) then
            Print("Use /ttracker scale 1.2 or /ttracker scale 13 1.2 (range 0.5 - 3).")
            return
        end
        if slot then SetScale(slot, scale)
        else SetScale(13, scale); SetScale(14, scale) end
        Print("Scale updated.")
    elseif cmd == "test" then
        if testUntil > GetTime() then
            testUntil = 0
            Print("Test mode off.")
        else
            testUntil = GetTime() + 10
            Print("Test mode active for 10 seconds.")
        end
    elseif cmd == "debug" then
        db.debug = not db.debug
        seenAuras = {}
        Print("Debug " .. (db.debug and "ON" or "OFF"))
    elseif cmd == "auras" then
        Print("Current player buffs (for mapping unknown trinkets):")
        for i = 1, 40 do
            local name, rank, icon, stacks, dtype, dur, exp,
                  caster, stealable, personal, id = UnitBuff("player", i)
            if not name then break end
            Print(name .. " = " .. tostring(id) .. " (stacks " .. tostring(stacks or 0) .. ")")
        end
    elseif cmd == "status" then
        for _, slot in ipairs({13, 14}) do
            local id = GetInventoryItemID("player", slot)
            local kind = DetectKind(id, GetEffect(id), slot)
            local effect = GetEffect(id)
            local detail = effect and effect.name or "unmapped"
            if effect and effect.aura then detail = detail .. " | buff " .. effect.aura end
            if effect and (tonumber(effect.icd) or 0) > 0 then
                detail = detail .. " | ICD " .. effect.icd .. "s"
            end
            Print("Slot " .. slot .. ": " .. (id and tostring(id) or "empty")
                  .. " | " .. kind .. " | " .. detail)
        end
        Print(db.unlocked and "Icons unlocked" or "Icons locked")
    elseif cmd == "database" or cmd == "db" then
        Print("Verified trinket database (v1.2):")
        for _, id in ipairs({117358, 137485, 137541, 139326, 139321, 121311}) do
            local e = KNOWN[id]
            local detail = ""
            if e.aura then detail = " | buff " .. e.aura end
            if e.icd then detail = detail .. " | ICD " .. e.icd .. "s" end
            if e.kind == "damage" then detail = detail .. " | enemy effect, no verified spell ID" end
            Print(e.name .. " [" .. id .. "] " .. e.kind .. detail)
        end
    elseif cmd == "bind" then
        local slot, auraID, kind, icd = tonumber(args[2]), tonumber(args[3]), args[4], tonumber(args[5]) or 0
        if (slot ~= 13 and slot ~= 14) or not auraID or auraID < 1
            or (kind ~= "use" and kind ~= "proc" and kind ~= "passive") or icd < 0 then
            Print("Usage: /ttracker bind 13 127923 proc 55")
            return
        end
        local id = GetInventoryItemID("player", slot)
        if not id then Print("No trinket in slot " .. slot); return end
        db.bindings[tostring(id)] = {aura = auraID, kind = kind, icd = icd}
        runtime[slot].wasActive = false
        runtime[slot].procStarted = nil
        Print("Saved effect binding for item " .. id .. ": spell " .. auraID .. " (" .. kind .. ")")
    elseif cmd == "unbind" then
        local slot = tonumber(args[2])
        if slot ~= 13 and slot ~= 14 then Print("Use /ttracker unbind 13 or /ttracker unbind 14"); return end
        local id = GetInventoryItemID("player", slot)
        if id then db.bindings[tostring(id)] = nil; Print("Removed override for item " .. id) end
    else
        Help()
    end
    UpdateAll()
end

TT:RegisterEvent("ADDON_LOADED")
TT:RegisterEvent("PLAYER_ENTERING_WORLD")
TT:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
TT:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
TT:RegisterEvent("UNIT_INVENTORY_CHANGED")
TT:RegisterEvent("UNIT_AURA")
TT:RegisterEvent("BAG_UPDATE_COOLDOWN")
TT:RegisterEvent("SPELL_UPDATE_COOLDOWN")

TT:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        TrinketTrackerDB = TrinketTrackerDB or {}
        db = TrinketTrackerDB
        db.positions = db.positions or {}
        db.bindings = db.bindings or {}
        if db.unlocked == nil then db.unlocked = false end
        for _, slot in ipairs({13, 14}) do
            local p = db.positions[slot]
            if type(p) ~= "table" then
                db.positions[slot] = {
                    x = DEFAULTS[slot].x, y = DEFAULTS[slot].y,
                    scale = DEFAULTS[slot].scale,
                }
            else
                p.x = tonumber(p.x) or DEFAULTS[slot].x
                p.y = tonumber(p.y) or DEFAULTS[slot].y
                p.scale = tonumber(p.scale) or 1
            end
            MakeFrame(slot)
            ApplyPosition(frames[slot])
        end
        ConfigureEdit()
        UpdateAll()
        Print("v1.2 loaded. /ttracker unlock to move icons; /ttracker db for known items.")
        return
    end
    if not db then return end
    if event == "UNIT_AURA" and arg1 ~= "player" then return end
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
    if event == "UNIT_AURA" then UpdateAurasDebug() end
    UpdateAll()
end)

TT:SetScript("OnUpdate", function(self, elapsed)
    if not db then return end
    updateClock = updateClock + elapsed
    glowClock = glowClock + elapsed
    equipmentClock = equipmentClock + elapsed
    if updateClock >= 0.12 then
        updateClock = 0
        local now = GetTime()
        for _, slot in ipairs({13, 14}) do UpdateSlot(slot, now) end
    end
    if equipmentClock >= 0.75 then
        equipmentClock = 0
        WatchEquipment() -- backup for trinket swaps that skip some events
    end
    if glowClock >= 0.08 then
        glowClock = 0
        local pulse = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(GetTime() * 5))
        for _, slot in ipairs({13, 14}) do
            local w = frames[slot]
            if w.glowMode then
                for _, edge in ipairs(w.edges) do edge:SetAlpha(pulse) end
            end
        end
    end
end)
