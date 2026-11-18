-- Foxden: the loot filter for the Dungeons page (boss loot and trash drops).
--   Only loot my class can use   armour and weapons your class can wear or wield
--   Hide recipes                  patterns, plans, formulas, schematics
--   Stats                         only gear with any of the ticked stats
-- ns.LootFilter.Pass(itemID) says whether an item is shown. Saved in FoxdenDB.settings.lootFilter.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local F = {}
ns.LootFilter = F

-- armour (class 4) and weapon (class 2) subclasses each class can use, classic rules
local ARMOR = { WARRIOR = { 1, 2, 3, 4, 6 }, PALADIN = { 1, 2, 3, 4, 6 }, HUNTER = { 1, 2, 3 }, SHAMAN = { 1, 2, 3, 6 },
  ROGUE = { 1, 2 }, DRUID = { 1, 2 }, MAGE = { 1 }, PRIEST = { 1 }, WARLOCK = { 1 } }
local WEAPON = { WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 }, PRIEST = { 4, 10, 15, 19 },
  SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 }, WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 } }
local STATS = { { "str", "Str", "ITEM_MOD_STRENGTH_SHORT" }, { "agi", "Agi", "ITEM_MOD_AGILITY_SHORT" }, { "sta", "Sta", "ITEM_MOD_STAMINA_SHORT" },
  { "int", "Int", "ITEM_MOD_INTELLECT_SHORT" }, { "spi", "Spi", "ITEM_MOD_SPIRIT_SHORT" } }

local function cfg()
  ns.settings.lootFilter = ns.settings.lootFilter or { classOnly = false, hideRecipes = false, stats = {} }
  ns.settings.lootFilter.stats = ns.settings.lootFilter.stats or {}
  return ns.settings.lootFilter
end

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end; return false end

function F.Active()
  local c = cfg()
  if c.classOnly or c.hideRecipes then return true end
  for _ in pairs(c.stats) do return true end
  return false
end

function F.Pass(id)
  local c = cfg()
  if not F.Active() then return true end
  local classID, subID, equipLoc
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, loc, _, cid, sid = C_Item.GetItemInfoInstant(id)
    classID, subID, equipLoc = cid, sid, loc
  end
  if not classID then return true end -- not known yet: show it
  if c.hideRecipes and classID == 9 then return false end
  local equip = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
  if c.classOnly and equip then
    local class = select(2, UnitClass("player"))
    local cloakOrMisc = equipLoc == "INVTYPE_CLOAK" or (classID == 4 and subID == 0)
    if classID == 4 and not cloakOrMisc and not (subID > 6) and not has(ARMOR[class], subID) then return false end
    if classID == 2 and not has(WEAPON[class], subID) then return false end
  end
  if equip and next(c.stats) then
    local _, link = C_Item.GetItemInfo(id)
    if not link then return true end -- not loaded yet: show it
    local stats = (C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link)) or {}
    local any = false
    for _, s in ipairs(STATS) do if c.stats[s[1]] and (stats[s[3]] or 0) > 0 then any = true end end
    if not any then return false end
  end
  return true
end

-- ---- the popover ------------------------------------------------------------------------------
local pop
local function build()
  pop = CreateFrame("Frame", "FoxdenLootFilter", UIParent)
  pop:SetSize(300, 200)
  pop:SetFrameStrata("DIALOG"); pop:EnableMouse(true)
  UI.Fill(pop, C.surface); UI.Border(pop)
  local title = UI.Text(pop, 13); title:SetPoint("TOPLEFT", 12, -10); title:SetText("Loot filter")
  local close = UI.CloseButton(pop, function() pop:Hide() end); close:SetPoint("TOPRIGHT", -4, -4)
  pop.rows = {}
  local function changed() if ns.RefreshUI then ns.RefreshUI() end; for _, r in ipairs(pop.rows) do r:Refresh() end end
  local t1 = UI.Toggle(pop, 276, "Only loot my class can use", nil, function() return cfg().classOnly end, function(v) cfg().classOnly = v; changed() end)
  t1:SetPoint("TOPLEFT", 12, -30)
  local t2 = UI.Toggle(pop, 276, "Hide recipes", nil, function() return cfg().hideRecipes end, function(v) cfg().hideRecipes = v; changed() end)
  t2:SetPoint("TOPLEFT", t1, "BOTTOMLEFT")
  pop.rows[1], pop.rows[2] = t1, t2
  local lbl = UI.Text(pop, 12, C.dim); lbl:SetPoint("TOPLEFT", t2, "BOTTOMLEFT", 0, -10); lbl:SetText("Only gear with any of:")
  local x = 0
  for _, s in ipairs(STATS) do
    local b = CreateFrame("Button", nil, pop); b:SetSize(50, 24)
    b.bg = UI.Fill(b, C.raised); UI.Border(b)
    b.on = b:CreateTexture(nil, "ARTWORK"); b.on:SetAllPoints(); UI.Accented(b.on, 0.25)
    b.t = UI.Text(b, 12, C.text, "CENTER"); b.t:SetPoint("CENTER"); b.t:SetText(s[2])
    b:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", x, -6); x = x + 54
    function b:Refresh() self.on:SetShown(cfg().stats[s[1]] == true) end
    b:SetScript("OnClick", function() cfg().stats[s[1]] = not cfg().stats[s[1]] or nil; changed() end)
    pop.rows[#pop.rows + 1] = b
  end
  local clear = UI.Button(pop, "Show everything", 130, 24, function()
    local c = cfg(); c.classOnly, c.hideRecipes, c.stats = false, false, {}; changed()
  end)
  clear:SetPoint("BOTTOMLEFT", 12, 10)
  pop:Hide()
  if UISpecialFrames then tinsert(UISpecialFrames, "FoxdenLootFilter") end
end

function F.Toggle(anchor)
  if not pop then build() end
  if pop:IsShown() then pop:Hide(); return end
  for _, r in ipairs(pop.rows) do r:Refresh() end
  pop:ClearAllPoints(); pop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
  pop:Show()
end
