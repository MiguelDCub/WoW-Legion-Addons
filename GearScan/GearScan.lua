------------------------------------------------------------
-- GearScan v1.1
-- World of Warcraft Legion 7.3.5
--
-- Saves:
--   Character/spec
--   Character stats
--   Equipped gear
--   Equippable items in bags
--   Full bag contents
--   Item IDs
--   Full item links / bonus IDs
--   Effective item levels
--   Gems / enchants
--   Talents
--   Artifact
--   Relics
--   Artifact traits (cached while Artifact UI is loaded)
------------------------------------------------------------

local addonName = ...

local ADDON_VERSION = "1.1"

------------------------------------------------------------
-- INVENTORY SLOT NAMES
------------------------------------------------------------

local SLOT_NAMES = {
    [1]  = "Head",
    [2]  = "Neck",
    [3]  = "Shoulder",
    [4]  = "Shirt",
    [5]  = "Chest",
    [6]  = "Waist",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrist",
    [10] = "Hands",
    [11] = "Finger1",
    [12] = "Finger2",
    [13] = "Trinket1",
    [14] = "Trinket2",
    [15] = "Back",
    [16] = "MainHand",
    [17] = "OffHand",
    [18] = "Ranged",
    [19] = "Tabard",
}

------------------------------------------------------------
-- SAFE FUNCTION
------------------------------------------------------------

local function SafeCall(func, ...)

    if type(func) ~= "function" then
        return nil
    end

    local ok,
          a, b, c, d, e, f, g,
          h, i, j, k, l, m =
        pcall(
            func,
            ...
        )

    if not ok then
        return nil
    end

    return
        a, b, c, d, e, f, g,
        h, i, j, k, l, m
end

------------------------------------------------------------
-- SAFE FUNCTION RETURNING ALL RESULTS AS TABLE
------------------------------------------------------------

local function SafePack(func, ...)

    if type(func) ~= "function" then
        return {}
    end

    local args = {
        ...
    }

    local ok,
          result =
        pcall(
            function()

                return {
                    func(
                        unpack(args)
                    )
                }

            end
        )

    if not ok
        or type(result) ~= "table"
    then

        return {}
    end

    return result
end

------------------------------------------------------------
-- ITEM STRING
------------------------------------------------------------

local function GetItemString(link)

    if not link then
        return nil
    end

    local itemString =
        string.match(
            link,
            "|H(item:[^|]+)|h"
        )

    if itemString then
        return itemString
    end

    if string.match(
        link,
        "^item:"
    )
    then
        return link
    end

    return nil
end

------------------------------------------------------------
-- PARSE BASIC ITEM STRING
------------------------------------------------------------

local function ParseItemString(itemString)

    if not itemString then
        return {}
    end

    local fields = {
        strsplit(
            ":",
            itemString
        )
    }

    return {

        itemID =
            tonumber(
                fields[2]
            ) or 0,

        enchantID =
            tonumber(
                fields[3]
            ) or 0,

        gem1 =
            tonumber(
                fields[4]
            ) or 0,

        gem2 =
            tonumber(
                fields[5]
            ) or 0,

        gem3 =
            tonumber(
                fields[6]
            ) or 0,

        gem4 =
            tonumber(
                fields[7]
            ) or 0,
    }
end

------------------------------------------------------------
-- GEMS
------------------------------------------------------------

local function ReadGems(link)

    local gems = {}

    if not GetItemGem then
        return gems
    end

    for i = 1, 4 do

        local gemName,
              gemLink =
            GetItemGem(
                link,
                i
            )

        if gemName
            or gemLink
        then

            gems[i] = {

                name =
                    gemName,

                link =
                    gemLink,
            }
        end
    end

    return gems
end

------------------------------------------------------------
-- ITEM INFORMATION
------------------------------------------------------------

local function GetItemData(link)

    if not link then
        return nil
    end

    local itemString =
        GetItemString(
            link
        )

    if not itemString then
        return nil
    end

    local parsed =
        ParseItemString(
            itemString
        )

    --------------------------------------------------------
    -- STANDARD ITEM INFO
    --------------------------------------------------------

    local name,
          canonicalLink,
          quality,
          baseItemLevel,
          minLevel,
          itemType,
          itemSubType,
          stackCount,
          equipLoc,
          texture,
          sellPrice,
          classID,
          subclassID,
          bindType,
          expansionID,
          setID,
          isCraftingReagent =
        GetItemInfo(
            link
        )

    --------------------------------------------------------
    -- REAL ITEM LEVEL
    --------------------------------------------------------

    local effectiveItemLevel =
        nil

    if GetDetailedItemLevelInfo then

        effectiveItemLevel =
            GetDetailedItemLevelInfo(
                link
            )
    end

    if not effectiveItemLevel then

        effectiveItemLevel =
            baseItemLevel
    end

    --------------------------------------------------------
    -- ITEM STATS
    --------------------------------------------------------

    local stats = {}

    if GetItemStats then

        local returned =
            GetItemStats(
                link
            )

        if returned then

            stats =
                returned
        end
    end

    --------------------------------------------------------
    -- EQUIPPABLE
    --------------------------------------------------------

    local equippable =
        false

    if IsEquippableItem then

        equippable =
            IsEquippableItem(
                link
            )
            and true
            or false
    end

    --------------------------------------------------------
    -- RESULT
    --------------------------------------------------------

    return {

        itemID =
            parsed.itemID,

        name =
            name,

        link =
            link,

        canonicalLink =
            canonicalLink,

        itemString =
            itemString,

        quality =
            quality,

        baseItemLevel =
            baseItemLevel,

        effectiveItemLevel =
            effectiveItemLevel,

        minimumLevel =
            minLevel,

        itemType =
            itemType,

        itemSubType =
            itemSubType,

        equipLocation =
            equipLoc,

        texture =
            texture,

        classID =
            classID,

        subclassID =
            subclassID,

        bindType =
            bindType,

        expansionID =
            expansionID,

        setID =
            setID,

        isCraftingReagent =
            isCraftingReagent,

        equippable =
            equippable,

        enchantID =
            parsed.enchantID,

        gemIDs = {

            parsed.gem1,
            parsed.gem2,
            parsed.gem3,
            parsed.gem4,
        },

        gems =
            ReadGems(
                link
            ),

        stats =
            stats,
    }
end

------------------------------------------------------------
-- EQUIPPED ITEMS
------------------------------------------------------------

local function ScanEquipped()

    local equipped = {}

    for slotID = 1, 19 do

        local link =
            GetInventoryItemLink(
                "player",
                slotID
            )

        if link then

            local item =
                GetItemData(
                    link
                )

            if item then

                item.slotID =
                    slotID

                item.slotName =
                    SLOT_NAMES[slotID]
                    or
                    (
                        "Slot"
                        ..
                        slotID
                    )

                table.insert(
                    equipped,
                    item
                )
            end
        end
    end

    return equipped
end

------------------------------------------------------------
-- BAGS
--
-- Returns:
--   all bag items
--   only equippable bag items
------------------------------------------------------------

local function ScanBags()

    local items =
        {}

    local equippableItems =
        {}

    local maxBag =
        NUM_BAG_SLOTS or 4

    for bag = 0, maxBag do

        local slots =
            GetContainerNumSlots(
                bag
            )

        for slot = 1, slots do

            local link =
                GetContainerItemLink(
                    bag,
                    slot
                )

            if link then

                local item =
                    GetItemData(
                        link
                    )

                if item then

                    local count = 1

                    if GetContainerItemInfo then

                        local texture,
                              itemCount =
                            GetContainerItemInfo(
                                bag,
                                slot
                            )

                        if itemCount then

                            count =
                                itemCount
                        end
                    end

                    item.bag =
                        bag

                    item.bagSlot =
                        slot

                    item.count =
                        count

                    table.insert(
                        items,
                        item
                    )

                    ------------------------------------------------
                    -- Compact list useful for simulations
                    ------------------------------------------------

                    if item.equippable then

                        table.insert(
                            equippableItems,
                            item
                        )
                    end
                end
            end
        end
    end

    return
        items,
        equippableItems
end

------------------------------------------------------------
-- CHARACTER STATS
------------------------------------------------------------

local function ScanStats()

    --------------------------------------------------------
    -- INTELLECT
    --------------------------------------------------------

    local baseInt,
          effectiveInt,
          positiveInt,
          negativeInt =
        UnitStat(
            "player",
            4
        )

    --------------------------------------------------------
    -- ITEM LEVEL
    --------------------------------------------------------

    local averageItemLevel,
          equippedItemLevel =
        GetAverageItemLevel()

    --------------------------------------------------------
    -- RATING IDs
    --------------------------------------------------------

    local critID =
        CR_CRIT_SPELL
        or
        11

    local hasteID =
        CR_HASTE_SPELL
        or
        20

    local masteryID =
        CR_MASTERY
        or
        26

    local versID =
        CR_VERSATILITY_DAMAGE_DONE
        or
        29

    --------------------------------------------------------
    -- RAW RATINGS
    --------------------------------------------------------

    local critRating =
        GetCombatRating(
            critID
        )

    local hasteRating =
        GetCombatRating(
            hasteID
        )

    local masteryRating =
        GetCombatRating(
            masteryID
        )

    local versatilityRating =
        GetCombatRating(
            versID
        )

    --------------------------------------------------------
    -- RATING BONUS
    --------------------------------------------------------

    local critRatingBonus =
        GetCombatRatingBonus(
            critID
        )

    local hasteRatingBonus =
        GetCombatRatingBonus(
            hasteID
        )

    local masteryRatingBonus =
        GetCombatRatingBonus(
            masteryID
        )

    local versatilityRatingBonus =
        GetCombatRatingBonus(
            versID
        )

    --------------------------------------------------------
    -- CRIT BY SCHOOL
    --------------------------------------------------------

    local fireCrit =
        GetSpellCritChance
        and
        GetSpellCritChance(3)
        or
        nil

    local frostCrit =
        GetSpellCritChance
        and
        GetSpellCritChance(5)
        or
        nil

    local arcaneCrit =
        GetSpellCritChance
        and
        GetSpellCritChance(7)
        or
        nil

    --------------------------------------------------------
    -- HASTE
    --------------------------------------------------------

    local spellHaste =
        UnitSpellHaste
        and
        UnitSpellHaste(
            "player"
        )
        or
        nil

    --------------------------------------------------------
    -- MASTERY
    --------------------------------------------------------

    local masteryEffect =
        GetMasteryEffect
        and
        GetMasteryEffect()
        or
        nil

    --------------------------------------------------------
    -- SPELL POWER
    --------------------------------------------------------

    local fireSpellPower =
        GetSpellBonusDamage
        and
        GetSpellBonusDamage(3)
        or
        nil

    local frostSpellPower =
        GetSpellBonusDamage
        and
        GetSpellBonusDamage(5)
        or
        nil

    local arcaneSpellPower =
        GetSpellBonusDamage
        and
        GetSpellBonusDamage(7)
        or
        nil

    --------------------------------------------------------
    -- RESULT
    --------------------------------------------------------

    return {

        averageItemLevel =
            averageItemLevel,

        equippedItemLevel =
            equippedItemLevel,

        intellect = {

            base =
                baseInt,

            effective =
                effectiveInt,

            positiveBuff =
                positiveInt,

            negativeBuff =
                negativeInt,
        },

        ratings = {

            crit =
                critRating,

            haste =
                hasteRating,

            mastery =
                masteryRating,

            versatility =
                versatilityRating,
        },

        ratingBonusPercent = {

            crit =
                critRatingBonus,

            haste =
                hasteRatingBonus,

            mastery =
                masteryRatingBonus,

            versatility =
                versatilityRatingBonus,
        },

        percentages = {

            fireCrit =
                fireCrit,

            frostCrit =
                frostCrit,

            arcaneCrit =
                arcaneCrit,

            spellHaste =
                spellHaste,

            mastery =
                masteryEffect,

            versatility =
                versatilityRatingBonus,
        },

        spellPower = {

            fire =
                fireSpellPower,

            frost =
                frostSpellPower,

            arcane =
                arcaneSpellPower,
        },
    }
end

------------------------------------------------------------
-- SPECIALIZATION
------------------------------------------------------------

local function ScanSpecialization()

    if not GetSpecialization then
        return nil
    end

    local index =
        GetSpecialization()

    if not index then
        return nil
    end

    local id,
          name,
          description,
          icon,
          role,
          primaryStat =
        GetSpecializationInfo(
            index
        )

    return {

        index =
            index,

        id =
            id,

        name =
            name,

        description =
            description,

        icon =
            icon,

        role =
            role,

        primaryStat =
            primaryStat,
    }
end

------------------------------------------------------------
-- TALENTS
------------------------------------------------------------

local function ScanTalents()

    local selectedTalents =
        {}

    if not GetTalentInfo then
        return selectedTalents
    end

    local group =
        GetActiveSpecGroup
        and
        GetActiveSpecGroup()
        or
        1

    --------------------------------------------------------
    -- Legion:
    -- 7 tiers
    -- 3 choices each
    --------------------------------------------------------

    for tier = 1, 7 do

        for column = 1, 3 do

            local talentID,
                  name,
                  texture,
                  selected,
                  available,
                  spellID =
                GetTalentInfo(
                    tier,
                    column,
                    group
                )

            if selected then

                table.insert(
                    selectedTalents,
                    {

                        tier =
                            tier,

                        column =
                            column,

                        talentID =
                            talentID,

                        spellID =
                            spellID,

                        name =
                            name,

                        texture =
                            texture,
                    }
                )
            end
        end
    end

    return selectedTalents
end

------------------------------------------------------------
-- ========================================================
-- ARTIFACT SYSTEM
-- ========================================================
------------------------------------------------------------

------------------------------------------------------------
-- READ ARTIFACT POWERS
--
-- GetPowers normally requires Artifact UI data to be loaded.
------------------------------------------------------------

local function ReadArtifactPowers()

    local result = {}

    if not C_ArtifactUI
        or not C_ArtifactUI.GetPowers
        or not C_ArtifactUI.GetPowerInfo
    then

        return result
    end

    local powers =
        SafeCall(
            C_ArtifactUI.GetPowers
        )

    if type(powers) ~= "table" then

        return result
    end

    for _,
        powerID
        in ipairs(powers)
    do

        local a,
              b,
              c,
              d,
              e,
              f,
              g,
              h,
              i,
              j,
              k,
              l =
            SafeCall(
                C_ArtifactUI.GetPowerInfo,
                powerID
            )

        local power = {

            powerID =
                powerID,
        }

        ----------------------------------------------------
        -- Legion API versions can expose GetPowerInfo
        -- either as a table or multiple return values.
        ----------------------------------------------------

        if type(a) == "table" then

            power.spellID =
                a.spellID

            power.cost =
                a.cost

            power.currentRank =
                a.currentRank

            power.maxRank =
                a.maxRank

            power.bonusRanks =
                a.bonusRanks

            power.numMaxRankBonusFromTier =
                a.numMaxRankBonusFromTier

            power.prereqsMet =
                a.prereqsMet

            power.isStart =
                a.isStart

            power.isGoldMedal =
                a.isGoldMedal

            power.isFinal =
                a.isFinal

            power.tier =
                a.tier

            if a.position then

                power.position = {

                    x =
                        a.position.x,

                    y =
                        a.position.y,
                }
            end

        else

            ------------------------------------------------
            -- Older Legion-style multiple returns:
            --
            -- spellID
            -- cost
            -- currentRank
            -- maxRank
            -- bonusRanks
            -- x
            -- y
            -- prereqsMet
            -- isStart
            -- isGoldMedal
            -- isFinal
            -- tier (if available)
            ------------------------------------------------

            power.spellID =
                a

            power.cost =
                b

            power.currentRank =
                c

            power.maxRank =
                d

            power.bonusRanks =
                e

            power.position = {

                x =
                    f,

                y =
                    g,
            }

            power.prereqsMet =
                h

            power.isStart =
                i

            power.isGoldMedal =
                j

            power.isFinal =
                k

            power.tier =
                l
        end

        ----------------------------------------------------
        -- SPELL NAME
        ----------------------------------------------------

        if power.spellID then

            power.name =
                GetSpellInfo(
                    power.spellID
                )
        end

        ----------------------------------------------------
        -- TOTAL RANK INCLUDING RELIC BONUS
        ----------------------------------------------------

        if power.currentRank then

            power.totalRank =
                power.currentRank
                +
                (
                    power.bonusRanks
                    or
                    0
                )
        end

        table.insert(
            result,
            power
        )
    end

    return result
end

------------------------------------------------------------
-- RELIC -> AFFECTED ARTIFACT POWERS
------------------------------------------------------------

local function GetRelicAffectedPowers(
    relicSlot,
    relicLink
)

    local result =
        {}

    --------------------------------------------------------
    -- First try current Artifact UI slot
    --------------------------------------------------------

    if C_ArtifactUI
        and
        C_ArtifactUI.GetPowersAffectedByRelic
    then

        local values =
            SafePack(
                C_ArtifactUI.GetPowersAffectedByRelic,
                relicSlot
            )

        for _,
            value
            in ipairs(values)
        do

            if type(value)
                ==
                "number"
            then

                table.insert(
                    result,
                    value
                )
            end
        end
    end

    --------------------------------------------------------
    -- Fallback: ask using relic item link itself
    --------------------------------------------------------

    if #result == 0
        and
        relicLink
        and
        C_ArtifactUI
        and
        C_ArtifactUI.GetPowersAffectedByRelicItemLink
    then

        local values =
            SafePack(
                C_ArtifactUI.GetPowersAffectedByRelicItemLink,
                relicLink
            )

        for _,
            value
            in ipairs(values)
        do

            if type(value)
                ==
                "number"
            then

                table.insert(
                    result,
                    value
                )
            end
        end
    end

    return result
end

------------------------------------------------------------
-- CACHE CURRENT ARTIFACT TRAITS
--
-- Best used with Artifact Forge / trait window open.
------------------------------------------------------------

local function CacheArtifactPowers(
    silent
)

    if not C_ArtifactUI
        or
        not C_ArtifactUI.GetArtifactInfo
    then

        return false
    end

    --------------------------------------------------------
    -- Artifact currently loaded by ArtifactUI
    --------------------------------------------------------

    local itemID,
          altItemID,
          name,
          icon,
          xp,
          pointsSpent,
          quality,
          artifactAppearanceID,
          appearanceModID,
          itemAppearanceID,
          altItemAppearanceID,
          altOnTop,
          tier =
        SafeCall(
            C_ArtifactUI.GetArtifactInfo
        )

    if not itemID then

        return false
    end

    --------------------------------------------------------
    -- POWERS
    --------------------------------------------------------

    local powers =
        ReadArtifactPowers()

    if #powers == 0 then

        return false
    end

    --------------------------------------------------------
    -- ENSURE SAVED DATABASE EXISTS
    --------------------------------------------------------

    if not GearScanDB then

        GearScanDB = {}
    end

    if not GearScanDB.artifactCache then

        GearScanDB.artifactCache =
            {}
    end

    --------------------------------------------------------
    -- RELIC INFORMATION WHILE UI IS LOADED
    --------------------------------------------------------

    local relicPowerMap =
        {}

    local relicCount = 3

    if C_ArtifactUI.GetNumRelicSlots then

        local detected =
            SafeCall(
                C_ArtifactUI.GetNumRelicSlots,
                false
            )

        if detected
            and detected > 0
        then

            relicCount =
                detected
        end
    end

    for slot = 1, relicCount do

        relicPowerMap[slot] =
            GetRelicAffectedPowers(
                slot,
                nil
            )
    end

    --------------------------------------------------------
    -- SAVE
    --------------------------------------------------------

    GearScanDB.artifactCache[itemID] = {

        itemID =
            itemID,

        altItemID =
            altItemID,

        name =
            name,

        cachedAt =
            date(
                "%Y-%m-%d %H:%M:%S"
            ),

        pointsSpent =
            pointsSpent,

        tier =
            tier,

        powers =
            powers,

        relicPowerMap =
            relicPowerMap,
    }

    if not silent then

        print(
            "|cff00ff00GearScan:|r cached "
            ..
            tostring(
                #powers
            )
            ..
            " artifact traits for "
            ..
            tostring(
                name or itemID
            )
            ..
            "."
        )
    end

    return true
end

------------------------------------------------------------
-- SCAN EQUIPPED ARTIFACT
------------------------------------------------------------

local function ScanArtifact()

    if not C_ArtifactUI
        or
        not C_ArtifactUI.GetEquippedArtifactInfo
    then

        return nil
    end

    --------------------------------------------------------
    -- EQUIPPED ARTIFACT INFO
    --------------------------------------------------------

    local itemID,
          altItemID,
          name,
          icon,
          xp,
          pointsSpent,
          quality,
          artifactAppearanceID,
          appearanceModID,
          itemAppearanceID,
          altItemAppearanceID,
          altOnTop,
          tier =
        SafeCall(
            C_ArtifactUI.GetEquippedArtifactInfo
        )

    if not itemID then
        return nil
    end

    local artifact = {

        itemID =
            itemID,

        altItemID =
            altItemID,

        name =
            name,

        icon =
            icon,

        artifactPower =
            xp,

        pointsSpent =
            pointsSpent,

        quality =
            quality,

        artifactAppearanceID =
            artifactAppearanceID,

        appearanceModID =
            appearanceModID,

        itemAppearanceID =
            itemAppearanceID,

        altItemAppearanceID =
            altItemAppearanceID,

        altOnTop =
            altOnTop,

        tier =
            tier,

        relics =
            {},

        powers =
            {},
    }

    --------------------------------------------------------
    -- RELICS
    --------------------------------------------------------

    local relicCount = 3

    if C_ArtifactUI.GetEquippedArtifactNumRelicSlots then

        local detected =
            SafeCall(
                C_ArtifactUI.GetEquippedArtifactNumRelicSlots,
                false
            )

        if detected
            and
            detected > 0
        then

            relicCount =
                detected
        end

    elseif C_ArtifactUI.GetNumRelicSlots then

        local detected =
            SafeCall(
                C_ArtifactUI.GetNumRelicSlots,
                false
            )

        if detected
            and
            detected > 0
        then

            relicCount =
                detected
        end
    end

    --------------------------------------------------------
    -- READ EACH RELIC
    --------------------------------------------------------

    if C_ArtifactUI.GetEquippedArtifactRelicInfo then

        for slot = 1, relicCount do

            local relicName,
                  relicIcon,
                  slotTypeName,
                  relicLink =
                SafeCall(
                    C_ArtifactUI.GetEquippedArtifactRelicInfo,
                    slot
                )

            local relic = {

                slot =
                    slot,

                name =
                    relicName,

                icon =
                    relicIcon,

                type =
                    slotTypeName,

                link =
                    relicLink,

                affectedPowerIDs =
                    {},
            }

            if relicLink then

                relic.item =
                    GetItemData(
                        relicLink
                    )

                ------------------------------------------------
                -- Try direct lookup
                ------------------------------------------------

                relic.affectedPowerIDs =
                    GetRelicAffectedPowers(
                        slot,
                        relicLink
                    )
            end

            table.insert(
                artifact.relics,
                relic
            )
        end
    end

    --------------------------------------------------------
    -- TRY LIVE ARTIFACT UI DATA
    --------------------------------------------------------

    local viewedArtifactID =
        nil

    if C_ArtifactUI.GetArtifactInfo then

        viewedArtifactID =
            SafeCall(
                C_ArtifactUI.GetArtifactInfo
            )
    end

    local livePowers =
        {}

    --------------------------------------------------------
    -- Only use live powers if the Artifact UI is currently
    -- describing the equipped artifact.
    --------------------------------------------------------

    if viewedArtifactID
        ==
        itemID
    then

        livePowers =
            ReadArtifactPowers()
    end

    --------------------------------------------------------
    -- LIVE DATA AVAILABLE
    --------------------------------------------------------

    if #livePowers > 0 then

        artifact.powers =
            livePowers

        artifact.powersFromCache =
            false

        ----------------------------------------------------
        -- Refresh persistent cache
        ----------------------------------------------------

        if not GearScanDB then

            GearScanDB = {}
        end

        if not GearScanDB.artifactCache then

            GearScanDB.artifactCache =
                {}
        end

        local relicPowerMap =
            {}

        for slot = 1, relicCount do

            relicPowerMap[slot] =
                GetRelicAffectedPowers(
                    slot,
                    nil
                )
        end

        GearScanDB.artifactCache[itemID] = {

            itemID =
                itemID,

            altItemID =
                altItemID,

            name =
                name,

            cachedAt =
                date(
                    "%Y-%m-%d %H:%M:%S"
                ),

            pointsSpent =
                pointsSpent,

            tier =
                tier,

            powers =
                livePowers,

            relicPowerMap =
                relicPowerMap,
        }

    --------------------------------------------------------
    -- USE CACHE
    --------------------------------------------------------

    elseif GearScanDB
        and
        GearScanDB.artifactCache
        and
        GearScanDB.artifactCache[itemID]
    then

        local cache =
            GearScanDB.artifactCache[
                itemID
            ]

        artifact.powers =
            cache.powers
            or
            {}

        artifact.powersFromCache =
            true

        artifact.powersCachedAt =
            cache.cachedAt

        ----------------------------------------------------
        -- Add cached relic trait data when direct lookup
        -- wasn't available.
        ----------------------------------------------------

        if cache.relicPowerMap then

            for _,
                relic
                in ipairs(
                    artifact.relics
                )
            do

                if not relic.affectedPowerIDs
                    or
                    #relic.affectedPowerIDs == 0
                then

                    relic.affectedPowerIDs =
                        cache.relicPowerMap[
                            relic.slot
                        ]
                        or
                        {}
                end
            end
        end

    else

        artifact.powers =
            {}

        artifact.powersFromCache =
            false
    end

    --------------------------------------------------------
    -- RESOLVE RELIC POWER NAMES
    --------------------------------------------------------

    local powersByID =
        {}

    for _,
        power
        in ipairs(
            artifact.powers
        )
    do

        powersByID[
            power.powerID
        ] =
            power
    end

    for _,
        relic
        in ipairs(
            artifact.relics
        )
    do

        relic.affectedPowers =
            {}

        for _,
            powerID
            in ipairs(
                relic.affectedPowerIDs
                or
                {}
            )
        do

            local power =
                powersByID[
                    powerID
                ]

            if power then

                table.insert(
                    relic.affectedPowers,
                    {

                        powerID =
                            powerID,

                        spellID =
                            power.spellID,

                        name =
                            power.name,

                        currentRank =
                            power.currentRank,

                        bonusRanks =
                            power.bonusRanks,

                        totalRank =
                            power.totalRank,
                    }
                )

            else

                table.insert(
                    relic.affectedPowers,
                    {

                        powerID =
                            powerID,
                    }
                )
            end
        end
    end

    return artifact
end

------------------------------------------------------------
-- CLIENT INFO
------------------------------------------------------------

local function ScanClient()

    local version,
          build,
          buildDate,
          tocVersion =
        GetBuildInfo()

    return {

        version =
            version,

        build =
            build,

        buildDate =
            buildDate,

        tocVersion =
            tocVersion,

        locale =
            GetLocale
            and
            GetLocale()
            or
            nil,
    }
end

------------------------------------------------------------
-- FULL CHARACTER SCAN
------------------------------------------------------------

local function DoScan()

    local characterName =
        UnitName(
            "player"
        )

    local realmName =
        GetRealmName()

    local className,
          classFile,
          classID =
        UnitClass(
            "player"
        )

    local raceName,
          raceFile =
        UnitRace(
            "player"
        )

    --------------------------------------------------------
    -- BAGS
    --------------------------------------------------------

    local allBagItems,
          equippableBagItems =
        ScanBags()

    --------------------------------------------------------
    -- BUILD SNAPSHOT
    --------------------------------------------------------

    local snapshot = {

        gearScanVersion =
            ADDON_VERSION,

        scanTime =
            date(
                "%Y-%m-%d %H:%M:%S"
            ),

        scanTimestamp =
            time(),

        client =
            ScanClient(),

        character = {

            name =
                characterName,

            realm =
                realmName,

            level =
                UnitLevel(
                    "player"
                ),

            class =
                className,

            classFile =
                classFile,

            classID =
                classID,

            race =
                raceName,

            raceFile =
                raceFile,
        },

        specialization =
            ScanSpecialization(),

        talents =
            ScanTalents(),

        stats =
            ScanStats(),

        equipped =
            ScanEquipped(),

        ----------------------------------------------------
        -- Full bags
        ----------------------------------------------------

        bags =
            allBagItems,

        ----------------------------------------------------
        -- Useful compact subset for gear comparison
        ----------------------------------------------------

        equippableBags =
            equippableBagItems,

        artifact =
            ScanArtifact(),
    }

    --------------------------------------------------------
    -- IMPORTANT:
    --
    -- Do NOT replace GearScanDB here because doing so would
    -- delete our persistent Artifact cache.
    --------------------------------------------------------

    if not GearScanDB then

        GearScanDB = {}
    end

    if not GearScanDB.artifactCache then

        GearScanDB.artifactCache =
            {}
    end

    GearScanDB.addonVersion =
        ADDON_VERSION

    GearScanDB.latest =
        snapshot

    --------------------------------------------------------
    -- SUMMARY
    --------------------------------------------------------

    print(
        "|cff00ff00GearScan complete.|r"
    )

    print(
        "Equipped items: "
        ..
        tostring(
            #snapshot.equipped
        )
    )

    print(
        "Equippable bag items: "
        ..
        tostring(
            #snapshot.equippableBags
        )
    )

    print(
        "All bag items: "
        ..
        tostring(
            #snapshot.bags
        )
    )

    if snapshot.specialization then

        print(
            "Spec: "
            ..
            tostring(
                snapshot.specialization.name
            )
        )
    end

    if snapshot.stats
        and
        snapshot.stats.equippedItemLevel
    then

        print(
            string.format(
                "Equipped ilvl: %.2f",
                snapshot.stats.equippedItemLevel
            )
        )
    end

    if snapshot.artifact then

        print(
            "Artifact: "
            ..
            tostring(
                snapshot.artifact.name
            )
        )

        print(
            "Relics detected: "
            ..
            tostring(
                #snapshot.artifact.relics
            )
        )

        print(
            "Artifact powers detected: "
            ..
            tostring(
                #snapshot.artifact.powers
            )
        )

        if snapshot.artifact.powersFromCache then

            print(
                "|cff00ccffArtifact powers loaded from GearScan cache.|r"
            )

        elseif #snapshot.artifact.powers == 0 then

            print(
                "|cffff9900No artifact traits available yet.|r"
            )

            print(
                "Open the artifact trait window and type:"
            )

            print(
                "|cffffff00/gearscan artifact|r"
            )
        end
    end

    print(
        "|cffffff00Type /reload so WoW writes GearScan.lua to disk.|r"
    )
end

------------------------------------------------------------
-- EVENTS
------------------------------------------------------------

local frame =
    CreateFrame(
        "Frame"
    )

frame:RegisterEvent(
    "ADDON_LOADED"
)

frame:RegisterEvent(
    "ARTIFACT_UPDATE"
)

frame:RegisterEvent(
    "ARTIFACT_RELIC_INFO_RECEIVED"
)

frame:SetScript(
    "OnEvent",
    function(
        self,
        event,
        ...
    )

        ----------------------------------------------------
        -- ADDON LOADED
        ----------------------------------------------------

        if event
            ==
            "ADDON_LOADED"
        then

            local name =
                ...

            if name ~= addonName then
                return
            end

            if not GearScanDB then

                GearScanDB = {

                    addonVersion =
                        ADDON_VERSION,

                    latest =
                        nil,

                    artifactCache =
                        {},
                }

            else

                GearScanDB.addonVersion =
                    ADDON_VERSION

                if not GearScanDB.artifactCache then

                    GearScanDB.artifactCache =
                        {}
                end
            end

            print(
                "|cff00ff00GearScan v"
                ..
                ADDON_VERSION
                ..
                " loaded.|r Type /gearscan"
            )

            return
        end

        ----------------------------------------------------
        -- ARTIFACT DATA CHANGED / AVAILABLE
        ----------------------------------------------------

        if event
            ==
            "ARTIFACT_UPDATE"
            or
            event
            ==
            "ARTIFACT_RELIC_INFO_RECEIVED"
        then

            ------------------------------------------------
            -- Silent automatic attempt.
            -- If Artifact UI isn't loaded this simply does
            -- nothing.
            ------------------------------------------------

            CacheArtifactPowers(
                true
            )

            return
        end
    end
)

------------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------------

SLASH_GEARSCAN1 =
    "/gearscan"

SLASH_GEARSCAN2 =
    "/gs"

SlashCmdList["GEARSCAN"] =
function(msg)

    msg =
        string.lower(
            msg or ""
        )

    --------------------------------------------------------
    -- ARTIFACT
    --------------------------------------------------------

    if msg
        ==
        "artifact"
    then

        local success =
            CacheArtifactPowers(
                false
            )

        if success then

            print(
                "|cff00ff00Artifact traits cached successfully.|r"
            )

            print(
                "Now type |cffffff00/gearscan|r"
            )

        else

            print(
                "|cffff9900Artifact traits are not currently available.|r"
            )

            print(
                "Go to your Artifact Forge and open the trait tree."
            )

            print(
                "With the traits visible, type:"
            )

            print(
                "|cffffff00/gearscan artifact|r"
            )
        end

        return
    end

    --------------------------------------------------------
    -- STATUS
    --------------------------------------------------------

    if msg
        ==
        "status"
    then

        if GearScanDB
            and
            GearScanDB.latest
        then

            local scan =
                GearScanDB.latest

            print(
                "|cff00ff00Last GearScan:|r "
                ..
                tostring(
                    scan.scanTime
                )
            )

            print(
                "Equipped: "
                ..
                tostring(
                    #scan.equipped
                )
            )

            if scan.equippableBags then

                print(
                    "Equippable bag items: "
                    ..
                    tostring(
                        #scan.equippableBags
                    )
                )
            end

            print(
                "All bag items: "
                ..
                tostring(
                    #scan.bags
                )
            )

            if scan.artifact then

                print(
                    "Artifact: "
                    ..
                    tostring(
                        scan.artifact.name
                    )
                )

                print(
                    "Artifact powers: "
                    ..
                    tostring(
                        #(
                            scan.artifact.powers
                            or
                            {}
                        )
                    )
                )
            end

        else

            print(
                "|cffff0000No GearScan snapshot exists yet.|r"
            )
        end

        return
    end

    --------------------------------------------------------
    -- CLEAR SNAPSHOT
    --
    -- Keeps artifact cache.
    --------------------------------------------------------

    if msg
        ==
        "clear"
    then

        if not GearScanDB then

            GearScanDB =
                {}
        end

        GearScanDB.latest =
            nil

        print(
            "|cffff9900GearScan snapshot cleared.|r"
        )

        print(
            "Artifact cache was preserved."
        )

        return
    end

    --------------------------------------------------------
    -- CLEAR ARTIFACT CACHE
    --------------------------------------------------------

    if msg
        ==
        "clearartifact"
    then

        if not GearScanDB then

            GearScanDB =
                {}
        end

        GearScanDB.artifactCache =
            {}

        print(
            "|cffff9900GearScan artifact cache cleared.|r"
        )

        return
    end

    --------------------------------------------------------
    -- HELP
    --------------------------------------------------------

    if msg
        ==
        "help"
    then

        print(
            "|cff00ff00----- GearScan v"
            ..
            ADDON_VERSION
            ..
            " -----|r"
        )

        print(
            "/gearscan"
        )

        print(
            "Scan character, equipment and bags."
        )

        print(
            "/gearscan artifact"
        )

        print(
            "Cache artifact traits while artifact tree is open."
        )

        print(
            "/gearscan status"
        )

        print(
            "Show information about last snapshot."
        )

        print(
            "/gearscan clear"
        )

        print(
            "Delete latest snapshot but KEEP artifact cache."
        )

        print(
            "/gearscan clearartifact"
        )

        print(
            "Delete artifact trait cache."
        )

        return
    end

    --------------------------------------------------------
    -- DEFAULT
    --------------------------------------------------------

    DoScan()
end