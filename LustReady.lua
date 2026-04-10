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
    264667, -- Hunter: Primal Rage
    390386, -- Evoker: Fury of the Aspects
}

-------------------------------------------------------------------------------
--- State Queries
-------------------------------------------------------------------------------

local function IsInGroupInstance()
    local _, instanceType = IsInInstance()

    return instanceType == "party"
        or instanceType == "raid"
        or instanceType == "scenario"
        or instanceType == "arena"
        or instanceType == "pvp"
end

local function FindPlayerHeroismSpell()
    for _, spellID in ipairs(HEROISM_SPELLS) do
        if IsPlayerSpell(spellID) then
            return spellID
        end
    end

    return nil
end

local function HasSatedDebuff()
    for spellID in pairs(SATED_DEBUFFS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura then
            return true
        end
    end

    return false
end

local function GetSatedRemaining()
    for spellID in pairs(SATED_DEBUFFS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura then
            if issecretvalue(aura.expirationTime) then
                return 0
            end

            local remaining = aura.expirationTime - GetTime()

            return math.max(remaining, 0)
        end
    end

    return 0
end

local COUNTDOWN_THRESHOLD = 30

local function IsHeroismOnCooldown(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then
        return false
    end

    return info.isActive
end

local function GetHeroismCooldownRemaining(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then
        return nil
    end

    if issecretvalue(info.duration) then
        return 0
    end

    -- duration <= 1.5 is just the GCD
    if info.duration <= 1.5 then
        return 0
    end

    local remaining = (info.startTime + info.duration) - GetTime()

    return math.max(remaining, 0)
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

local function IsHeroismReady(spellID)
    if IsHeroismOnCooldown(spellID) then
        return false
    end

    if HasSatedDebuff() then
        return false
    end

    return true
end

function LR:ShouldShow()
    if not LR.heroismSpellID then
        return false, nil
    end

    -- In combat, cooldown fields are tainted (secret values) and cannot
    -- be compared.  Only check ready state, skip the countdown window.
    if inCombat then
        if IsHeroismReady(LR.heroismSpellID) then
            return true, 0
        end

        return false, nil
    end

    local cdRemaining = GetHeroismCooldownRemaining(LR.heroismSpellID)
    if not cdRemaining then
        return false, nil
    end

    local satedRemaining = GetSatedRemaining()
    local remaining = math.max(cdRemaining, satedRemaining)

    local isReady = remaining == 0
    local isSoon = remaining > 0 and remaining <= COUNTDOWN_THRESHOLD

    if not isReady and not isSoon then
        return false, nil
    end

    if IsInGroupInstance() then
        return true, remaining
    end

    return false, nil
end

function LR:UpdateText(remaining)
    if remaining == 0 then
        LR.frame.text:SetText("Lust Ready")
    else
        LR.frame.text:SetText("Lust in " .. math.ceil(remaining))
    end
end

local UPDATE_INTERVAL = 0.5
local timeSinceLastUpdate = 0

function LR:UpdateVisibility()
    if testing then
        LR.frame:Show()
        LR:UpdateMover()

        return
    end

    if not LustReadyDB.locked then
        LR.frame:Show()

        return
    end

    local shouldShow, remaining = LR:ShouldShow()

    if shouldShow then
        LR:UpdateText(remaining)
        LR.frame:Show()
        LR.frame:SetScript("OnUpdate", LR.OnUpdate)
    else
        LR.frame:Hide()
        LR.frame:SetScript("OnUpdate", nil)
    end
end

function LR.OnUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end

    timeSinceLastUpdate = 0
    LR:UpdateVisibility()
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

    if not LustReadyDB then
        LR:Print("LustReadyDB not available, creating.")
        LustReadyDB = { locked = false }
    end

    local pos = LustReadyDB.position
    if pos then
        LR.frame:ClearAllPoints()
        LR.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    LR.heroismSpellID = FindPlayerHeroismSpell()
    LR:UpdateMover()
    LR:UpdateVisibility()

    LR.frame:UnregisterEvent("ADDON_LOADED")
    LR.frame:RegisterEvent("UNIT_AURA")
    LR.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    LR.frame:RegisterEvent("SPELLS_CHANGED")
    LR.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    LR.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    LR.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    LR.frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    LR:Print("Loaded. Use " .. SLASH_LUSTREADY1 .. " for commands.")
end

local function OnUnitAura(self, unit)
    if unit ~= "player" then return end

    LR:UpdateVisibility()
end

local function OnSpellUpdateCooldown()
    LR:UpdateVisibility()
end

local function OnSpellsChanged()
    LR.heroismSpellID = FindPlayerHeroismSpell()
    LR:VPrint("Spells changed — heroism spell: " .. tostring(LR.heroismSpellID))
    LR:UpdateVisibility()
end

local function OnPlayerEnteringWorld()
    LR.heroismSpellID = FindPlayerHeroismSpell()
    inCombat = InCombatLockdown()
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
    ADDON_LOADED           = OnAddonLoaded,
    UNIT_AURA              = OnUnitAura,
    SPELL_UPDATE_COOLDOWN  = OnSpellUpdateCooldown,
    SPELLS_CHANGED         = OnSpellsChanged,
    PLAYER_ENTERING_WORLD  = OnPlayerEnteringWorld,
    ZONE_CHANGED_NEW_AREA  = OnPlayerEnteringWorld,
    PLAYER_REGEN_DISABLED  = OnCombatStart,
    PLAYER_REGEN_ENABLED   = OnCombatEnd,
}

LR.frame:RegisterEvent("ADDON_LOADED")

LR.frame:SetScript("OnEvent", function(self, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then
        handler(self, ...)
    end
end)
