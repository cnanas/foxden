-- Fishing key: one key that casts Fishing.
-- A hidden secure button casts the spell; the key is a normal game binding
-- ("CLICK FoxdenFishButton:LeftButton"), set from Foxden's settings or from
-- the game's Key Bindings > AddOns > Foxden. The player still presses the key
-- for every cast: nothing is automated.
local _, ns = ...

ns.FISH_BINDING = "CLICK FoxdenFishButton:LeftButton"
_G["BINDING_NAME_" .. ns.FISH_BINDING] = "Cast Fishing"

-- Fishing's spell ids across game versions; the name is the same for every rank
-- and casting by name uses the best one the character knows.
local FISHING_IDS = { 7620, 131474, 7731, 7732, 18248 }

local function fishingName()
  for _, id in ipairs(FISHING_IDS) do
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
      or (GetSpellInfo and GetSpellInfo(id))
    if name and name ~= "" then return name end
  end
  return PROFESSIONS_FISHING or "Fishing"
end

local button = CreateFrame("Button", "FoxdenFishButton", UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp", "AnyDown")
button:Hide()

local function setup()
  if InCombatLockdown and InCombatLockdown() then return false end
  button:SetAttribute("type", "spell")
  button:SetAttribute("spell", fishingName())
  return true
end
setup()

function ns.FishingKey()
  return GetBindingKey and GetBindingKey(ns.FISH_BINDING)
end

ns.RegisterModule({
  name = "Fishing",
  events = {
    -- spell names can arrive late on a cold start; set again once logged in
    PLAYER_LOGIN = function() setup() end,
    PLAYER_REGEN_ENABLED = function() if button:GetAttribute("spell") == nil then setup() end end,
  },
})
