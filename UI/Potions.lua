-- Foxden: potion button.
-- One small button you can drag anywhere. Click it and it opens a tray of every potion,
-- elixir and flask in your bags; click one to drink it. The tray opens and closes in combat
-- too (a secure snippet does it), and each item is a normal secure "use item" button, so the
-- player clicks for every use: nothing is automated.
--
-- The game doesn't let addons add, remove or re-point secure buttons in combat, so the tray's
-- contents are rebuilt out of combat; in combat the counts and cooldowns still update and an
-- item you run out of goes grey.
--
-- settings.potionButton (default on), settings.potionPos { point, x, y } (relative to UIParent).

local _, ns = ...
local UI = ns.UI
local C = UI.C

local SIZE, ICON, GAP, COLS = 36, 32, 4, 6
local LAUNCHER_ICON = "Interface\\Icons\\Trade_Alchemy"

-- a key for the button (Settings > Keys, or the game's Key Bindings > AddOns > Foxden)
ns.POTION_BINDING = "CLICK FoxdenPotionButton:LeftButton"
_G["BINDING_NAME_" .. ns.POTION_BINDING] = "Open potions and flasks"

-- Consumable subclasses: 1 potion, 2 elixir, 3 flask. Some classic items sit in the generic
-- subclass 0, so those are recognised by name instead.
local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local KIND = { [1] = 1, [2] = 3, [3] = 2 } -- sort order: potions, flasks, elixirs
local function kindOf(id)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInfo then return nil end
  local _, _, _, _, _, classID, subID = getInfo(id)
  if classID ~= CONSUMABLE then return nil end
  if KIND[subID] then return KIND[subID] end
  if subID == 0 then
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    if name then
      if name:find("Potion") then return 1 elseif name:find("Flask") then return 2 elseif name:find("Elixir") then return 3 end
    end
  end
end

local Container = C_Container or {}
local function numSlots(bag) return (Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function slotItem(bag, slot) return (Container.GetContainerItemID or GetContainerItemID)(bag, slot) end
local function count(id) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0 end
local function cooldown(id)
  local f = Container.GetItemCooldown or GetItemCooldown
  if f then return f(id) end
end
local function icon(id)
  return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
end
local function itemName(id)
  return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ""
end

-- every potion/flask/elixir in the bags, each id once
local function scan()
  local seen, list = {}, {}
  local lastBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for bag = 0, lastBag do
    for slot = 1, numSlots(bag) do
      local id = slotItem(bag, slot)
      if id and not seen[id] then
        seen[id] = true
        local k = kindOf(id)
        if k then list[#list + 1] = { id = id, kind = k, name = itemName(id) } end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.name < b.name
  end)
  return list
end

local launcher, tray
local buttons, shown = {}, {}
local dirty = true

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- ---- the tray's item buttons ---------------------------------------------------------------

local function refreshButton(b)
  local id = b.itemID
  if not id then return end
  local n = count(id)
  b.count:SetText(n > 1 and n or "")
  b.icon:SetDesaturated(n == 0)
  b.icon:SetAlpha(n == 0 and 0.4 or 1)
  local start, dur, enable = cooldown(id)
  if start and dur and dur > 1.5 and enable ~= 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
end

local function itemButton(i)
  if buttons[i] then return buttons[i] end
  local b = CreateFrame("Button", "FoxdenPotion" .. i, tray, "SecureActionButtonTemplate")
  b:SetSize(ICON, ICON)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  UI.Fill(b, C.raised)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  buttons[i] = b
  return b
end

-- Grow away from the nearest screen edge: up from a button in the bottom half, down otherwise;
-- right from a button in the left half, left otherwise.
local function layout()
  local n = #shown
  local cols = math.max(1, math.min(n, COLS))
  local rows = math.max(1, math.ceil(n / COLS))
  tray:SetSize(cols * ICON + (cols + 1) * GAP, rows * ICON + (rows + 1) * GAP)
  local x, y = launcher:GetCenter()
  local w, h = UIParent:GetSize()
  local up = not y or y < h / 2
  local right = not x or x < w / 2
  local v = up and "BOTTOM" or "TOP"
  local hz = right and "LEFT" or "RIGHT"
  tray:ClearAllPoints()
  tray:SetPoint(v .. hz, launcher, (up and "TOP" or "BOTTOM") .. hz, 0, up and GAP or -GAP)
  for i, b in ipairs(shown) do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    b:ClearAllPoints()
    b:SetPoint(v .. hz, tray, v .. hz,
      (right and 1 or -1) * (GAP + col * (ICON + GAP)),
      (up and 1 or -1) * (GAP + row * (ICON + GAP)))
  end
end

local refreshLauncherCooldown -- defined below; rebuild uses it

local function rebuild()
  if not tray then return end
  if inCombat() then dirty = true; return end
  dirty = false
  local list = scan()
  wipe(shown)
  for i, item in ipairs(list) do
    local b = itemButton(i)
    b.itemID = item.id
    b:SetAttribute("item", "item:" .. item.id)
    b.icon:SetTexture(icon(item.id))
    b:Show()
    shown[i] = b
    refreshButton(b)
  end
  for i = #list + 1, #buttons do
    local b = buttons[i]
    b.itemID = nil
    b:SetAttribute("item", nil)
    b:Hide()
  end
  launcher.icon:SetDesaturated(#list == 0)
  layout()
  refreshLauncherCooldown()
end

-- The launcher shows the cooldown with the most time left: potions share one cooldown, so
-- after drinking one this is when the next can go.
function refreshLauncherCooldown()
  if not launcher then return end
  local bestStart, bestDur, bestEnd = nil, nil, 0
  for _, b in ipairs(shown) do
    local start, dur, enable = cooldown(b.itemID)
    if start and dur and dur > 1.5 and enable ~= 0 and start + dur > bestEnd then
      bestStart, bestDur, bestEnd = start, dur, start + dur
    end
  end
  if bestStart then launcher.cd:SetCooldown(bestStart, bestDur) else launcher.cd:Clear() end
end

local function refreshAll()
  for _, b in ipairs(shown) do refreshButton(b) end
  refreshLauncherCooldown()
end

-- ---- the launcher --------------------------------------------------------------------------

local function savePos()
  local x, y = launcher:GetCenter()
  local s = UIParent:GetEffectiveScale() / launcher:GetEffectiveScale()
  local w, h = UIParent:GetSize()
  ns.settings.potionPos = { x / s - w / 2, y / s - h / 2 }
end

local function place()
  local p = ns.settings.potionPos
  launcher:ClearAllPoints()
  if type(p) == "table" and p[1] then
    launcher:SetPoint("CENTER", UIParent, "CENTER", p[1], p[2])
  else
    launcher:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
  end
end

local function build()
  if launcher then return end
  launcher = CreateFrame("Button", "FoxdenPotionButton", UIParent, "SecureHandlerClickTemplate")
  launcher:SetSize(SIZE, SIZE)
  launcher:SetFrameStrata("MEDIUM")
  launcher:SetMovable(true)
  launcher:SetClampedToScreen(true)
  -- down and up both arrive; it opens on the press (mouse or key), the release is ignored
  launcher:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  launcher:RegisterForDrag("LeftButton")
  UI.Fill(launcher, C.surface); UI.Border(launcher)
  launcher.icon = launcher:CreateTexture(nil, "ARTWORK")
  launcher.icon:SetPoint("TOPLEFT", 3, -3); launcher.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  launcher.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  launcher.icon:SetTexture(LAUNCHER_ICON)
  launcher.cd = CreateFrame("Cooldown", nil, launcher, "CooldownFrameTemplate")
  launcher.cd:SetAllPoints(launcher.icon)
  local edge = launcher:CreateTexture(nil, "OVERLAY")
  edge:SetHeight(2); edge:SetPoint("BOTTOMLEFT", 1, 1); edge:SetPoint("BOTTOMRIGHT", -1, 1)
  UI.Accented(edge)
  launcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  -- the tray: protected so the secure snippet may show and hide it in combat
  tray = CreateFrame("Frame", "FoxdenPotionTray", launcher, "SecureHandlerStateTemplate")
  tray:SetFrameStrata("MEDIUM")
  UI.Fill(tray, C.bg); UI.Border(tray)
  tray:Hide()
  launcher:SetFrameRef("tray", tray)
  launcher:SetAttribute("_onclick", [=[
    if down == false then return end
    local t = self:GetFrameRef("tray")
    if t:IsShown() then t:Hide() else t:Show() end
  ]=])

  launcher:SetScript("OnDragStart", function(self)
    if inCombat() then return end
    GameTooltip:Hide()
    self:StartMoving()
  end)
  launcher:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if inCombat() then return end
    savePos(); place(); layout()
  end)
  launcher:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Potions and flasks")
    GameTooltip:AddLine(#shown == 0 and "None in your bags." or (#shown .. (#shown == 1 and " kind" or " kinds") .. " in your bags."), 1, 1, 1)
    local key = GetBindingKey and GetBindingKey(ns.POTION_BINDING)
    GameTooltip:AddLine("Click" .. (key and (" or press " .. (GetBindingText and GetBindingText(key) or key)) or "") .. " to open. Drag to move.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tray:SetScript("OnShow", refreshAll)

  place()
end

function ns.RefreshPotions()
  if inCombat() then dirty = true; return end
  if ns.settings.potionButton == false then
    if launcher then launcher:Hide() end
    return
  end
  build()
  launcher:Show()
  rebuild()
end

-- /fox potions: put the button back in the middle of the screen (and turn it on)
function ns.ResetPotions()
  if inCombat() then ns.say("Try again out of combat.", true); return end
  ns.settings.potionPos = nil
  ns.settings.potionButton = true
  ns.RefreshPotions()
  place(); layout()
  ns.say("Potion button is back near the middle of your screen.", true)
end

ns.RegisterModule({
  name = "Potions",
  events = {
    PLAYER_LOGIN = function() ns.RefreshPotions() end,
    BAG_UPDATE_DELAYED = function()
      if not launcher or not launcher:IsShown() then return end
      if inCombat() then dirty = true; refreshAll() else rebuild() end
    end,
    BAG_UPDATE_COOLDOWN = function() if launcher and launcher:IsShown() then refreshAll() end end,
    SPELL_UPDATE_COOLDOWN = function() if launcher and launcher:IsShown() then refreshLauncherCooldown() end end,
    PLAYER_REGEN_ENABLED = function() if dirty then ns.RefreshPotions() end end,
    -- item names/classes can arrive late on a cold start
    -- (this fires once per item, so one rebuild half a second after the last)
    GET_ITEM_INFO_RECEIVED = function()
      if inCombat() or not (launcher and launcher:IsShown()) or ns._potionsPending then return end
      ns._potionsPending = true
      C_Timer.After(0.5, function() ns._potionsPending = nil; rebuild() end)
    end,
  },
})
