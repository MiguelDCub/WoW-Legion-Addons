-- LegendarySetFix v1.4 (Legion 7.3.5)
-- Uses the proven native EquipmentManager_RunAction unequip operation.
-- Verifies each legendary reaches a bag before applying the destination set.

local LSF = CreateFrame("Frame")
local job
local queued
local nativeBusy = false
local nativeSince = 0
local nextStart = 0
local debugMode = false
local lastError = nil

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd28bffLegendarySetFix:|r " .. tostring(message))
end

local function Debug(message)
    if debugMode then
        Print("[DEBUG] " .. tostring(message))
    end
end

local function GetSetID(setName)
    local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
    for _, id in ipairs(ids) do
        if C_EquipmentSet.GetEquipmentSetInfo(id) == setName then
            return id
        end
    end
    return nil
end

local function SetIsEquipped(id)
    local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
    return equipped == true
end

local function IsLegendaryEquipped(slot)
    local quality = GetInventoryItemQuality("player", slot)
    if quality == nil then
        local link = GetInventoryItemLink("player", slot)
        if link then
            quality = select(3, GetItemInfo(link))
        end
    end
    return quality == 5
end

local function GetEmptyNormalBagSlots()
    local slots = {}
    for bag = 0, NUM_BAG_SLOTS do
        local _, family = GetContainerNumFreeSlots(bag)
        if family == 0 then
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                if not GetContainerItemID(bag, slot) then
                    slots[#slots + 1] = { bag = bag, slot = slot }
                end
            end
        end
    end
    return slots
end

-- Read the destination set every time; no item names or slot whitelist.
-- A value of 1 means ignored; 0 means empty; -1 means unavailable.
local function BuildPlan(id)
    local locations = C_EquipmentSet.GetItemLocations(id)
    local targetIDs = C_EquipmentSet.GetItemIDs(id)
    if not locations or not targetIDs then
        return nil, "Could not read the destination Equipment Set."
    end

    local actions = {}
    for slot = 1, 19 do
        if IsLegendaryEquipped(slot) then
            local location = locations[slot]
            local oldID = GetInventoryItemID("player", slot)
            local targetID = targetIDs[slot]

            if location == nil then
                return nil, "No saved slot information for legendary in slot " .. slot
            elseif location == -1 then
                return nil, "Target item unavailable for legendary slot " .. slot
            elseif location == 1 then
                -- Intentionally ignored by the destination set.
            elseif location == 0 or (location > 1 and targetID ~= oldID) then
                if location > 1 and not targetID then
                    return nil, "Target item ID unknown for slot " .. slot
                end
                actions[#actions + 1] = {
                    slot = slot,
                    oldID = oldID,
                    oldLink = GetInventoryItemLink("player", slot),
                    targetID = targetID,
                }
            end
        end
    end

    table.sort(actions, function(a, b) return a.slot < b.slot end)
    return actions
end

local function EndJob(success, message)
    local name = job and job.name or "unknown"
    job = nil
    nextStart = GetTime() + 0.12

    if message then Print(message) end
    if not success then
        lastError = message
        queued = nil
        Print("Swap stopped. Inspect your equipment before retrying.")
    else
        lastError = nil
        Debug("Completed " .. name)
    end
end

local function StartSwap(name)
    if InCombatLockdown() then
        Print("Cannot change equipment during combat.")
        return
    end
    if GetCursorInfo() then
        Print("Empty your cursor before switching sets.")
        return
    end

    local id = GetSetID(name)
    if not id then
        Print("Equipment Set not found: " .. name)
        return
    end
    if SetIsEquipped(id) then
        Debug(name .. " already equipped.")
        return
    end

    local actions, err = BuildPlan(id)
    if not actions then
        Print(err)
        return
    end

    -- The native equipment manager chooses the destination bag slot itself.
    -- Ensure we have enough normal bag space before starting the swap.
    local emptySlots = GetEmptyNormalBagSlots()
    if #emptySlots < #actions then
        Print("Need " .. #actions .. " empty normal bag slots; found " .. #emptySlots .. ".")
        return
    end
    if #actions > 0 and type(EquipmentManager_RunAction) ~= "function" then
        Print("WoW EquipmentManager_RunAction is unavailable; nothing was changed.")
        return
    end

    job = {
        id = id,
        name = name,
        actions = actions,
        index = 1,
        phase = "release",
        waiting = false,
        nextAt = GetTime(),
        nativeResult = nil,
    }
    lastError = nil

    Debug("Set " .. name .. ": removing " .. #actions .. " conflicting legendary item(s).")
    for _, action in ipairs(actions) do
        Debug("Slot " .. action.slot .. ": item " .. tostring(action.oldID)
            .. " -> native unequip (target ID " .. tostring(action.targetID) .. ")")
    end
end

local function RequestSwap(name)
    if InCombatLockdown() then
        Print("Cannot change equipment during combat.")
        return
    end
    if job or nativeBusy or GetTime() < nextStart then
        if job and job.name == name then
            queued = nil
            Debug("Already switching to " .. name)
        else
            queued = name
            Print("Queued: " .. name)
        end
        return
    end
    StartSwap(name)
end

-- The native Equipment Manager handles inventory placement and item locks.
-- The exact action has been verified manually on this Legion 7.3.5 client:
-- EquipmentManager_RunAction({ type = 2, invSlot = 9 })
local function ReleaseNative(action)
    if GetCursorInfo() then
        return false, "Cursor not empty before releasing slot " .. action.slot
    end
    if GetInventoryItemID("player", action.slot) ~= action.oldID then
        return false, "Slot " .. action.slot .. " changed since preparation."
    end
    if IsInventoryItemLocked and IsInventoryItemLocked(action.slot) then
        return nil, "locked"
    end
    if type(EquipmentManager_RunAction) ~= "function" then
        return false, "EquipmentManager_RunAction is unavailable."
    end

    -- This only REQUESTS an unequip; successful execution does not prove success.
    local ok, err = pcall(EquipmentManager_RunAction, {
        type = 2,
        invSlot = action.slot,
    })
    if not ok then
        return false, "Native unequip error in slot " .. action.slot .. ": " .. tostring(err)
    end

    Debug("Requested native unequip for slot " .. action.slot
        .. " (item " .. tostring(action.oldID) .. "); awaiting confirmation.")
    return true
end

local function FindItemInBags(itemID)
    if not itemID then return nil end
    for bag = 0, NUM_BAG_SLOTS do
        for bagSlot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemID(bag, bagSlot) == itemID then
                return bag, bagSlot
            end
        end
    end
    return nil
end

local function HandleRelease(now)
    local action = job.actions[job.index]
    if not action then
        if GetCursorInfo() then
            EndJob(false, "Cursor occupied before applying set.")
            return
        end

        job.phase = "apply"
        job.deadline = now + 5.0
        Debug("Applying complete set " .. job.name)

        local oldJob = job
        local ok = C_EquipmentSet.UseEquipmentSet(job.id)
        if job ~= oldJob then return end
        if not ok then
            EndJob(false, "WoW rejected the Equipment Set application.")
        end
        return
    end

    if job.waiting then
        local current = GetInventoryItemID("player", action.slot)
        local bag, bagSlot = FindItemInBags(action.oldID)
        if current == nil and bag ~= nil and not GetCursorInfo() then
            Debug("Confirmed native unequip: slot " .. action.slot
                .. " empty; item " .. tostring(action.oldID)
                .. " found in bag " .. bag .. ":" .. bagSlot .. ".")
            job.index = job.index + 1
            job.waiting = false
            job.nextAt = now + 0.08
        elseif current ~= nil and current ~= action.oldID then
            EndJob(false, "Unexpected item in slot " .. action.slot .. " during release.")
        elseif now >= job.deadline then
            EndJob(false, "Native unequip not confirmed for slot " .. action.slot
                .. " (equipped=" .. tostring(current)
                .. ", foundInBag=" .. tostring(bag ~= nil) .. ").")
        end
        return
    end

    if now < job.nextAt then return end

    local ok, err = ReleaseNative(action)
    if ok == nil and err == "locked" then
        -- Wait briefly for inventory lock to clear before attempting the move.
        if not job.lockDeadline then job.lockDeadline = now + 3.0 end
        if now >= job.lockDeadline then
            EndJob(false, "Item in slot " .. action.slot .. " remained locked.")
        else
            job.nextAt = now + 0.10
        end
        return
    end
    job.lockDeadline = nil
    if not ok then
        EndJob(false, err)
        return
    end

    job.waiting = true
    job.deadline = now + 5.0
end

LSF:RegisterEvent("PLAYER_LOGIN")
LSF:RegisterEvent("EQUIPMENT_SWAP_PENDING")
LSF:RegisterEvent("EQUIPMENT_SWAP_FINISHED")

LSF:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Print("v1.4 loaded. Use /lsf SetName or /lsf inspect SetName.")
    elseif event == "EQUIPMENT_SWAP_PENDING" then
        nativeBusy = true
        nativeSince = GetTime()
        Debug("Native Equipment Set change pending.")
    elseif event == "EQUIPMENT_SWAP_FINISHED" then
        local success, setID = ...
        nativeBusy = false
        nativeSince = 0
        if job and job.phase == "apply" and (setID == job.id or setID == nil) then
            job.nativeResult = success == true or success == 1
            Debug("Native Equipment Set completion: " .. tostring(success))
        end
    end
end)

LSF:SetScript("OnUpdate", function()
    local now = GetTime()

    -- Native equipment change watchdog: the event can be absent on some clients.
    if nativeBusy and now - nativeSince > 6.0 then
        Debug("Native busy watchdog expired.")
        nativeBusy = false
    end

    if not job then
        if queued and not nativeBusy and now >= nextStart and not InCombatLockdown() then
            local name = queued
            queued = nil
            StartSwap(name)
        end
        return
    end

    if InCombatLockdown() then
        EndJob(false, "Interrupted by combat.")
        return
    end

    if job.phase == "release" then
        HandleRelease(now)
    elseif job.phase == "apply" then
        if SetIsEquipped(job.id) then
            EndJob(true, "Equipped: " .. job.name)
        elseif job.nativeResult == false then
            EndJob(false, "WoW reported Equipment Set swap failure.")
        elseif now >= job.deadline then
            EndJob(false, "Equipment Set was not confirmed within 5 seconds.")
        end
    end
end)

SLASH_LEGENDARYSETFIX1 = "/lsf"
SlashCmdList["LEGENDARYSETFIX"] = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$")
    local lower = command:lower()

    if command == "" then
        Print("Usage: /lsf <EquipmentSetName>")
        Print("Extra: /lsf inspect <SetName> | status | debug | cancel")
    elseif lower == "debug" then
        debugMode = not debugMode
        Print("Debug " .. (debugMode and "ON" or "OFF"))
    elseif lower == "status" then
        if job then
            Print("Active " .. job.name .. " | phase " .. job.phase
                .. " | slot " .. tostring(job.actions[job.index] and job.actions[job.index].slot or "none"))
        else
            Print("No active swap.")
        end
        Print("Queued: " .. tostring(queued or "none")
            .. " | native busy: " .. tostring(nativeBusy))
        if lastError then Print("Last error: " .. lastError) end
    elseif lower == "cancel" then
        queued = nil
        Print("Queued request cleared; active swap continues.")
    elseif lower:sub(1, 8) == "inspect " then
        local name = command:sub(9):match("^%s*(.-)%s*$")
        local id = GetSetID(name)
        if not id then
            Print("Equipment Set not found: " .. name)
            return
        end
        local plan, err = BuildPlan(id)
        if not plan then
            Print(err)
            return
        end
        local free = #GetEmptyNormalBagSlots()
        Print("Inspect " .. name .. ": " .. #plan
            .. " legendary slot(s) to free, " .. free .. " free normal bag slots.")
        for _, action in ipairs(plan) do
            Print("  Slot " .. action.slot .. ": " .. tostring(action.oldLink or action.oldID)
                .. " -> target ID " .. tostring(action.targetID))
        end
    else
        RequestSwap(command)
    end
end
