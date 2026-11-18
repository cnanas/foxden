-- Foxden: the run summary. Pops up when the last boss dies (once you're out of combat),
-- or when you leave a dungeon you didn't clear: time, XP, gold, bosses with their kill
-- times, the loot your group got, and a button to the full run in Foxden. XP and gold keep counting while it's
-- open, so loot from the last boss still lands. Escape or X closes it; /fox summary
-- shows it again.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local W, H_TOP = 440, 150
local PAD = 20
local S, shownFor
local S_FillLoot

local function build()
  S = CreateFrame("Frame", "FoxdenRunSummary", UIParent)
  S:SetWidth(W)
  S:SetPoint("TOP", 0, -120)
  S:SetFrameStrata("DIALOG")
  S:SetToplevel(true); S:SetClampedToScreen(true)
  S:EnableMouse(true); S:SetMovable(true); S:RegisterForDrag("LeftButton")
  S:SetScript("OnDragStart", S.StartMoving)
  S:SetScript("OnDragStop", S.StopMovingOrSizing)
  UI.Fill(S, C.bg); UI.Border(S, { 1, 1, 1, 0.14 })
  tinsert(UISpecialFrames, "FoxdenRunSummary")

  local accent = S:CreateTexture(nil, "ARTWORK"); accent:SetSize(3, 20); accent:SetPoint("TOPLEFT", PAD, -20); UI.Accented(accent)
  S.title = UI.Text(S, 17); S.title:SetPoint("LEFT", accent, "RIGHT", 10, 0); S.title:SetWidth(W - 90)
  local close = UI.CloseButton(S, function() S:Hide() end); close:SetPoint("TOPRIGHT", -10, -10)
  S.sub = UI.Text(S, 12, C.dim); S.sub:SetPoint("TOPLEFT", accent, "BOTTOMLEFT", 0, -8); S.sub:SetWidth(W - PAD * 2)

  -- four tiles: time, XP, gold, bosses
  S.tiles = {}
  local tw = (W - PAD * 2 - 3 * 8) / 4
  for i, label in ipairs({ "Time", "XP gained", "Gold looted", "Bosses" }) do
    local t = CreateFrame("Frame", nil, S); t:SetSize(tw, 56)
    t:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + 8), -76)
    UI.Fill(t, C.surface); UI.Border(t)
    local l = UI.Text(t, 11, C.dim); l:SetPoint("TOPLEFT", 10, -9); l:SetText(label)
    t.value = UI.Text(t, 16); t.value:SetPoint("TOPLEFT", 10, -27); t.value:SetWidth(tw - 14)
    S.tiles[i] = t
  end

  S.lines = {}
  S.FillLoot = function(...) return S_FillLoot(...) end
  S.open = UI.Button(S, "Full summary", 130, 28, function()
    local id = S.run and (S.live and "live" or S.run.id)
    S:Hide()
    if id then ns.OpenPage("runs", id) end
  end, "primary")
  S.ok = UI.Button(S, "Close", 80, 28, function() S:Hide() end)

  -- XP and gold still come in while you loot the last boss
  S:SetScript("OnUpdate", function(self, e)
    self.tick = (self.tick or 0) + e
    if self.tick < 1 then return end
    self.tick = 0
    -- (and item names and icons arrive from the server a moment after they're first asked for)
    if not self.live or ns.GetCurrentRun() == self.run then self:Fill() end
  end)

  S.lootHead = UI.Text(S, 11, C.faint); S.lootHead:SetText("LOOT")
  S.lootNote = UI.Text(S, 11, C.dim); S.lootNote:SetWidth(W - PAD * 2); S.lootNote:SetWordWrap(true)
  S.loot = {}

  function S:Fill()
    local run = self.run
    if not run then return end
    local done = run.doneAt ~= nil
    self.title:SetText(ns.RunName(run) .. (done and " cleared" or ""))
    local bits = {}
    if run.difficulty and run.difficulty ~= "" then bits[#bits + 1] = run.difficulty end
    local wipes = run.wipes or 0
    bits[#bits + 1] = wipes == 0 and "No wipes" or (wipes == 1 and "1 wipe" or (wipes .. " wipes"))
    if (run.combatSeconds or 0) > 0 then bits[#bits + 1] = UI.Time(run.combatSeconds) .. " in combat" end
    if not done then bits[#bits + 1] = self.live and "In progress" or "Left before the last boss" end
    self.sub:SetText(table.concat(bits, "  ·  "))

    local total, down = ns.RunBossCount(run)
    local kills = #(run.bosses or {})
    if total == 0 then total, down = kills, kills end
    local level = UnitLevel and UnitLevel("player") or 0
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    self.tiles[1].value:SetText(UI.Time(ns.RunElapsed(run)))
    self.tiles[2].value:SetText((run.xp or 0) == 0 and level >= maxLevel and "|cff999fb0max|r" or UI.Num(run.xp or 0))
    self.tiles[3].value:SetText(ns.Money(run.gold or 0))
    self.tiles[4].value:SetText(string.format("%d/%d", down, total))

    -- bosses in the dungeon's order, with the time into the run each one died
    local list, seen = {}, {}
    local function killOf(b)
      for _, k in ipairs(run.bosses or {}) do
        if k.name == b.name then return k end
        for _, id in ipairs(b.ids or {}) do if k.id == id then return k end end
      end
    end
    for _, b in ipairs(ns.RunDungeonBosses(run)) do -- this wing's, in a dungeon with wings
      local k = killOf(b)
      if k then seen[k] = true end
      list[#list + 1] = { name = b.name, at = k and k.killedAt }
    end
    for _, k in ipairs(run.bosses or {}) do
      if not seen[k] then list[#list + 1] = { name = k.name, at = k.killedAt } end
    end
    local colW, perCol = (W - PAD * 2 - 16) / 2, math.ceil(math.min(#list, 16) / 2)
    for i = 1, math.min(#list, 16) do
      local row = self.lines[i]
      if not row then
        row = CreateFrame("Frame", nil, self); row:SetSize(colW, 18)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(12, 12); row.icon:SetPoint("LEFT", 0, 0)
        row.name = UI.Text(row, 12); row.name:SetPoint("LEFT", 18, 0); row.name:SetPoint("RIGHT", -50, 0)
        row.at = UI.Text(row, 12, C.dim, "RIGHT"); row.at:SetPoint("RIGHT", 0, 0)
        self.lines[i] = row
      end
      local b = list[i]
      local col, r = math.floor((i - 1) / perCol), (i - 1) % perCol
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", PAD + col * (colW + 16), -148 - r * 20)
      row.name:SetText(b.name or "?")
      if b.at then
        row.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); row.icon:SetAlpha(1)
        row.name:SetTextColor(unpack(C.text)); row.at:SetText(UI.Time(b.at))
      else
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull"); row.icon:SetAlpha(0.35)
        row.name:SetTextColor(unpack(C.faint)); row.at:SetText("")
      end
      row:Show()
    end
    for i = math.min(#list, 16) + 1, #self.lines do self.lines[i]:Hide() end
    local bottom = 148 + perCol * 20 + 14
    bottom = self:FillLoot(run, bottom)
    self.open:ClearAllPoints(); self.open:SetPoint("TOPRIGHT", -PAD, -bottom)
    self.ok:ClearAllPoints(); self.ok:SetPoint("RIGHT", self.open, "LEFT", -8, 0)
    self:SetHeight(bottom + 28 + PAD)
  end
end

-- ---- loot: icons, best first; greys only counted -------------------------------------

local ICON, GAP, ROWS = 30, 6, 2

local function lootIcon(i)
  local b = S.loot[i]
  if b then return b end
  b = CreateFrame("Button", nil, S); b:SetSize(ICON, ICON)
  b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.count = UI.Text(b, 11, C.text, "RIGHT"); b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.g.i) then GameTooltip:AddLine("Item " .. self.g.i) end
    GameTooltip:AddLine(" ")
    if self.g.w then GameTooltip:AddLine("Looted by " .. self.g.w, 0.7, 0.72, 0.78) end
    if self.g.b then GameTooltip:AddLine("From " .. self.g.b, 0.7, 0.72, 0.78) end
    GameTooltip:AddLine("Shift-click to link it in chat.", 0.6, 0.63, 0.69)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:SetScript("OnClick", function(self)
    if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
      local _, link = UI.ItemLook(self.g.i)
      if link then ChatEdit_InsertLink(link) end
    end
  end)
  S.loot[i] = b
  return b
end

-- Lay out the loot section from y (pixels below the top); returns the new bottom.
S_FillLoot = function(self, run, y)
  local list, grey = ns.RunLootList(run)
  local shown = {}
  for _, g in ipairs(list) do if (g.q or 1) >= 1 then shown[#shown + 1] = g end end
  if #list == 0 and not run.got then
    for _, b in ipairs(self.loot) do b:Hide() end
    self.lootHead:Hide(); self.lootNote:Hide()
    return y
  end
  self.lootHead:ClearAllPoints(); self.lootHead:SetPoint("TOPLEFT", PAD, -y); self.lootHead:Show()
  y = y + 18
  local perRow = math.floor((W - PAD * 2 + GAP) / (ICON + GAP))
  local max = perRow * ROWS
  for i = 1, math.min(#shown, max) do
    local b, g = lootIcon(i), shown[i]
    b.g = g
    local _, _, q, icon = UI.ItemLook(g.i)
    b.tex:SetTexture(icon or 134400)
    local r, gg, bl = UI.QualityColor(q or g.q)
    b.edge:SetColorTexture(r, gg, bl, 0.9)
    b.count:SetText((g.n or 1) > 1 and g.n or "")
    local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD + col * (ICON + GAP), -(y + row * (ICON + GAP)))
    b:Show()
  end
  for i = math.min(#shown, max) + 1, #self.loot do self.loot[i]:Hide() end
  if #shown > 0 then y = y + math.ceil(math.min(#shown, max) / perRow) * (ICON + GAP) + 2 end
  local bits = {}
  if #shown == 0 then bits[#bits + 1] = "Nothing looted yet." end
  if #shown > max then bits[#bits + 1] = (#shown - max) .. " more in Full summary" end
  if grey > 0 then bits[#bits + 1] = grey .. " grey " .. (grey == 1 and "item" or "items") end
  if #bits > 0 then
    self.lootNote:SetText(table.concat(bits, "  ·  "))
    self.lootNote:ClearAllPoints(); self.lootNote:SetPoint("TOPLEFT", PAD, -y); self.lootNote:Show()
    y = y + 18
  else self.lootNote:Hide() end
  return y + 10
end

-- Show the summary for a run. live: it's the run you're still in.
function ns.ShowRunSummary(run, live)
  if not run then return end
  if not S then build() end
  S.run, S.live = run, live and true or false
  shownFor = run.id
  S:Fill()
  S:Show(); S:Raise()
end

-- Wait until you're out of combat, then show it.
local function showSoon(run, live, tries)
  tries = tries or 0
  if tries > 120 then return end
  local busy = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
  if busy then C_Timer.After(1, function() showSoon(run, live, tries + 1) end); return end
  C_Timer.After(tries == 0 and 2 or 1.5, function()
    if live and ns.GetCurrentRun() ~= run then return end -- left in the meantime: the save shows it
    ns.ShowRunSummary(run, live)
  end)
end

ns.RegisterModule({
  name = "RunSummary",
  OnRunDone = function(_, run)
    if ns.settings.runSummary == false then return end
    showSoon(run, true)
  end,
  OnRunSaved = function(_, run)
    -- the popup that's open for this run now points at the saved copy
    if S and S:IsShown() and S.run and S.run.id == run.id then S.run, S.live = run, false; S:Fill(); return end
    if ns.settings.runSummary == false or shownFor == run.id then return end
    showSoon(run, false)
  end,
})
