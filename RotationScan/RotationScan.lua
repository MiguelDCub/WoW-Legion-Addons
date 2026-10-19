-- RotationScan 1.2.1 - World of Warcraft Legion 7.3.5 (26972)
-- Single-file replacement; existing RotationScan.toc and SavedVariables name work unchanged.
-- /rs start [label], stop, status, last, gear, mark [text], clear, help
-- New: /rs mode compact|detailed, /rs report, /rs artifact
-- Compact mode: direct impacts + one-second periodic buckets by actor/target/spell.
-- Detailed mode additionally records individual periodic impacts and raw cast arguments.
-- Schema 2: event.stateID refers to session.states[id]; combat.loadoutID to session.loadouts[id].
-- summary.totalDamage is offensive damage ONLY. Self/friendly/incoming/unknown are separate.
-- All amounts retain combat-log overkill; effectiveDamage subtracts positive overkill.
-- CAST_SUCCEEDED means a client notification; session.casts is the canonical cast ledger.
-- Manual casts, automatic effects and unresolved notifications have separate counters.
-- Sampled availability/idle time is descriptive, never a verdict that a player made a mistake.
-- Old saved sessions are retained, with their original version and original semantics.
-- Artifact ranks are stored as API raw values; relic bonuses are NEVER added a second time.
-- Settings and artifacts are stored inside RotationScanDB; no second addon/file required.
-- Save/backup workflow: /rs stop -> /reload -> copy SavedVariables/RotationScan.lua
-- -> /rs clear -> /reload. The addon cannot flush SavedVariables to disk on demand.

local addonName = ...
local VERSION, SCHEMA = "1.2.1", 2

local function Round(
    value,
    decimals
)
    if not value then
        return nil
    end
    decimals =
        decimals or 3
    local mult =
        10 ^ decimals
    return
        math.floor(
            value * mult + 0.5
        )
        /
        mult
end

local function GetCurrentSpec()
    if not GetSpecialization then
        return nil
    end
    local index =
        GetSpecialization()
    if not index then
        return nil
    end
    local id,
          name =
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
    }
end

local function ScanTalents()
    local result =
        {}
    if not GetTalentInfo then
        return result
    end
    local group =
        GetActiveSpecGroup
        and
        GetActiveSpecGroup()
        or
        1
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
                    result,
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
                    }
                )
            end
        end
    end
    return result
end

local function ScanStats()
    local baseInt,
          effectiveInt =
        UnitStat(
            "player",
            4
        )
    local averageItemLevel,
          equippedItemLevel =
        GetAverageItemLevel()
    local critID =
        CR_CRIT_SPELL or 11
    local hasteID =
        CR_HASTE_SPELL or 20
    local masteryID =
        CR_MASTERY or 26
    local versID =
        CR_VERSATILITY_DAMAGE_DONE or 29
    return {
        intellect =
            effectiveInt,
        equippedItemLevel =
            equippedItemLevel,
        averageItemLevel =
            averageItemLevel,
        spellPower = {
            fire =
                GetSpellBonusDamage(3),
            frost =
                GetSpellBonusDamage(5),
        },
        ratings = {
            crit =
                GetCombatRating(
                    critID
                ),
            haste =
                GetCombatRating(
                    hasteID
                ),
            mastery =
                GetCombatRating(
                    masteryID
                ),
            versatility =
                GetCombatRating(
                    versID
                ),
        },
        percentages = {
            fireCrit =
                GetSpellCritChance(3),
            frostCrit =
                GetSpellCritChance(5),
            haste =
                UnitSpellHaste(
                    "player"
                ),
            mastery =
                GetMasteryEffect(),
            versatility =
                GetCombatRatingBonus(
                    versID
                ),
        },
    }
end

local function ScanNetwork()
    if not GetNetStats then
        return nil
    end
    local bandwidthIn,
          bandwidthOut,
          latencyHome,
          latencyWorld =
        GetNetStats()
    return {
        homeLatency =
            latencyHome,
        worldLatency =
            latencyWorld,
    }
end

local SAMPLE_INTERVAL, END_GRACE, RECENT_WINDOW = 0.25, 0.75, 5
local LIMIT = { events = 60000, states = 16000, casts = 16000, buckets = 60000 }
local CRITICAL_RESERVE = 1500
local RS = { session = nil, playerGUID = nil, recentTargets = {}, units = {},
    castsByGUID = {}, pendingProcs = {}, procs = {}, recentCasts = {}, deathRing = {},
    sequence = 0, accumulator = 0 }
local frame = CreateFrame("Frame")
local BeginCombat, EndCombat, StopSession, CaptureState, StartWindow, FinishWindow
local CaptureLoadout, ResolveProcs, RefreshUnits, RecordDeath

local MANUAL = {}
for _, id in ipairs({133,11366,2948,2120,108853,194466,31661,44457,153561,190319,
    116011,2139,80353,30449,235313,212653,1953,28730,118,45438,66,110959,55342,
    205025,157980,157981,198929,44614,116,30455,84714,190356,12472,11426,
    120,122,108839,205021,205022,153595,31687,190336,759,190336,224869}) do
    MANUAL[id] = true
end
local AUTO = { [48108]=true,[48107]=true,[12654]=true,[194432]=true,[153564]=true,
    [177345]=true,[175396]=true,[155158]=true,[224637]=true,[215775]=true,
    [205345]=true,[226757]=true,[194522]=true,[217694]=true,[44461]=true,
    [208052]=true,[214399]=true,[215407]=true,[209455]=true,[8326]=true,
    [87023]=true,[220875]=true,[194461]=true,[226754]=true,[226755]=true }
local PROC = { [48108] = "hotStreak", [209455] = "marquee", [208052] = "sephuz" }
local FIRE_AURAS = { heatingUp=48107, hotStreak=48108, combustion=190319,
    runeOfPower=116014, pyreticIncantation=194329, marquee=209455,
    enhancedPyrotechnics=157644, incantersFlow=116267 }
local function Say(message) print("|cff66ccffRotationScan:|r " .. tostring(message)) end
local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a,b,c,d,e,f,g,h,i,j,k,l = pcall(fn, ...)
    if ok then return a,b,c,d,e,f,g,h,i,j,k,l end
end
local function Copy(value, depth)
    if type(value) ~= "table" then return value end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local out = {}
    for k,v in pairs(value) do out[k] = Copy(v, depth) end
    return out
end
local function Now() return RS.session and Round(GetTime()-RS.session.runtimeStart,4) or 0 end
local function Flag(flags, value)
    return flags and value and bit and bit.band(flags,value) ~= 0 or false
end
local function Mine(guid, flags)
    return guid == RS.playerGUID or Flag(flags,COMBATLOG_OBJECT_AFFILIATION_MINE)
end
local function NPCID(guid)
    if type(guid) ~= "string" then return nil end
    local kind,_,_,_,_,id = strsplit("-",guid)
    if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return tonumber(id) end
end
local function Spell(id, name)
    if not id or not RS.session then return end
    if not RS.session.spells[id] then
        RS.session.spells[id] = {name=name or Safe(GetSpellInfo,id)}
    end
end
local function Actor(guid, name, flags)
    if not guid or not RS.session then return end
    local a = RS.session.actors[guid]
    if not a then
        a = {name=name,npcID=NPCID(guid),flags=flags,firstSeen=Now()}
        RS.session.actors[guid] = a
    else
        a.name, a.flags = name or a.name, flags or a.flags
    end
    return a
end
local function Loss(kind, eventType)
    local s, t = RS.session, Now()
    if not s then return end
    s.losses.firstT = s.losses.firstT or t
    s.losses.lastT = t
    s.losses[kind] = (s.losses[kind] or 0)+1
    s.losses.byType[eventType or kind] = (s.losses.byType[eventType or kind] or 0)+1
    if kind == "events" then s.droppedEvents = s.droppedEvents+1 end
    if not RS.limitWarning then
        RS.limitWarning = true
        Say("Límite de detalle alcanzado. Los totales siguen; /rs status muestra las pérdidas.")
    end
end
local function Event(kind, data, capture, critical)
    local s = RS.session
    if not s then return end
    RS.sequence = RS.sequence+1
    local cap = LIMIT.events - (critical and 0 or CRITICAL_RESERVE)
    if #s.events >= cap then Loss("events",kind); return end
    local e = data or {}
    e.type, e.t, e.seq = kind, Now(), RS.sequence
    e.combat = e.combat or (RS.currentCombat and RS.currentCombat.index)
    e.encounter = e.encounter or (RS.encounter and RS.encounter.index)
    if capture and CaptureState then e.stateID = CaptureState(true) end
    s.events[#s.events+1] = e
    return e
end
local function Ring(kind, data)
    local t = Now()
    RS.deathRing[#RS.deathRing+1] = {t=t,type=kind,data=Copy(data)}
    while #RS.deathRing > 100 or (#RS.deathRing>0 and t-RS.deathRing[1].t>10) do
        table.remove(RS.deathRing,1)
    end
end

local function AuraMap(unit, filter)
    local out = {}
    for n=1,40 do
        local name,_,_,stacks,_,duration,expires,caster,_,_,id = UnitAura(unit,n,filter)
        if not name then break end
        if id then
            out[id] = {spellID=id,active=true,stacks=stacks or 0,duration=duration or 0,
                expires=expires or 0,remaining=Round(math.max(0,(expires or 0)-GetTime()),3),
                sourceGUID=caster and UnitGUID(caster)}
            Spell(id,name)
        end
    end
    return out
end
local function Aura(auras, id, alternate)
    local a = auras[id] or (alternate and auras[alternate])
    if not a then return {active=false} end
    return {active=true,spellID=a.spellID,stacks=a.stacks,duration=a.duration,remaining=a.remaining}
end
local function BuffList(auras)
    local list = {}
    for id,a in pairs(auras) do
        list[#list+1] = {spellID=id,stacks=a.stacks,duration=a.duration,
            expiresT=a.expires>0 and Round(a.expires-RS.session.runtimeStart,3) or nil,
            sourceGUID=a.sourceGUID}
    end
    table.sort(list,function(a,b) return a.spellID<b.spellID end)
    return list
end
local function GCD()
    local start,duration = GetSpellCooldown(61304)
    return {remaining=Round(math.max(0,(start or 0)+(duration or 0)-GetTime()),3),
        duration=duration or 0,start=start or 0}
end
local function Cooldown(id, gcd)
    local start,duration,enabled = GetSpellCooldown(id)
    if start == nil then return {spellID=id,known=false} end
    start,duration = start or 0,duration or 0
    local raw = math.max(0,start+duration-GetTime())
    local onlyGCD = raw>0 and gcd and gcd.remaining>0 and
        math.abs(start-gcd.start)<0.02 and math.abs(duration-gcd.duration)<0.02
    return {spellID=id,known=Safe(IsPlayerSpell,id) or Safe(IsSpellKnown,id) or false,
        remaining=Round(onlyGCD and 0 or raw,3),rawRemaining=Round(raw,3),
        duration=onlyGCD and 0 or duration,gcdOnly=onlyGCD and true or false,enabled=enabled}
end
local function Charges(id)
    local current,maxCharges,start,duration = Safe(GetSpellCharges,id)
    if current == nil then return nil end
    local remaining,fractional = 0,current
    if current<maxCharges and start and duration and duration>0 then
        remaining = math.max(0,start+duration-GetTime())
        fractional = math.min(maxCharges,current+math.max(0,math.min(1,1-remaining/duration)))
    end
    return {current=current,max=maxCharges,rechargeRemaining=Round(remaining,3),
        rechargeDuration=duration,fractional=Round(fractional,3)}
end
local function TargetState(unit)
    if not UnitExists(unit) then return nil end
    local guid,health,maximum = UnitGUID(unit),UnitHealth(unit),UnitHealthMax(unit)
    local attackable = UnitCanAttack("player",unit) and true or false
    local dead = UnitIsDeadOrGhost(unit) and true or false
    local inRange = Safe(IsSpellInRange,133,unit)
    return {guid=guid,name=UnitName(unit),npcID=NPCID(guid),health=health,maxHealth=maximum,
        healthPercent=maximum and maximum>0 and Round(health/maximum*100,2) or nil,
        level=UnitLevel(unit),classification=Safe(UnitClassification,unit),
        attackable=attackable,dead=dead,visible=Safe(UnitIsVisible,unit),fireballInRange=inRange}
end
RefreshUnits = function()
    RS.units = {}
    for _,unit in ipairs({"target","focus","boss1","boss2","boss3","boss4","boss5"}) do
        local guid = UnitGUID(unit)
        if guid then
            RS.units[guid] = unit
            local actor = Actor(guid,UnitName(unit))
            if actor and string.find(unit,"^boss") then
                actor.isBoss = true
                if RS.currentCombat then RS.currentCombat.bossGUIDs[guid]=true end
                if RS.encounter then RS.encounter.bossGUIDs[guid]=true end
            end
        end
    end
    for unit in pairs(RS.nameplates or {}) do
        local guid = UnitGUID(unit)
        if guid and not RS.units[guid] then RS.units[guid]=unit end
    end
end
local function RecentCount()
    local count = 0
    for guid,t in pairs(RS.recentTargets) do
        if GetTime()-t<=RECENT_WINDOW then count=count+1 else RS.recentTargets[guid]=nil end
    end
    return count
end
local function Casting()
    local name,_,_,_,startMS,endMS,_,castID,notInterruptible,spellID = Safe(UnitCastingInfo,"player")
    local channel = false
    if not name then
        name,_,_,_,startMS,endMS,_,notInterruptible = Safe(UnitChannelInfo,"player")
        channel = name and true or false
    end
    if not name then return nil end
    if not spellID then spellID=select(7,GetSpellInfo(name)) end
    return {spellID=spellID,name=name,castID=castID,channel=channel,
        startT=startMS and Round(startMS/1000-RS.session.runtimeStart,3),
        endT=endMS and Round(endMS/1000-RS.session.runtimeStart,3),notInterruptible=notInterruptible}
end
local function StateSignature(st)
    local parts = {tostring(st.moving),tostring(st.dead),tostring(st.playerHealth),
        tostring(st.target and st.target.guid),tostring(st.target and st.target.attackable),
        tostring(st.target and st.target.dead),tostring(st.target and st.target.fireballInRange),
        tostring(st.target and st.target.healthPercent and math.floor(st.target.healthPercent*2)),
        tostring(st.casting and st.casting.castID),tostring(st.casting and st.casting.spellID),
        tostring(st.gcd.remaining>0),tostring(st.recentlyDamagedTargets),
        tostring(st.fireballUsable),tostring(st.fireballLacksMana)}
    for _,boss in ipairs(st.bossTargets or {}) do
        parts[#parts+1]=boss.guid..":"..tostring(boss.healthPercent and math.floor(boss.healthPercent*2))..
            ":"..tostring(boss.attackable)..":"..tostring(boss.dead)
    end
    for _,section in ipairs({st.fire,st.frost,st.shared}) do
        if section then
            local keys = {}
            for k in pairs(section) do keys[#keys+1]=k end
            table.sort(keys)
            for _,k in ipairs(keys) do
                local v=section[k]
                if type(v)=="table" then
                    parts[#parts+1]=k..":"..tostring(v.active)..":"..tostring(v.stacks)..":"..
                        tostring(v.current)..":"..tostring(v.fractional and math.floor(v.fractional*4))..
                        ":"..tostring(v.remaining and math.ceil(v.remaining))
                end
            end
        end
    end
    return table.concat(parts,"|")
end
CaptureState = function(force)
    local s = RS.session
    if not s then return nil end
    local a,gcd = AuraMap("player","HELPFUL"),GCD()
    local spec = GetCurrentSpec()
    local usable,noMana=Safe(IsUsableSpell,133)
    local st = {t=Now(),moving=(GetUnitSpeed("player") or 0)>0,
        dead=UnitIsDeadOrGhost("player") and true or false,
        playerHealth=UnitHealth("player"),playerMaxHealth=UnitHealthMax("player"),
        mana=Safe(UnitPower,"player",0),gcd=gcd,casting=Casting(),target=TargetState("target"),
        fireballUsable=usable,fireballLacksMana=noMana,bossTargets={},
        recentlyDamagedTargets=RecentCount(),targetCountWindow=RECENT_WINDOW,
        shared={sephuz=Aura(a,208052),infernalWrit=Aura(a,215816),timeWarp=Aura(a,80353),
            temporalDisplacement=Aura(a,80354),counterspell=Cooldown(2139,gcd),
            timeWarpCooldown=Cooldown(80353,gcd)}}
    for n=1,5 do
        local boss=TargetState("boss"..n)
        if boss then
            st.bossTargets[#st.bossTargets+1]=boss
            RS.lastBossStates[boss.guid]=Copy(boss)
        end
    end
    if spec and spec.id==63 then
        st.fire={}
        for name,id in pairs(FIRE_AURAS) do st.fire[name]=Aura(a,id,name=="pyreticIncantation" and 194331 or nil) end
        st.fire.fireBlastCharges,st.fire.phoenixFlamesCharges=Charges(108853),Charges(194466)
        st.fire.combustionCooldown,st.fire.meteorCooldown=Cooldown(190319,gcd),Cooldown(153561,gcd)
        st.fire.runeCooldown=Cooldown(116011,gcd)
    elseif spec and spec.id==64 then
        st.frost={fingersOfFrost=Aura(a,44544),brainFreeze=Aura(a,190446,190447),
            icyVeins=Aura(a,12472),runeOfPower=Aura(a,116014),
            wintersChill=Aura(AuraMap("target","HARMFUL"),228358),
            icyVeinsCooldown=Cooldown(12472,gcd),frozenOrbCooldown=Cooldown(84714,gcd),
            ebonboltCooldown=Cooldown(214634,gcd)}
    end
    local sig=StateSignature(st)
    RS.observedState=st
    if not force and sig==RS.stateSignature then return RS.lastStateID end
    if #s.states>=LIMIT.states then Loss("states","STATE"); return nil end
    s.states[#s.states+1]=st
    RS.lastStateID,RS.stateSignature=#s.states,sig
    return RS.lastStateID
end

local function Equipment()
    local out={}
    for slot=1,19 do
        local link=GetInventoryItemLink("player",slot)
        if link then
            local item={itemID=GetInventoryItemID("player",slot),link=link,
                itemLevel=Safe(GetDetailedItemLevelInfo,link),stats=Safe(GetItemStats,link),gems={}}
            for n=1,4 do
                local name,gemLink=Safe(GetItemGem,link,n)
                if gemLink then item.gems[n]={name=name,link=gemLink} end
            end
            item.enchantID=tonumber(string.match(link,"item:%d+:(%d*)")) or 0
            out[slot]=item
        end
    end
    return out
end
local function Artifact()
    if not C_ArtifactUI then return nil end
    local id,alt,name,_,xp,points=Safe(C_ArtifactUI.GetEquippedArtifactInfo)
    if not id then return nil end
    local out={itemID=id,altItemID=alt,name=name,artifactPower=xp,pointsSpent=points,
        rankSemantics="raw_API_values_no_bonus_addition",relics={}}
    local link=GetInventoryItemLink("player",16)
    for slot=1,3 do
        local relicName,relicLink=Safe(GetItemGem,link,slot)
        if relicLink then out.relics[slot]={name=relicName,link=relicLink} end
    end
    local viewed=Safe(C_ArtifactUI.GetArtifactInfo)
    local equippedView=Safe(C_ArtifactUI.IsViewedArtifactEquipped)
    if viewed==id and equippedView~=false then
        local powers=Safe(C_ArtifactUI.GetPowers)
        if type(powers)=="table" and #powers>0 then
            out.powers={}
            for _,powerID in ipairs(powers) do
                local a,b,c,d,e,f,g,h,i,j,k,l=Safe(C_ArtifactUI.GetPowerInfo,powerID)
                local p={powerID=powerID}
                if type(a)=="table" then
                    for _,key in ipairs({"spellID","currentRank","maxRank","bonusRanks","isStart",
                        "tier","numMaxRankBonusFromTier","isGoldMedal","isFinal"}) do p[key]=a[key] end
                else
                    p.spellID,p.currentRank,p.maxRank,p.bonusRanks=a,c,d,e
                    p.isStart,p.isGoldMedal,p.isFinal,p.tier=i,j,k,l
                end
                if p.spellID then p.name=Safe(GetSpellInfo,p.spellID) end
                out.powers[#out.powers+1]=p
            end
            out.powersSource,out.powersCachedAt,out.fresh="viewed_equipped_artifact",date("%Y-%m-%d %H:%M:%S"),true
        end
    end
    if not out.powers and GearScanDB and GearScanDB.latest then
        local latest=GearScanDB.latest
        local character,cached=latest.character,latest.artifact
        if character and character.name==UnitName("player") and cached and cached.itemID==id then
            out.powers=Copy(cached.powers)
            if out.powers then for _,p in pairs(out.powers) do p.totalRank=nil end end
            out.powersSource,out.powersCachedAt,out.fresh="GearScan_cache_unverified",cached.powersCachedAt,false
            out.cachePointsSpent=cached.pointsSpent
        end
    end
    if not out.powers and RotationScanDB.artifactCache then
        local cached=RotationScanDB.artifactCache[id]
        if cached then
            out.powers,out.powersCachedAt=Copy(cached.powers),cached.powersCachedAt
            out.powersSource,out.fresh="RotationScan_cache_unverified",false
        end
    end
    return out
end
CaptureLoadout = function()
    local s=RS.session
    local gear,talents,artifact=Equipment(),ScanTalents(),Artifact()
    local parts={}
    for slot=1,19 do parts[#parts+1]=gear[slot] and gear[slot].link or "-" end
    for _,talent in ipairs(talents) do parts[#parts+1]=tostring(talent.talentID) end
    parts[#parts+1]=tostring(artifact and artifact.pointsSpent)
    parts[#parts+1]=tostring(artifact and artifact.powersCachedAt)
    local key=table.concat(parts,";")
    local id=RS.loadoutKeys[key]
    if not id then
        id=#s.loadouts+1
        s.loadouts[id]={equipment=gear,talents=talents,artifact=artifact,
            specialization=GetCurrentSpec(),capturedAt=Now()}
        RS.loadoutKeys[key]=id
    end
    return id
end

local function NewSummary()
    return {damageScope="hostile_or_neutral_only",totalDamage=0,effectiveDamage=0,
        directDamage=0,periodicDamage=0,overkill=0,crits=0,casts=0,
        selfDamage=0,friendlyDamage=0,unknownDamage=0,incomingDamage=0,
        castsBySpell={},automaticCastsBySpell={},unresolvedCastsBySpell={},
        damageBySpell={},damageByTarget={},incomingBySpell={},otherDamageBySpell={}}
end
local function SpellAmount(map,id,amount,critical,periodic,overkill,absorbed)
    local key=tostring(id or 0)
    local r=map[key]
    if not r then
        r={spellID=id,damage=0,hits=0,crits=0,periodicDamage=0,periodicHits=0,overkill=0,absorbed=0}
        map[key]=r
    end
    r.damage,r.hits=r.damage+amount,r.hits+1
    r.overkill=r.overkill+math.max(0,overkill or 0)
    r.absorbed=r.absorbed+(absorbed or 0)
    if critical then r.crits=r.crits+1 end
    if periodic then r.periodicDamage,r.periodicHits=r.periodicDamage+amount,r.periodicHits+1 end
end
local function AddDamageSummary(summary,d)
    if d.direction=="outgoing" then
        summary.totalDamage=summary.totalDamage+d.amount
        summary.effectiveDamage=summary.effectiveDamage+math.max(0,d.amount-math.max(0,d.overkill or 0))
        summary.overkill=summary.overkill+math.max(0,d.overkill or 0)
        local key=d.periodic and "periodicDamage" or "directDamage"
        summary[key]=summary[key]+d.amount
        if d.critical then summary.crits=summary.crits+1 end
        SpellAmount(summary.damageBySpell,d.spellID,d.amount,d.critical,d.periodic,d.overkill,d.absorbed)
        local target=summary.damageByTarget[d.targetGUID]
        if not target then target={totalDamage=0,damageBySpell={}};summary.damageByTarget[d.targetGUID]=target end
        target.totalDamage=target.totalDamage+d.amount
        SpellAmount(target.damageBySpell,d.spellID,d.amount,d.critical,d.periodic,d.overkill,d.absorbed)
    else
        local key=d.direction=="self" and "selfDamage" or d.direction=="friendly" and "friendlyDamage" or
            d.direction=="incoming" and "incomingDamage" or "unknownDamage"
        summary[key]=summary[key]+d.amount
        local map=key=="incomingDamage" and summary.incomingBySpell or summary.otherDamageBySpell
        SpellAmount(map,d.spellID,d.amount,d.critical,d.periodic,d.overkill,d.absorbed)
        if d.direction=="self" then
            summary.incomingDamage=summary.incomingDamage+d.amount
            SpellAmount(summary.incomingBySpell,d.spellID,d.amount,d.critical,d.periodic,d.overkill,d.absorbed)
        end
    end
end
local function Summaries(combat)
    local list={RS.session.summary}
    if combat then list[#list+1]=combat.summary end
    if RS.encounter then list[#list+1]=RS.encounter.summary end
    return list
end
local function AddCastSummary(summary,id,kind)
    local map=kind=="manual" and summary.castsBySpell or kind=="automatic" and
        summary.automaticCastsBySpell or summary.unresolvedCastsBySpell
    local key=tostring(id or 0)
    map[key]=map[key] or {spellID=id,casts=0}
    map[key].casts=map[key].casts+1
    if kind=="manual" then summary.casts=summary.casts+1 end
end
local function AttachEncounter(combat)
    if not RS.encounter or not combat then return end
    combat.encounterIndex=RS.encounter.index
    combat.encounter={encounterID=RS.encounter.encounterID,encounterName=RS.encounter.encounterName,
        difficultyID=RS.encounter.difficultyID,groupSize=RS.encounter.groupSize}
    if not RS.encounter.combatSet[combat.index] then
        RS.encounter.combatSet[combat.index]=true
        RS.encounter.combatIDs[#RS.encounter.combatIDs+1]=combat.index
    end
end
BeginCombat = function(reason)
    if not RS.session then return end
    RS.pendingEnd=nil
    if RS.currentCombat then AttachEncounter(RS.currentCombat);return end
    local c={index=#RS.session.combats+1,startT=Now(),startEpoch=time(),startReason=reason,
        target=TargetState("target"),loadoutID=CaptureLoadout(),stats=ScanStats(),
        startBuffs=BuffList(AuraMap("player","HELPFUL")),summary=NewSummary(),
        bossGUIDs={},availability={sampledTime=0,fireBlastCapped=0,phoenixCapped=0,
            combustionReady=0,meteorReady=0,noCastOrGCDWithAttackableTarget=0}}
    RS.currentCombat=c
    RS.session.combats[#RS.session.combats+1]=c
    RS.recentTargets={}
    AttachEncounter(c)
    -- Legion may deliver successful opener notifications just before entering combat.
    -- Attach only recent, already counted successes; never count them globally twice.
    for _,r in ipairs(RS.recentCasts) do
        if r.succeeded and not r.combat and r.successT and
            c.startT-r.successT>=0 and c.startT-r.successT<=0.25 then
            r.combat=c.index
            if r.countRecorded then AddCastSummary(c.summary,r.spellID,r.kind) end
        end
    end
    if RS.window and not RS.window.combat then RS.window.combat=c.index end
    RefreshUnits()
    Event("COMBAT_START",{reason=reason},true,true)
end
EndCombat = function(reason,at)
    local c=RS.currentCombat
    if not c then return end
    c.endT=math.max(at or Now(),c.lastDamageT or c.startT)
    c.duration=Round(math.max(0,c.endT-c.startT),4)
    c.endReason,c.empty=reason or "left_combat",c.summary.totalDamage==0 and c.summary.casts==0
    Event("COMBAT_END",{reason=c.endReason,duration=c.duration,endT=c.endT},true,true)
    RS.lastCombat,RS.currentCombat,RS.pendingEnd=c,nil,nil
    RS.lastSampleT=nil
end

StartWindow = function(source)
    if RS.window then return RS.window end
    local w={index=#RS.session.combustions+1,startT=Now(),source=source,
        combat=RS.currentCombat and RS.currentCombat.index,encounter=RS.encounter and RS.encounter.index,
        startStateID=CaptureState(true),castsBySpell={},damageBySpell={},totalDamage=0,
        meteorCasts={},meteorImpacts={}}
    RS.session.combustions[#RS.session.combustions+1]=w
    RS.window=w
    return w
end
FinishWindow = function(reason)
    local w=RS.window
    if not w then return end
    w.endT,w.endReason,w.endStateID=Now(),reason,CaptureState(true)
    w.duration=Round(w.endT-w.startT,4)
    w.damageDPS=w.duration>0 and Round(w.totalDamage/w.duration,1) or 0
    RS.window=nil
end
local function CountCast(id,kind)
    for _,summary in ipairs(Summaries(RS.currentCombat)) do
        AddCastSummary(summary,id,kind)
    end
end
local function ClassifyDestination(guid,flags)
    if guid==RS.playerGUID then return "self" end
    if Flag(flags,COMBATLOG_OBJECT_REACTION_FRIENDLY) or
        Flag(flags,COMBATLOG_OBJECT_AFFILIATION_MINE) or
        Flag(flags,COMBATLOG_OBJECT_AFFILIATION_PARTY) or
        Flag(flags,COMBATLOG_OBJECT_AFFILIATION_RAID) then return "friendly" end
    if Flag(flags,COMBATLOG_OBJECT_REACTION_HOSTILE) or Flag(flags,COMBATLOG_OBJECT_REACTION_NEUTRAL) then
        return "outgoing"
    end
    local unit=RS.units[guid]
    if unit and UnitGUID(unit)==guid and UnitCanAttack("player",unit) then return "outgoing" end
    return "unknown"
end
local function DamageBucket(d,combat)
    local second=math.floor(Now())
    if RS.bucketSecond~=second then RS.bucketSecond,RS.bucketMap=second,{} end
    local key=table.concat({d.direction,d.sourceGUID or "?",d.targetGUID or "?",d.spellID or 0,
        d.periodic and 1 or 0,combat and combat.index or 0,RS.encounter and RS.encounter.index or 0,
        RS.window and RS.window.index or 0},"|")
    local b=RS.bucketMap[key]
    if not b then
        if #RS.session.damageBuckets>=LIMIT.buckets then Loss("buckets","DAMAGE_BUCKET");return end
        b={second=second,firstT=Now(),lastT=Now(),direction=d.direction,sourceGUID=d.sourceGUID,
            targetGUID=d.targetGUID,spellID=d.spellID,periodic=d.periodic,amount=0,hits=0,crits=0,
            overkill=0,absorbed=0,combat=combat and combat.index,
            encounter=RS.encounter and RS.encounter.index,combustion=RS.window and RS.window.index}
        RS.session.damageBuckets[#RS.session.damageBuckets+1]=b
        RS.bucketMap[key]=b
    end
    b.lastT,b.amount,b.hits=Now(),b.amount+d.amount,b.hits+1
    b.crits=b.crits+(d.critical and 1 or 0)
    b.overkill,b.absorbed=b.overkill+math.max(0,d.overkill or 0),b.absorbed+(d.absorbed or 0)
end
local function RecordDamage(d)
    if not d.targetGUID and d.direction=="outgoing" then d.direction="unknown" end
    local combat=RS.currentCombat
    if d.direction=="outgoing" then
        if not combat and not UnitIsDeadOrGhost("player") then
            local previous=RS.lastCombat
            if previous and Now()-(previous.endT or 0)<=END_GRACE and
                previous.summary.damageByTarget[d.targetGUID] then
                combat=previous
                previous.endT=Now();previous.duration=Round(previous.endT-previous.startT,4)
            else
                BeginCombat("first_offensive_damage")
                combat=RS.currentCombat
            end
        end
        RS.recentTargets[d.targetGUID]=GetTime()
        if combat then combat.lastDamageT=Now() end
    end
    for _,summary in ipairs(Summaries(combat)) do AddDamageSummary(summary,d) end
    if not combat then AddDamageSummary(RS.session.unassignedSummary,d) end
    if RS.window and d.direction=="outgoing" then
        local w=RS.window
        w.totalDamage=w.totalDamage+d.amount
        SpellAmount(w.damageBySpell,d.spellID,d.amount,d.critical,d.periodic,d.overkill,d.absorbed)
        if d.spellID==153564 then
            w.meteorImpacts[#w.meteorImpacts+1]={t=Now(),targetGUID=d.targetGUID,amount=d.amount,critical=d.critical}
        end
    end
    DamageBucket(d,combat)
    if not d.periodic or RS.session.mode=="detailed" then
        local e=Copy(d)
        e.combat=combat and combat.index
        e.combustion=RS.window and RS.window.index
        local unit=RS.units[d.targetGUID]
        if unit and UnitGUID(unit)==d.targetGUID then
            e.targetHealthAfter=UnitHealth(unit);e.targetMaxHealth=UnitHealthMax(unit)
        end
        Event("DAMAGE",e,false,false)
    end
    if d.direction=="incoming" or d.direction=="self" then Ring("DAMAGE_TAKEN",d) end
end

local function CastArgs(event,...)
    local a={...}
    local id,name,guid,target
    if type(a[5])=="number" then id=a[5] end
    if not id and type(a[3])=="number" then id=a[3] end
    if event=="UNIT_SPELLCAST_SENT" and type(a[4])=="number" then id=a[4] end
    local explicitID=id~=nil
    if event=="UNIT_SPELLCAST_SENT" and type(a[5])=="string" then guid,target=a[5],a[4]
    elseif type(a[4])=="string" then guid=a[4]
    elseif type(a[2])=="string" and string.find(a[2],"^Cast%-") then guid=a[2]
    elseif event=="UNIT_SPELLCAST_SENT" and type(a[3])=="string" then guid,target=a[3],a[2] end
    if not id and type(a[2])=="string" then
        name=a[2]
        id=select(7,GetSpellInfo(name))
    end
    if id then name=GetSpellInfo(id) or name end
    if guid=="0-0-0-0-0-0000000000" then guid=nil end
    return id,name,guid,target,a,explicitID
end
local function GetCast(id,guid,create)
    local r=guid and RS.castsByGUID[guid]
    if not r and not guid then
        for n=#RS.recentCasts,1,-1 do
            local candidate=RS.recentCasts[n]
            if candidate.spellID==id and not candidate.succeeded and Now()-candidate.sentT<3 then
                r=candidate;break
            end
        end
    end
    if r or not create then return r end
    if #RS.session.casts>=LIMIT.casts then Loss("casts","CAST_LEDGER");return nil end
    r={index=#RS.session.casts+1,spellID=id,castGUID=guid,sentT=Now(),
        combat=RS.currentCombat and RS.currentCombat.index,encounter=RS.encounter and RS.encounter.index,
        notifications={},kind=AUTO[id] and "automatic" or MANUAL[id] and "manual" or "unresolved"}
    RS.session.casts[#RS.session.casts+1]=r
    if guid then RS.castsByGUID[guid]=r end
    RS.recentCasts[#RS.recentCasts+1]=r
    while #RS.recentCasts>60 do table.remove(RS.recentCasts,1) end
    return r
end
local function HandleCast(event,...)
    if select(1,...)~="player" then return end
    local id,name,guid,target,raw,explicitID=CastArgs(event,...)
    if not id and not name then return end
    Spell(id,name)
    local kind=string.gsub(event,"UNIT_SPELLCAST_","")
    local r=GetCast(id,guid,true)
    if not r then return end
    -- SENT on Legion can contain only a localized spell name. Multiple spell IDs
    -- share names (Living Bomb, Meteor, Phoenix); START/SUCCEEDED's numeric ID wins.
    if explicitID then
        if r.spellID~=id then r.inferredSpellID=r.spellID;r.spellID=id end
        r.hasExplicitSpellID=true
        if AUTO[id] then r.kind="automatic" elseif MANUAL[id] then r.kind="manual" end
    end
    r.notifications[kind]=(r.notifications[kind] or 0)+1
    if kind=="SENT" then r.targetName=target;r.decisionStateID=CaptureState(true) end
    if kind=="SENT" or kind=="START" or kind=="CHANNEL_START" then
        if not AUTO[id] then r.kind="manual" end
    end
    if kind=="START" or kind=="CHANNEL_START" then
        r.startT,r.startStateID,r.hadStart=Now(),CaptureState(true),true
        r.channel=kind=="CHANNEL_START"
        r.castInfo=Casting()
    elseif kind=="STOP" or kind=="CHANNEL_STOP" then
        r.stopT=Now()
        if r.channel and r.startT then r.channelDuration=Round(r.stopT-r.startT,4) end
    elseif kind=="FAILED" or kind=="INTERRUPTED" then
        if not r.succeeded then
            r.outcome=string.lower(kind)
            r.failureT=Now()
            r.activeDuration=r.startT and Round(Now()-r.startT,4) or 0
            r.failureStateID=CaptureState(false)
        else r.lateFailureNotifications=(r.lateFailureNotifications or 0)+1 end
    elseif kind=="SUCCEEDED" then
        if r.succeeded then return end
        r.succeeded,r.successT,r.outcome=true,Now(),"succeeded"
        r.successStateID=CaptureState(true)
        r.activeDuration=r.startT and Round(Now()-r.startT,4) or 0
        if r.kind=="manual" and not RS.currentCombat and UnitAffectingCombat("player") then
            BeginCombat("cast_in_combat")
        end
        r.combat=r.combat or (RS.currentCombat and RS.currentCombat.index)
        r.encounter=r.encounter or (RS.encounter and RS.encounter.index)
        if id==190319 then StartWindow("cast_notification") end
        CountCast(id,r.kind)
        r.countRecorded=true
        if RS.window and r.kind=="manual" then
            local key=tostring(id)
            RS.window.castsBySpell[key]=(RS.window.castsBySpell[key] or 0)+1
            if id==153561 then RS.window.meteorCasts[#RS.window.meteorCasts+1]={t=Now(),castID=r.index} end
        end
        if id==8326 then Event("SPIRIT_RELEASE",{castID=r.index},true,true) end
        if r.kind=="manual" then Ring("CAST",{castID=r.index,spellID=id}) end
    end
    -- Failed key presses are counted on the ledger, not misreported as interrupted hardcasts.
    if (kind=="FAILED" or kind=="INTERRUPTED") and r.notifications[kind]>1 then return end
    local capture=(kind=="SENT" or kind=="START" or kind=="CHANNEL_START" or kind=="SUCCEEDED") and r.kind~="automatic"
    local e={spellID=id,castGUID=guid,castID=r.index,kind=r.kind}
    if RS.session.mode=="detailed" then e.raw=raw end
    if capture then
        e.stateID=r.successStateID or r.startStateID or r.decisionStateID
    end
    Event("CAST_"..kind,e,false,r.kind=="manual" and kind=="SUCCEEDED")
end

local function ProcEvent(kind,id)
    if not PROC[id] then return end
    local t=Now()
    if kind=="SPELL_AURA_APPLIED" or kind=="SPELL_AURA_REFRESH" then
        local previous=RS.procs[id]
        if previous then
            previous.removedAt,previous.outcome=t,kind=="SPELL_AURA_REFRESH" and "refreshed" or "reapplied_unresolved"
        end
        local a=Aura(AuraMap("player","HELPFUL"),id)
        local p={index=#RS.session.procWindows+1,spellID=id,name=PROC[id],appliedAt=t,
            refresh=kind=="SPELL_AURA_REFRESH",combat=RS.currentCombat and RS.currentCombat.index,
            encounter=RS.encounter and RS.encounter.index,stateID=CaptureState(true),
            expiresAt=a.active and a.remaining and t+a.remaining or nil}
        RS.session.procWindows[#RS.session.procWindows+1]=p
        RS.procs[id]=p
    elseif kind=="SPELL_AURA_REMOVED" then
        local p=RS.procs[id]
        if p then
            p.removedAt,p.removedCombat=t,RS.currentCombat and RS.currentCombat.index
            RS.pendingProcs[#RS.pendingProcs+1]=p
            RS.procs[id]=nil
        end
    end
end
ResolveProcs = function(force)
    for n=#RS.pendingProcs,1,-1 do
        local p=RS.pendingProcs[n]
        if force or Now()-p.removedAt>=0.3 then
            local candidates={}
            if p.spellID==48108 or p.spellID==209455 then
                for _,r in ipairs(RS.recentCasts) do
                    if r.succeeded and math.abs(r.successT-p.removedAt)<=0.15 and
                        (p.spellID==48108 and (r.spellID==11366 or r.spellID==2120) or
                         p.spellID==209455 and r.spellID==11366 and r.hadStart and r.activeDuration>0.2) then
                        candidates[#candidates+1]=r.index
                    end
                end
            end
            if #candidates==1 then p.outcome,p.castID="consumed",candidates[1]
            elseif #candidates>1 then p.outcome,p.castCandidates="consumption_ambiguous",candidates
            elseif p.spellID==208052 then p.outcome="ended"
            elseif UnitIsDeadOrGhost("player") then p.outcome="removed_on_death"
            elseif p.expiresAt and p.removedAt>=p.expiresAt-0.2 then p.outcome="expired"
            else p.outcome="removed_unresolved" end
            table.remove(RS.pendingProcs,n)
        end
    end
end
RecordDeath = function(source)
    if RS.deadRecorded then return end
    RS.deadRecorded=true
    local d={t=Now(),source=source,combat=RS.currentCombat and RS.currentCombat.index,
        encounter=RS.encounter and RS.encounter.index,stateID=CaptureState(true),last10Seconds=Copy(RS.deathRing)}
    RS.session.deaths[#RS.session.deaths+1]=d
    Event("PLAYER_DEATH",{deathIndex=#RS.session.deaths,source=source},false,true)
end

local function HandleCLEU(...)
    local a={...}
    if #a==0 and CombatLogGetCurrentEventInfo then a={CombatLogGetCurrentEventInfo()} end
    local timestamp,kind=a[1],a[2]
    if not kind then return end
    local sourceGUID,sourceName,sourceFlags=a[4],a[5],a[6]
    local destGUID,destName,destFlags=a[8],a[9],a[10]
    local owned,playerSource,destPlayer=Mine(sourceGUID,sourceFlags),sourceGUID==RS.playerGUID,destGUID==RS.playerGUID
    local id,name,school=a[12],a[13],a[14]
    if kind=="UNIT_DIED" or kind=="UNIT_DESTROYED" then
        if destPlayer then RecordDeath("combat_log") end
        if destPlayer or RS.recentTargets[destGUID] or (RS.session.actors[destGUID] and RS.session.actors[destGUID].isBoss) then
            Event(kind,{targetGUID=destGUID,targetName=destName,cleuTimestamp=timestamp},false,true)
        end
        if destGUID then RS.recentTargets[destGUID]=nil end
        return
    end
    local damage=kind=="SPELL_DAMAGE" or kind=="SPELL_PERIODIC_DAMAGE" or kind=="RANGE_DAMAGE" or
        kind=="SWING_DAMAGE" or kind=="ENVIRONMENTAL_DAMAGE"
    if damage and (owned or destPlayer) then
        Actor(sourceGUID,sourceName,sourceFlags);Actor(destGUID,destName,destFlags)
        local offset=15
        if kind=="SWING_DAMAGE" then offset,id,name,school=12,6603,"Melee",1 end
        if kind=="ENVIRONMENTAL_DAMAGE" then offset,id,name,school=13,0,"Environment: "..tostring(a[12]),nil end
        Spell(id,name)
        local d={sourceGUID=sourceGUID,targetGUID=destGUID,spellID=id,spellSchool=school,
            cleuTimestamp=timestamp,amount=tonumber(a[offset]) or 0,overkill=a[offset+1],
            resisted=a[offset+3],blocked=a[offset+4],absorbed=a[offset+5],critical=a[offset+6] and true or false,
            periodic=kind=="SPELL_PERIODIC_DAMAGE",sourceIsPlayer=playerSource,
            sourceIsOwned=owned,direction=owned and ClassifyDestination(destGUID,destFlags) or "incoming"}
        RecordDamage(d)
        return
    end
    if not owned and not destPlayer then return end
    Actor(sourceGUID,sourceName,sourceFlags);Actor(destGUID,destName,destFlags);Spell(id,name)
    if kind=="SPELL_CAST_SUCCESS" and owned then
        local candidate
        for n=#RS.recentCasts,1,-1 do
            local r=RS.recentCasts[n]
            if r.spellID==id and math.abs((r.successT or r.sentT)-Now())<0.2 then candidate=r.index;break end
        end
        Event("CLEU_CAST_SUCCESS",{spellID=id,sourceGUID=sourceGUID,targetGUID=destGUID,
            relatedCastID=candidate,correlation=candidate and "time_spell_candidate" or nil,cleuTimestamp=timestamp},false,false)
    elseif string.find(kind,"^SPELL_AURA_") then
        Event(kind,{spellID=id,sourceGUID=sourceGUID,targetGUID=destGUID,auraType=a[15],stacks=a[16],
            cleuTimestamp=timestamp},false,destPlayer and (PROC[id]~=nil or id==190319))
        if destPlayer then
            ProcEvent(kind,id)
            if id==190319 then
                if kind=="SPELL_AURA_APPLIED" then
                    local w=StartWindow("aura_applied");w.auraAppliedAt=Now()
                elseif kind=="SPELL_AURA_REMOVED" then FinishWindow("aura_removed") end
            end
        end
    elseif kind=="SPELL_INTERRUPT" or kind=="SPELL_DISPEL" or kind=="SPELL_STOLEN" then
        Spell(a[15],a[16])
        Event(kind=="SPELL_INTERRUPT" and "INTERRUPT" or "DISPEL",{spellID=id,sourceGUID=sourceGUID,
            targetGUID=destGUID,extraSpellID=a[15],extraSpellSchool=a[17],cleuTimestamp=timestamp},true,true)
    elseif string.find(kind,"_MISSED$") then
        local missType=a[15]
        if kind=="SWING_MISSED" then id,missType=6603,a[12];Spell(id,"Melee") end
        Event("SPELL_MISSED",{spellID=id,sourceGUID=sourceGUID,targetGUID=destGUID,missType=missType,
            cleuTimestamp=timestamp},false,false)
    elseif (kind=="SPELL_HEAL" or kind=="SPELL_PERIODIC_HEAL") and destPlayer then
        Ring("HEAL_RECEIVED",{sourceGUID=sourceGUID,spellID=id,amount=a[15],overhealing=a[16],critical=a[18]})
    end
end

local function InstanceInfo()
    local name,kind,difficultyID,difficultyName,maxPlayers,_,_,instanceID=GetInstanceInfo()
    local info={name=name,type=kind,difficultyID=difficultyID,difficultyName=difficultyName,
        maxPlayers=maxPlayers,instanceID=instanceID}
    if C_ChallengeMode then
        local level,affixes,energized=Safe(C_ChallengeMode.GetActiveKeystoneInfo)
        info.keystoneLevel,info.affixes,info.energized=level,Copy(affixes),energized
    end
    return info
end
local function LastSession() return RS.session or RotationScanDB.sessions[#RotationScanDB.sessions] end
local function FinishEncounter(reason,success)
    local en=RS.encounter
    if not en then return end
    en.endT,en.success,en.endReason=Now(),success,reason
    en.duration=Round(en.endT-en.startT,4)
    en.endBossStates={}
    for guid in pairs(en.bossGUIDs) do
        local unit=RS.units[guid]
        local current=unit and UnitGUID(unit)==guid and TargetState(unit)
        en.endBossStates[guid]=current or Copy(RS.lastBossStates[guid])
    end
    en.combatSet=nil
    RS.encounter=nil
end
local function StartSession(label)
    if RS.session then Say("Ya hay una grabación. Usa /rs stop.");return end
    local version,build,buildDate,toc=GetBuildInfo()
    local race,raceFile=UnitRace("player")
    local s={version=VERSION,schemaVersion=SCHEMA,label=label~="" and label or "session",
        startEpoch=time(),startDate=date("%Y-%m-%d %H:%M:%S"),runtimeStart=GetTime(),finished=false,
        mode=RotationScanDB.settings.mode,character={name=UnitName("player"),realm=GetRealmName(),
            class=select(1,UnitClass("player")),classFile=select(2,UnitClass("player")),
            level=UnitLevel("player"),race=race,raceFile=raceFile},
        client={version=version,build=build,buildDate=buildDate,tocVersion=toc,locale=GetLocale()},
        instance=InstanceInfo(),network=ScanNetwork(),summary=NewSummary(),unassignedSummary=NewSummary(),
        spells={},actors={},events={},states={},casts={},loadouts={},combats={},encounters={},
        combustions={},procWindows={},damageBuckets={},deaths={},droppedEvents=0,
        losses={byType={}},sampleInterval=SAMPLE_INTERVAL,limits=Copy(LIMIT),
        interpretation={damageBuckets="one-second buckets; direct events also present, do not double-count",
            incomingIncludesSelf=true,
            stateTiming="API state when observed, not a guaranteed pre-impact server state",
            recentTargets="distinct damaged GUIDs in last 5s, not simultaneous living enemies",
            readiness="sampled availability, not a measure of avoidable mistakes"}}
    RS.session=s
    RS.currentCombat,RS.lastCombat,RS.encounter,RS.window,RS.pendingEnd=nil,nil,nil,nil,nil
    RS.playerGUID=UnitGUID("player")
    RS.castsByGUID,RS.recentCasts,RS.procs,RS.pendingProcs,RS.deathRing={},{},{},{},{}
    RS.units,RS.nameplates,RS.recentTargets,RS.loadoutKeys,RS.lastBossStates={},{},{},{},{}
    RS.sequence,RS.accumulator,RS.limitWarning=0,0,false
    RS.stateSignature,RS.lastStateID,RS.lastSampleT,RS.observedState,RS.buffSignature=nil,nil,nil,nil,nil
    RS.lastSampleID,RS.previousSample=nil,nil
    RS.bucketMap,RS.bucketSecond={},nil
    RS.deadRecorded=UnitIsDeadOrGhost("player") and true or false
    RotationScanDB.sessions[#RotationScanDB.sessions+1]=s
    -- Existing sessions are not automatically removed. /rs clear is explicit.
    local loadout=CaptureLoadout()
    s.initialLoadoutID=loadout
    s.equipment=Copy(s.loadouts[loadout].equipment)
    s.talents=Copy(s.loadouts[loadout].talents)
    s.artifact=Copy(s.loadouts[loadout].artifact)
    s.specialization,s.stats=GetCurrentSpec(),ScanStats()
    local latest=GearScanDB and GearScanDB.latest
    s.gearScanReference=latest and {scanTimestamp=latest.scanTimestamp,scanTime=latest.scanTime,
        addonVersion=GearScanDB.addonVersion}
    RefreshUnits()
    Event("SESSION_START",{label=s.label,buffs=BuffList(AuraMap("player","HELPFUL"))},true,true)
    if UnitAffectingCombat("player") then BeginCombat("recording_started_in_combat") end
    if Aura(AuraMap("player","HELPFUL"),190319).active then
        local w=StartWindow("already_active_at_session_start");w.partialStart=true
    end
    Say("Grabando "..s.label.." ("..s.mode.."). /rs stop para terminar.")
end
StopSession = function(reason,quiet)
    local s=RS.session
    if not s then if not quiet then Say("No hay una grabación activa.") end;return end
    ResolveProcs(true)
    for _,r in ipairs(s.casts) do
        if not r.outcome then r.outcome=r.stopT and "stopped_without_success" or "unresolved_at_recording_end" end
    end
    FinishWindow(reason or "session_stopped")
    if RS.currentCombat then EndCombat(reason or "session_stopped") end
    FinishEncounter(reason or "session_stopped",nil)
    for _,p in pairs(RS.procs) do p.outcome="active_at_recording_end";p.recordingEndT=Now() end
    Event("SESSION_STOP",{reason=reason or "manual"},true,true)
    s.duration,s.endEpoch,s.endDate=Now(),time(),date("%Y-%m-%d %H:%M:%S")
    s.finished,s.stopReason=true,reason or "manual"
    s.interrupted=reason=="logout_or_reload" or nil
    s.activeCombatTime=0
    for _,c in ipairs(s.combats) do s.activeCombatTime=s.activeCombatTime+(c.duration or 0) end
    s.activeCombatTime=Round(s.activeCombatTime,4)
    s.activeDPS=s.activeCombatTime>0 and Round(s.summary.totalDamage/s.activeCombatTime,1) or 0
    s.elapsedDPS=s.duration>0 and Round(s.summary.totalDamage/s.duration,1) or 0
    s.validation={combatDamage=0,unassignedDamage=s.unassignedSummary.totalDamage}
    for _,c in ipairs(s.combats) do s.validation.combatDamage=s.validation.combatDamage+c.summary.totalDamage end
    s.validation.damageReconciles=s.validation.combatDamage+s.validation.unassignedDamage==s.summary.totalDamage
    RS.session=nil
    if not quiet then
        Say("Guardado en memoria: "..#s.combats.." combates, "..tostring(s.activeDPS).." DPS ofensivo activo.")
        Say("/reload para guardar en disco; después copia de seguridad, /rs clear y /reload.")
    end
end

local function Sample()
    if not RS.session then return end
    RefreshUnits()
    local id=CaptureState(false)
    local st=RS.observedState
    for spellID,p in pairs(RS.procs) do
        local observed=spellID==208052 and st.shared.sephuz or
            st.fire and (spellID==48108 and st.fire.hotStreak or spellID==209455 and st.fire.marquee)
        if observed and observed.active and observed.remaining and observed.remaining>0 then
            p.expiresAt=st.t+observed.remaining
            p.expirySource="observed_unit_aura"
        end
    end
    if id~=RS.lastSampleID and id then Event("STATE_SAMPLE",{stateID=id},false,false);RS.lastSampleID=id end
    local now=Now()
    local dt=RS.lastSampleT and math.max(0,math.min(SAMPLE_INTERVAL*2,now-RS.lastSampleT)) or 0
    RS.lastSampleT=now
    local c,previous=RS.currentCombat,RS.previousSample
    if c and previous and dt>0 and previous.target and previous.target.attackable and
        not previous.target.dead and not previous.dead then
        local v=c.availability
        v.sampledTime=v.sampledTime+dt
        if previous.fire then
            local f=previous.fire
            if f.fireBlastCharges and f.fireBlastCharges.current==f.fireBlastCharges.max then v.fireBlastCapped=v.fireBlastCapped+dt end
            if f.phoenixFlamesCharges and f.phoenixFlamesCharges.current==f.phoenixFlamesCharges.max then v.phoenixCapped=v.phoenixCapped+dt end
            if f.combustionCooldown.known and f.combustionCooldown.remaining==0 and not f.combustion.active then v.combustionReady=v.combustionReady+dt end
            if f.meteorCooldown.known and f.meteorCooldown.remaining==0 then v.meteorReady=v.meteorReady+dt end
        end
        if not previous.casting and previous.gcd.remaining==0 then
            v.noCastOrGCDWithAttackableTarget=v.noCastOrGCDWithAttackableTarget+dt
        end
    end
    RS.previousSample=st
    for _,r in ipairs(RS.recentCasts) do
        if not r.succeeded and r.stopT and now-r.stopT>0.3 and not r.outcome then
            r.outcome="stopped_without_success"
            r.activeDuration=r.startT and Round(r.stopT-r.startT,4) or 0
        end
    end
    ResolveProcs(false)
    if RS.pendingEnd and now-RS.pendingEnd>=END_GRACE and not UnitAffectingCombat("player") then
        EndCombat("left_combat",RS.pendingEnd)
    end
end
frame:SetScript("OnUpdate",function(_,elapsed)
    if not RS.session then return end
    RS.accumulator=RS.accumulator+elapsed
    if RS.accumulator>=SAMPLE_INTERVAL then RS.accumulator=0;Sample() end
end)

local function BuffsChanged()
    local list=BuffList(AuraMap("player","HELPFUL"))
    local parts={}
    for _,a in ipairs(list) do parts[#parts+1]=a.spellID..":"..a.stacks..":"..tostring(a.expiresT)..":"..tostring(a.sourceGUID) end
    local signature=table.concat(parts,";")
    if signature~=RS.buffSignature then
        RS.buffSignature=signature
        Event("BUFFS_CHANGED",{buffs=list},false,false)
    end
end
local function OnEvent(_,event,...)
    if event=="ADDON_LOADED" then
        if select(1,...)~=addonName then return end
        RotationScanDB=RotationScanDB or {}
        RotationScanDB.sessions=RotationScanDB.sessions or {}
        RotationScanDB.settings=RotationScanDB.settings or {mode="compact"}
        if RotationScanDB.settings.mode~="detailed" then RotationScanDB.settings.mode="compact" end
        RotationScanDB.artifactCache=RotationScanDB.artifactCache or {}
        RotationScanDB.version=VERSION
        for _,s in ipairs(RotationScanDB.sessions) do
            if s.finished==false then s.finished,s.interrupted=true,true end
        end
        Say("v"..VERSION.." lista. /rs help")
        return
    end
    if not RS.session then return end
    if event=="PLAYER_LOGOUT" then StopSession("logout_or_reload",true)
    elseif event=="PLAYER_REGEN_DISABLED" then BeginCombat("regen_disabled")
    elseif event=="PLAYER_REGEN_ENABLED" then RS.pendingEnd=Now()
    elseif event=="COMBAT_LOG_EVENT_UNFILTERED" then HandleCLEU(...)
    elseif string.find(event,"^UNIT_SPELLCAST_") then HandleCast(event,...)
    elseif event=="PLAYER_TARGET_CHANGED" then
        RefreshUnits();Event("TARGET_CHANGED",{target=TargetState("target")},true,false)
    elseif event=="ENCOUNTER_START" then
        if RS.encounter then FinishEncounter("replaced_by_new_encounter",nil) end
        local id,name,difficulty,size=...
        local en={index=#RS.session.encounters+1,encounterID=id,encounterName=name,
            difficultyID=difficulty,groupSize=size,startT=Now(),summary=NewSummary(),
            bossGUIDs={},combatIDs={},combatSet={},instance=InstanceInfo()}
        RS.encounter=en;RS.session.encounters[#RS.session.encounters+1]=en
        AttachEncounter(RS.currentCombat);RefreshUnits()
        Event("ENCOUNTER_START",{encounterID=id,encounterName=name,difficultyID=difficulty,groupSize=size},true,true)
    elseif event=="ENCOUNTER_END" then
        local id,name,difficulty,size,success=...
        RefreshUnits()
        Event("ENCOUNTER_END",{encounterID=id,encounterName=name,difficultyID=difficulty,groupSize=size,success=success},true,true)
        FinishEncounter("encounter_end",success)
    elseif event=="INSTANCE_ENCOUNTER_ENGAGE_UNIT" then RefreshUnits()
    elseif event=="PLAYER_DEAD" then RecordDeath("PLAYER_DEAD")
    elseif event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then
        local ghost=Safe(UnitIsGhost,"player") and true or false
        Event(event,{ghost=ghost,dead=UnitIsDeadOrGhost("player") and true or false},true,true)
        if not UnitIsDeadOrGhost("player") then RS.deadRecorded=false end
    elseif event=="UNIT_AURA" and select(1,...)=="player" then BuffsChanged()
    elseif event=="PLAYER_STARTED_MOVING" or event=="PLAYER_STOPPED_MOVING" then Event(event,nil,true,false)
    elseif event=="UI_ERROR_MESSAGE" then
        local code,message=...
        Event("UI_ERROR",{errorCode=type(code)=="number" and code or nil,message=message or code,
            relatedCastID=RS.recentCasts[#RS.recentCasts] and RS.recentCasts[#RS.recentCasts].index,
            correlation="temporal_only"},false,false)
    elseif event=="NAME_PLATE_UNIT_ADDED" then RS.nameplates[select(1,...)]=true;RefreshUnits()
    elseif event=="NAME_PLATE_UNIT_REMOVED" then RS.nameplates[select(1,...)]=nil
    elseif event=="PLAYER_EQUIPMENT_CHANGED" or event=="PLAYER_SPECIALIZATION_CHANGED" or event=="PLAYER_TALENT_UPDATE" then
        Event("LOADOUT_CHANGED",{loadoutID=CaptureLoadout(),stats=ScanStats()},true,true)
    elseif event=="ZONE_CHANGED_NEW_AREA" or event=="CHALLENGE_MODE_START" or event=="CHALLENGE_MODE_COMPLETED" then
        Event(event,{instance=InstanceInfo()},true,true)
    end
end
frame:SetScript("OnEvent",OnEvent)
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGOUT","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "COMBAT_LOG_EVENT_UNFILTERED","UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP","PLAYER_TARGET_CHANGED","ENCOUNTER_START","ENCOUNTER_END",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT","PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST","UNIT_AURA",
    "PLAYER_STARTED_MOVING","PLAYER_STOPPED_MOVING","UI_ERROR_MESSAGE","NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED","PLAYER_EQUIPMENT_CHANGED","PLAYER_SPECIALIZATION_CHANGED","PLAYER_TALENT_UPDATE",
    "ZONE_CHANGED_NEW_AREA","CHALLENGE_MODE_START","CHALLENGE_MODE_COMPLETED"}) do
    -- Optional events on private clients must not prevent addon loading.
    Safe(frame.RegisterEvent,frame,event)
end

local function PrintSummary(s)
    if not s then Say("Todavía no hay sesiones.");return end
    Say(tostring(s.label).." | "..tostring(s.startDate).." | versión "..tostring(s.version))
    Say("Combates: "..#(s.combats or {}).." | Eventos: "..#(s.events or {}).." | Perdidos: "..(s.droppedEvents or 0))
    Say("Daño: "..tostring(s.summary and s.summary.totalDamage or 0).." | DPS activo: "..tostring(s.activeDPS or "grabando"))
    if s.schemaVersion==2 then
        Say("Daño propio: "..s.summary.selfDamage.." | Aliados: "..s.summary.friendlyDamage.." | Recibido: "..s.summary.incomingDamage)
        Say("Estados: "..#s.states.." | Lanzamientos: "..#s.casts.." | Muertes: "..#s.deaths)
        if s.losses.firstT then Say("Detalle incompleto desde t="..s.losses.firstT.."; consultar losses.") end
    else Say("Sesión antigua: el daño conserva los criterios de su versión.") end
end
local function PrintGear()
    local s=LastSession()
    local c=s and s.combats and s.combats[#s.combats]
    if not c then Say("No hay un combate guardado.");return end
    local loadout=c.loadoutID and s.loadouts and s.loadouts[c.loadoutID] or c
    Say("Equipo del último combate #"..c.index)
    for _,slot in ipairs({1,2,6,9,11,12,13,14,16}) do
        local item=loadout.equipment and loadout.equipment[slot]
        if item then Say("Slot "..slot..": "..item.link) end
    end
end
local function PrintReport()
    local s=LastSession()
    PrintSummary(s)
    if not s or s.schemaVersion~=2 then return end
    for _,en in ipairs(s.encounters) do
        local duration=en.duration or (RS.session==s and Now()-en.startT) or 0
        Say(en.encounterName..": "..tostring(Round(duration,1)).." s | "..
            tostring(duration>0 and Round(en.summary.totalDamage/duration,1) or 0).." DPS del encuentro")
    end
    for _,w in ipairs(s.combustions) do
        Say("Combustion #"..w.index..": Pyro "..tostring(w.castsBySpell["11366"] or 0)..
            " | impactos Meteor "..#w.meteorImpacts.." | daño durante aura "..w.totalDamage)
    end
end
SLASH_ROTATIONSCAN1,SLASH_ROTATIONSCAN2="/rotationscan","/rs"
SlashCmdList["ROTATIONSCAN"]=function(msg)
    local command,rest=string.match(msg or "","^(%S*)%s*(.-)$")
    command=string.lower(command or "")
    if not RotationScanDB then Say("El addon todavía está cargando.");return end
    if command=="start" then StartSession(rest)
    elseif command=="stop" then StopSession()
    elseif command=="status" then
        if RS.session then PrintSummary(RS.session) else Say("Sin grabación activa. Sesiones: "..#RotationScanDB.sessions) end
    elseif command=="last" then PrintSummary(LastSession())
    elseif command=="gear" then PrintGear()
    elseif command=="report" then PrintReport()
    elseif command=="mark" then
        if RS.session then Event("MARKER",{text=rest~="" and rest or "marker"},true,true);Say("Marca añadida.")
        else Say("Primero usa /rs start.") end
    elseif command=="clear" then
        if RS.session then Say("Primero /rs stop; guarda con /reload y haz copia antes de borrar.")
        else RotationScanDB.sessions={};Say("Sesiones borradas. /reload guarda el registro limpio.") end
    elseif command=="mode" then
        if RS.session then Say("Cambia el modo antes de comenzar una grabación.")
        elseif rest=="compact" or rest=="detailed" then RotationScanDB.settings.mode=rest;Say("Modo: "..rest)
        else Say("Modo actual: "..RotationScanDB.settings.mode..". /rs mode compact|detailed") end
    elseif command=="artifact" then
        local artifact=Artifact()
        if artifact and artifact.fresh and artifact.powers then
            RotationScanDB.artifactCache[artifact.itemID]=Copy(artifact)
            Say("Rasgos del artefacto equipado actualizados, sin sumar dos veces las reliquias.")
            if RS.session then Event("ARTIFACT_SNAPSHOT",{artifact=artifact},false,true) end
        else Say("Abre el panel del artefacto equipado y vuelve a ejecutar /rs artifact. La caché se conserva como no verificada.") end
    else
        Say("v"..VERSION.." | /rs start [etiqueta], stop, status, last, gear, mark [texto], report, artifact, clear")
        Say("/rs mode compact (normal) | /rs mode detailed (pruebas cortas con ticks individuales)")
        Say("Al terminar: /rs stop -> /reload -> copia de seguridad -> /rs clear -> /reload")
    end
end
