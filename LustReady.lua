local ADDON_NAME, LR = ...
local ADDON_ABBR = "LR"

-------------------------------------------------------------------------------
--- Configuration
-------------------------------------------------------------------------------

local addon_color = "ffffff77"
local r, g, b = 255/255, 255/255, 119/255

local      font_size = 36
local  handle_offset = 0
local     mover_size = 32
local padding_bottom = -3

local testing  = false
local verbose  = false
local inCombat = false

local petAvailable = false
local petSpellSlot
local ownedDrums = {}
local pendingItemData = {}
local refreshTimer

local COUNTDOWN_THRESHOLD = 30
local UPDATE_INTERVAL = 0.5

-------------------------------------------------------------------------------
--- Spell Data
-------------------------------------------------------------------------------

local SATED_DEBUFFS = {
    [57723]  = true, -- Exhaustion
    [57724]  = true, -- Sated
    [80354]  = true, -- Temporal Displacement
    [95809]  = true, -- Insanity (Hunter Pet)
    [160455] = true, -- Fatigued (Hunter Pet)
    [264689] = true, -- Fatigued (Hunter Pet)
    [390435] = true, -- Exhaustion
}

local HEROISM_SPELLS = {
    32182,  -- Shaman: Heroism
    2825,   -- Shaman: Bloodlust
    80353,  -- Mage: Time Warp
    390386, -- Evoker: Fury of the Aspects
    466904, -- Marksmanship Hunter: Harrier's Cry
}

-- Primal Rage belongs to the active pet, not the player's Command Pet spell.
local PRIMAL_RAGE = 264667

local DRUM_ITEMS = {
    244639, -- Void-Touched Drums (Midnight)
    219905, -- Thunderous Drums (The War Within)
}

-------------------------------------------------------------------------------
--- State Queries
-------------------------------------------------------------------------------

local function IsInGroupInstance()
    local _, instanceType = IsInInstance()

    return instanceType == "party"
        or instanceType == "raid"
        or instanceType == "scenario"
        or instanceType == "pvp"
end

local function IsPetAvailable()
    return UnitExists("pet") and not UnitIsDeadOrGhost("pet")
end

local function FindPlayerHeroismSpell()
    for _, spellID in ipairs(HEROISM_SPELLS) do
        if C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player) then
            return spellID
        end
    end

    return nil
end

local function FindPetHeroismSlot()
    local spellBank = Enum.SpellBookSpellBank.Pet
    if not petAvailable or not C_SpellBook.IsSpellKnown(PRIMAL_RAGE, spellBank) then
        return nil
    end

    local numPetSpells = C_SpellBook.HasPetSpells() or 0
    for slot = 1, numPetSpells do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, spellBank)
        if info and info.spellID == PRIMAL_RAGE then
            return slot
        end
    end

    return nil
end

function LR:RefreshSources()
    petAvailable = IsPetAvailable()
    LR.heroismSpellID = FindPlayerHeroismSpell()
    petSpellSlot = nil
    wipe(ownedDrums)

    if not LR.heroismSpellID then
        petSpellSlot = FindPetHeroismSlot()
        if petSpellSlot then
            LR.heroismSpellID = PRIMAL_RAGE
        end
    end

    -- Prefer the class/pet ability, even while it is on cooldown.
    if LR.heroismSpellID then return end

    for _, itemID in ipairs(DRUM_ITEMS) do
        -- The default count excludes all banks.
        if C_Item.GetItemCount(itemID) > 0 then
            ownedDrums[#ownedDrums + 1] = itemID
            if not C_Item.IsItemDataCachedByID(itemID) and not pendingItemData[itemID] then
                pendingItemData[itemID] = true
                C_Item.RequestLoadItemDataByID(itemID)
            end
        end
    end
end

local function GetSatedRemaining()
    local longestRemaining = 0
    for spellID in pairs(SATED_DEBUFFS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if issecretvalue(aura) then return nil end

        if aura then
            -- Any known lockout blocks the combat alert, without reading timing.
            if inCombat then return nil end

            local expirationTime = aura.expirationTime
            if issecretvalue(expirationTime) or type(expirationTime) ~= "number" then
                return nil
            end

            if expirationTime == 0 then return nil end

            longestRemaining = math.max(longestRemaining, expirationTime - GetTime())
        end
    end

    return longestRemaining
end

local function GetHeroismCooldownRemaining()
    local info
    if petSpellSlot then
        if not IsPetAvailable() then return nil end

        -- Revalidate the slot after a pet swap before querying its cooldown.
        local spellInfo = C_SpellBook.GetSpellBookItemInfo(petSpellSlot, Enum.SpellBookSpellBank.Pet)
        if not spellInfo or spellInfo.spellID ~= PRIMAL_RAGE then return nil end

        info = C_SpellBook.GetSpellBookItemCooldown(petSpellSlot, Enum.SpellBookSpellBank.Pet)
    else
        info = C_Spell.GetSpellCooldown(LR.heroismSpellID)
    end

    if issecretvalue(info) or not info then return nil end

    local isEnabled, isActive = info.isEnabled, info.isActive
    if issecretvalue(isEnabled) or issecretvalue(isActive)
        or isEnabled ~= true or type(isActive) ~= "boolean"
    then
        return nil
    end

    if not isActive then return 0 end
    if inCombat then return nil end

    local duration
    if petSpellSlot then
        duration = C_SpellBook.GetSpellBookItemCooldownDuration(petSpellSlot, Enum.SpellBookSpellBank.Pet, true)
    else
        duration = C_Spell.GetSpellCooldownDuration(LR.heroismSpellID, true)
    end

    if issecretvalue(duration) or not duration then return nil end

    -- Native duration objects account for cooldown rate changes and the GCD.
    local remaining = duration:GetRemainingDuration()
    if issecretvalue(remaining) or type(remaining) ~= "number" then return nil end

    return math.max(remaining, 0)
end

local function IsHeroismUsable()
    local isUsable
    if petSpellSlot then
        isUsable = C_SpellBook.IsSpellBookItemUsable(petSpellSlot, Enum.SpellBookSpellBank.Pet)
    else
        isUsable = C_Spell.IsSpellUsable(LR.heroismSpellID)
    end

    return not issecretvalue(isUsable) and isUsable == true
end

local function GetDrumsCooldownRemaining()
    local shortestRemaining
    for _, itemID in ipairs(ownedDrums) do
        if C_Item.IsItemDataCachedByID(itemID) and C_Item.IsUsableItem(itemID)
            and C_Item.GetItemCount(itemID) > 0
        then
            local startTime, duration, isEnabled = C_Item.GetItemCooldown(itemID)
            if not issecretvalue(startTime) and not issecretvalue(duration)
                and not issecretvalue(isEnabled) and isEnabled == true
                and type(startTime) == "number" and type(duration) == "number"
            then
                local remaining = math.max(startTime + duration - GetTime(), 0)
                if not shortestRemaining or remaining < shortestRemaining then
                    shortestRemaining = remaining
                end
            end
        end
    end

    if inCombat and shortestRemaining and shortestRemaining > 0 then return nil end

    return shortestRemaining
end

-------------------------------------------------------------------------------
--- Utility Functions
-------------------------------------------------------------------------------

function LR:Print(msg)
    print("|c" .. addon_color .. ADDON_NAME .. ":|r " .. msg)
end

function LR:VPrint(msg)
    if not verbose then return end

    print("|c" .. addon_color .. ADDON_ABBR .. ":|r " .. msg)
end

function LR:ToggleLock()
    LustReadyDB.locked = not LustReadyDB.locked
    LR:UpdateMover()
    LR:UpdateVisibility()
    LR:Print("Frame " .. (LustReadyDB.locked and "L" or "Unl") .. "ocked")
end

function LR:UpdateMover()
    if LustReadyDB.locked then
        LR.frame.bg:Hide()
        LR.frame.handle:Hide()
        LR.frame:EnableMouse(false)
    else
        LR.frame.bg:Show()
        LR.frame.handle:Show()
        LR.frame:EnableMouse(true)
    end
end

function LR:ToggleDebug()
    verbose = not verbose
    LR:Print("debug turned " .. (verbose and "on" or "off"))
end

function LR:ToggleTest()
    testing = not testing
    LR:Print("testing turned " .. (testing and "on" or "off"))
    LR:UpdateVisibility()
end

-------------------------------------------------------------------------------
--- Visibility
-------------------------------------------------------------------------------

function LR:ShouldShow()
    if not IsInGroupInstance() or UnitIsDeadOrGhost("player") then
        return false, nil
    end

    if not LR.heroismSpellID and #ownedDrums == 0 then
        return false, nil
    end

    local satedRemaining = GetSatedRemaining()
    if satedRemaining == nil then
        return false, nil
    end

    local cdRemaining, label
    if LR.heroismSpellID then
        cdRemaining = GetHeroismCooldownRemaining()
        label = "Lust"
    else
        cdRemaining = GetDrumsCooldownRemaining()
        label = "Drums"
    end

    if cdRemaining == nil then
        return false, nil
    end

    local remaining = math.max(cdRemaining, satedRemaining)
    if remaining == 0 and LR.heroismSpellID and not IsHeroismUsable() then
        return false, nil
    end

    return remaining <= COUNTDOWN_THRESHOLD, remaining, label
end

function LR:UpdateText(remaining, label)
    label = label or "Lust"
    if remaining == 0 then
        LR.frame.text:SetText(label .. " Ready")
    else
        LR.frame.text:SetText(label .. " in " .. math.ceil(remaining))
    end
end

local function OnRefreshTimer()
    refreshTimer = nil
    LR:UpdateVisibility()
end

function LR:UpdateVisibility()
    if refreshTimer then
        refreshTimer:Cancel()
        refreshTimer = nil
    end

    if testing or not LustReadyDB.locked then
        LR:UpdateText(0)
        LR.frame:Show()
        LR:UpdateMover()

        return
    end

    local shouldShow, remaining, label = LR:ShouldShow()

    if shouldShow then
        LR:UpdateText(remaining, label)
        LR.frame:Show()
    else
        LR.frame:Hide()
    end

    if remaining and remaining > 0 then
        -- Wake at the countdown boundary even while the display is hidden.
        local delay = math.max(remaining - COUNTDOWN_THRESHOLD, UPDATE_INTERVAL)
        refreshTimer = C_Timer.NewTimer(delay, OnRefreshTimer)
    end
end

-------------------------------------------------------------------------------
--- Frame Setup
-------------------------------------------------------------------------------

LR.frame = CreateFrame("Frame", "LustReadyFrame", UIParent)
LR.frame:SetSize(mover_size, mover_size)
LR.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
LR.frame:SetMovable(true)
LR.frame:SetClampedToScreen(true)
LR.frame:Hide()

-- Background
LR.frame.bg = LR.frame:CreateTexture(nil, "BACKGROUND")
LR.frame.bg:SetAllPoints(LR.frame)
LR.frame.bg:SetColorTexture(0, 0, 0, 0.5)

-- Mover handle
LR.frame.handle = LR.frame:CreateTexture(nil, "BACKGROUND")
LR.frame.handle:SetSize(mover_size - 2, mover_size - 2)
LR.frame.handle:SetPoint("CENTER", LR.frame, "CENTER", 0, 0)
LR.frame.handle:SetTexture("Interface\\CURSOR\\UI-Cursor-Move")
LR.frame.handle:SetVertexColor(1, 1, 1, 1)

-- Dragging
LR.frame:EnableMouse(true)
LR.frame:RegisterForDrag("LeftButton")
LR.frame:SetScript("OnDragStart", LR.frame.StartMoving)
LR.frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    LustReadyDB.position = { point = point, relPoint = relPoint, x = x, y = y }
end)

-- Font
local FONT = "Interface\\AddOns\\LustReady\\media\\fonts\\PTSansNarrow-Bold.ttf"

LR.frame.font = CreateFont("LustReadyFont")
LR.frame.font:SetFont(FONT, font_size, "OUTLINE")
LR.frame.font:SetTextColor(1, 1, 1, 1)

-- Text
LR.frame.text = LR.frame:CreateFontString(nil, "OVERLAY")
LR.frame.text:SetFontObject(LR.frame.font)
LR.frame.text:SetTextColor(r, g, b, 1)
LR.frame.text:SetPoint("BOTTOMLEFT", LR.frame, "BOTTOMRIGHT", handle_offset + 2, padding_bottom)
LR.frame.text:SetText("Lust Ready")

-------------------------------------------------------------------------------
--- Event Handling
-------------------------------------------------------------------------------

local function OnAddonLoaded(self, arg1)
    if arg1 ~= ADDON_NAME then return end

    self:UnregisterEvent("ADDON_LOADED")

    if not LustReadyDB then
        LR:Print("LustReadyDB not available, creating.")
        LustReadyDB = { locked = false }
    end

    local pos = LustReadyDB.position
    if pos then
        LR.frame:ClearAllPoints()
        LR.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    self:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterUnitEvent("UNIT_PET", "player")
    self:RegisterUnitEvent("UNIT_HEALTH", "pet")
    self:RegisterUnitEvent("UNIT_FLAGS", "pet")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("SPELL_UPDATE_USABLE")
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:RegisterEvent("PET_BAR_UPDATE")
    self:RegisterEvent("PET_UI_UPDATE")
    self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    self:RegisterEvent("PET_BAR_UPDATE_USABLE")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_DEAD")
    self:RegisterEvent("PLAYER_ALIVE")
    self:RegisterEvent("PLAYER_UNGHOST")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")

    inCombat = InCombatLockdown()
    LR:RefreshSources()
    LR:UpdateMover()
    LR:UpdateVisibility()

    LR:Print("Loaded. Use " .. SLASH_LUSTREADY1 .. " for commands.")
end

local function OnUnitAura(self, unit)
    if issecretvalue(unit) or unit ~= "player" then return end

    LR:UpdateVisibility()
end

local function OnReadinessChanged()
    LR:UpdateVisibility()
end

local function OnSourcesChanged()
    LR:RefreshSources()
    LR:VPrint("Source changed — spell: " .. tostring(LR.heroismSpellID)
        .. ", pet slot: " .. tostring(petSpellSlot) .. ", carried drums: " .. #ownedDrums)
    LR:UpdateVisibility()
end

local function OnPlayerSourceChanged(self, unit)
    if issecretvalue(unit) or unit ~= "player" then return end

    OnSourcesChanged()
end

local function OnPetHealthChanged(self, unit)
    if issecretvalue(unit) or unit ~= "pet" then return end

    -- Health changes are frequent; only rediscover on death/resurrection.
    if IsPetAvailable() ~= petAvailable then
        OnSourcesChanged()
    end
end

local function OnItemInfoReceived(self, itemID, success)
    if not pendingItemData[itemID] then return end

    pendingItemData[itemID] = nil
    if success then
        OnSourcesChanged()
    end
end

local function OnPlayerEnteringWorld()
    inCombat = InCombatLockdown()
    LR:RefreshSources()
    LR:UpdateVisibility()
end

local function OnCombatStart()
    inCombat = true
    LR:UpdateVisibility()
end

local function OnCombatEnd()
    inCombat = false
    LR:UpdateVisibility()
end

local EVENT_HANDLERS = {
    ADDON_LOADED                  = OnAddonLoaded,
    UNIT_AURA                     = OnUnitAura,
    UNIT_PET                      = OnPlayerSourceChanged,
    UNIT_HEALTH                   = OnPetHealthChanged,
    UNIT_FLAGS                    = OnPetHealthChanged,
    SPELL_UPDATE_COOLDOWN         = OnReadinessChanged,
    SPELL_UPDATE_USABLE           = OnReadinessChanged,
    SPELLS_CHANGED                = OnSourcesChanged,
    PLAYER_SPECIALIZATION_CHANGED = OnPlayerSourceChanged,
    PET_BAR_UPDATE                = OnSourcesChanged,
    PET_UI_UPDATE                 = OnSourcesChanged,
    PET_BAR_UPDATE_COOLDOWN       = OnReadinessChanged,
    PET_BAR_UPDATE_USABLE         = OnReadinessChanged,
    BAG_UPDATE_DELAYED            = OnSourcesChanged,
    BAG_UPDATE_COOLDOWN           = OnReadinessChanged,
    GET_ITEM_INFO_RECEIVED        = OnItemInfoReceived,
    PLAYER_LEVEL_UP               = OnSourcesChanged,
    PLAYER_ENTERING_WORLD         = OnPlayerEnteringWorld,
    ZONE_CHANGED_NEW_AREA         = OnPlayerEnteringWorld,
    PLAYER_DEAD                   = OnReadinessChanged,
    PLAYER_ALIVE                  = OnReadinessChanged,
    PLAYER_UNGHOST                = OnReadinessChanged,
    PLAYER_REGEN_DISABLED         = OnCombatStart,
    PLAYER_REGEN_ENABLED          = OnCombatEnd,
}

LR.frame:RegisterEvent("ADDON_LOADED")

LR.frame:SetScript("OnEvent", function(self, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then
        handler(self, ...)
    end
end)
