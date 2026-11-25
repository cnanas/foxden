-- Foxden: stream overlays. Windows made to be captured by OBS (or just left in view) while
-- you run a dungeon. They show themselves inside a dungeon run when "Stream overlays" is on:
--
--   Splits    the run clock and every boss as a split, against the guild's best run
--   Strip     a thin bar of boss portraits that light up as they die
--   Boss      a card when a boss is pulled, and one when it dies (or wipes you)
--   Loot      a card for each item someone in the group gets
--   Map       the dungeon's map with the bosses, the route so far, and where the group is
--
-- The game doesn't tell addons where you are inside a dungeon (no map position, no world
-- position: checked in game), so "where the group is" is the boss being fought, else the last
-- one killed.
--
-- Every window can be dragged; positions are kept in settings.streamPos. /fox stream turns
-- them on and off, /fox stream test shows them all with sample data (to place them and to
-- set up OBS outside a dungeon).

local _, ns = ...
local UI = ns.UI
local C = UI.C

local S = { fight = nil, test = nil } -- fight = { id, name, at } while a boss is pulled
local panels = {}
local GREEN, RED, GOLD = "|cff6fd39a", "|cfff06b6b", "|cffffd24d"

local function on(key) return ns.settings[key] ~= false end
local function run() return S.test or (ns.settings.stream and ns.LiveRun and ns.LiveRun()) or nil end

local function signed(seconds)
  local s = math.floor(math.abs(seconds) + 0.5)
  return (seconds <= 0 and "-" or "+") .. UI.Time(s)
end

-- ---- a window you can drag -------------------------------------------------------------

local DEFAULT_POS = {
  Splits = { "RIGHT", "RIGHT", -40, 60 },
  Strip = { "TOP", "TOP", 0, -30 },
  Boss = { "TOP", "TOP", 0, -130 },
  Loot = { "LEFT", "LEFT", 40, 40 },
  Map = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 200 },
}

-- The dock: every window in one block in a corner of the screen, each in a slot that never
-- moves or changes size, so an OBS crop of a slot stays right. { x, y, width, height } from the
-- block's top left; two columns, both 490 tall.
local DOCK = {
  Boss = { 0, 0, 440, 92 }, Map = { 0, 100, 380, 304 }, Strip = { 0, 412, 440, 78 },
  Splits = { 448, 0, 320, 312 }, Loot = { 448, 320, 320, 170 },
}
local DOCK_W, DOCK_H, DOCK_M = 768, 490, 8
local function dockCorner()
  local c = ns.settings.streamDock
  if c == "TOPLEFT" or c == "TOPRIGHT" or c == "BOTTOMLEFT" or c == "BOTTOMRIGHT" then return c end
end

local function place(f)
  f:ClearAllPoints()
  f:SetScale(ns.settings.streamScale or 1)
  local corner, slot = dockCorner(), DOCK[f.key]
  if corner and slot then
    local right, bottom = corner:find("RIGHT") ~= nil, corner:find("BOTTOM") ~= nil
    local x = right and (-(DOCK_M + DOCK_W) + slot[1]) or (DOCK_M + slot[1])
    local y = bottom and (DOCK_M + DOCK_H - slot[2]) or (-(DOCK_M + slot[2]))
    f:SetPoint("TOPLEFT", UIParent, corner, x, y)
    return
  end
  local p = (ns.settings.streamPos and ns.settings.streamPos[f.key]) or DEFAULT_POS[f.key]
  f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- /fox stream crops: each slot of the dock in screen pixels, as OBS's Crop filter wants them
function ns.StreamCrops()
  local corner = dockCorner()
  if not corner then ns.say("Turn on the dock first (Settings > Stream > Dock).", true); return end
  local pw, ph = GetPhysicalScreenSize()
  local s = ns.settings.streamScale or 1
  local u = UIParent:GetEffectiveScale()
  local px = u * s * ph / 768 -- screen pixels per unit of a stream window
  local uw, uh = UIParent:GetWidth() / s, UIParent:GetHeight() / s
  local right, bottom = corner:find("RIGHT") ~= nil, corner:find("BOTTOM") ~= nil
  ns.say(string.format("OBS crops for a %d x %d capture (left, top, right, bottom):", pw, ph), true)
  for _, key in ipairs({ "Splits", "Strip", "Boss", "Loot", "Map" }) do
    local d = DOCK[key]
    local x = (right and (uw - DOCK_M - DOCK_W) or DOCK_M) + d[1]
    local y = (bottom and (uh - DOCK_M - DOCK_H) or DOCK_M) + d[2]
    local l, t, w, h = math.floor(x * px), math.floor(y * px), math.ceil(d[3] * px), math.ceil(d[4] * px)
    ns.say(string.format("%s: %d, %d, %d, %d", key, l, t, math.max(0, pw - l - w), math.max(0, ph - t - h)), true)
  end
  local l = math.floor((right and (uw - DOCK_M - DOCK_W) or DOCK_M) * px)
  local t = math.floor((bottom and (uh - DOCK_M - DOCK_H) or DOCK_M) * px)
  ns.say(string.format("Whole dock (to cover it on stream): starts at %d, %d and is %d x %d.", l, t, math.ceil(DOCK_W * px), math.ceil(DOCK_H * px)), true)
end

-- solid = a window with its own background; otherwise a see-through holder for cards
local function panel(key, w, h, solid)
  local f = CreateFrame("Frame", "FoxdenStream" .. key, UIParent)
  f.key = key
  f:SetSize(w, h)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:EnableMouse(solid and true or false)
  f:SetScript("OnDragStart", function(self) if not dockCorner() then self.moving = true; self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    if not self.moving then return end -- docked windows stay in their slots
    self.moving = nil
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.settings.streamPos = ns.settings.streamPos or {}
    ns.settings.streamPos[key] = { p, rp, x, y }
  end)
  if solid then
    UI.Fill(f, C.bg); UI.Border(f, { 1, 1, 1, 0.12 })
  else
    -- behind the cards: nothing, or one flat color for OBS to key out
    f.back = f:CreateTexture(nil, "BACKGROUND"); f.back:SetAllPoints(); f.back:Hide()
    f.hint = UI.Text(f, 11, C.dim, "CENTER"); f.hint:SetPoint("BOTTOM", 0, 4); f.hint:Hide()
  end
  f:Hide()
  place(f)
  panels[key] = f
  return f
end

-- a holder shows while there is a run; its background follows the "backdrop" setting
local function holder(f, show, hint)
  local mode = ns.settings.streamBackdrop or "none"
  if mode == "green" then f.back:SetColorTexture(0, 1, 0, 1)
  elseif mode == "black" then f.back:SetColorTexture(0, 0, 0, 1)
  else f.back:SetColorTexture(1, 1, 1, 0.06) end
  f.back:SetShown(mode ~= "none" or S.test ~= nil)
  f.hint:SetText(hint); f.hint:SetShown(S.test ~= nil)
  f:EnableMouse(S.test ~= nil) -- only in the way of clicks while you're placing it
  f:SetShown(show)
end

-- fade in, stay, fade out
local function flash(f, hold, onDone)
  f.t = 0
  f:SetAlpha(0); f:Show()
  f:SetScript("OnUpdate", function(self, e)
    self.t = self.t + e
    local a = 1
    if self.t < 0.25 then a = self.t / 0.25
    elseif self.t > hold + 0.25 then a = 1 - (self.t - hold - 0.25) / 0.6 end
    if a <= 0 then
      self:Hide(); self:SetScript("OnUpdate", nil)
      if onDone then onDone(self) end
      return
    end
    self:SetAlpha(a)
  end)
end

-- ---- the run as the overlays see it ------------------------------------------------------

local function isBoss(b, id, name)
  if id and (b.encounterID == id) then return true end
  for _, x in ipairs(b.ids or {}) do if x == id then return true end end
  return name ~= nil and b.name == name
end

-- rows = { { b, name, kill = { killedAt }, best = seconds, level, fighting }, ... }
local function model(r)
  local list = ns.RunBossList and ns.RunBossList(r.dungeon, r) or {}
  local times, total, by = {}, nil, nil
  if ns.BestRun and not (ns.Wings and ns.Wings[r.instanceID]) then times, total, by = ns.BestRun(r.dungeon) end
  local levels = {}
  local d = ns.Dungeons and ns.Dungeons[r.instanceID]
  for _, b in ipairs(d and d.bosses or {}) do levels[b.name] = b.level end
  local rows, dead = {}, 0
  for i, b in ipairs(list) do
    local kill
    for _, k in ipairs(r.bosses or {}) do if isBoss(b, k.id, k.name) then kill = k end end
    local best = b.encounterID and times[b.encounterID]
    for _, id in ipairs(b.ids or {}) do best = best or times[id] end
    if kill then best = best or times[kill.id] end
    if S.test and not best then best = 70 + i * 95 end -- sample best times, so the preview has splits
    if kill then dead = dead + 1 end
    rows[i] = { b = b, name = b.name, kill = kill, best = best, level = levels[b.name],
      fighting = not kill and S.fight ~= nil and isBoss(b, S.fight.id, S.fight.name) }
  end
  if S.test and not total then total, by = 70 + #rows * 95, "the guild" end
  return rows, { dead = dead, total = total, by = by }
end

local function clockText(r)
  local t = UI.Time(ns.RunElapsed(r))
  if not r.pulled then return "|cff999fb0" .. t .. "|r" end
  if r.doneAt then return GREEN .. t .. "|r" end
  return t
end

local function portrait(parent, size)
  local b = CreateFrame("Frame", nil, parent); b:SetSize(size, size)
  b.ring = b:CreateTexture(nil, "BACKGROUND"); b.ring:SetPoint("TOPLEFT", -2, 2); b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  b.ring:SetColorTexture(1, 1, 1, 1); UI.Round(b, b.ring)
  b.back = b:CreateTexture(nil, "BORDER"); b.back:SetAllPoints(); b.back:SetColorTexture(0.12, 0.13, 0.15, 1); UI.Round(b, b.back)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); UI.Round(b, b.tex)
  return b
end
local function paintPortrait(p, boss)
  if ns.SetBossPortrait then ns.SetBossPortrait(p.tex, boss) else p.tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull") end
end

-- ---- splits --------------------------------------------------------------------------------

local SPLIT_W, ROW_H = 270, 20
local function splits(r, rows, info)
  local f = panels.Splits
  if not f then
    f = panel("Splits", SPLIT_W, 120, true)
    local accent = f:CreateTexture(nil, "ARTWORK"); accent:SetSize(3, 14); accent:SetPoint("TOPLEFT", 14, -13); UI.Accented(accent)
    f.title = UI.Text(f, 13); f.title:SetPoint("LEFT", accent, "RIGHT", 8, 0); f.title:SetWidth(SPLIT_W - 40)
    f.clock = UI.Text(f, 30); f.clock:SetPoint("TOPLEFT", 14, -34)
    f.total = UI.Text(f, 12, C.dim, "RIGHT"); f.total:SetPoint("TOPRIGHT", -14, -46)
    f.rule = f:CreateTexture(nil, "ARTWORK"); f.rule:SetColorTexture(1, 1, 1, 0.08); f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", 14, -74); f.rule:SetPoint("TOPRIGHT", -14, -74)
    f.rows = {}
    f.foot = UI.Text(f, 11, C.dim); f.foot:SetWidth(SPLIT_W - 28)
  end
  f.title:SetText(ns.RunName and ns.RunName(r) or r.dungeon or "Dungeon")
  f.clock:SetText(clockText(r))
  local last, lastDelta
  for i, x in ipairs(rows) do
    local row = f.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, f); row:SetSize(SPLIT_W - 28, ROW_H)
      row.mark = row:CreateTexture(nil, "ARTWORK"); row.mark:SetSize(3, ROW_H - 6); row.mark:SetPoint("LEFT", -8, 0); UI.Accented(row.mark)
      row.name = UI.Text(row, 12); row.name:SetPoint("LEFT"); row.name:SetWidth(SPLIT_W - 28 - 106)
      row.delta = UI.Text(row, 12, C.dim, "RIGHT"); row.delta:SetPoint("RIGHT", -50, 0); row.delta:SetWidth(54)
      row.time = UI.Text(row, 12, C.text, "RIGHT"); row.time:SetPoint("RIGHT"); row.time:SetWidth(48)
      f.rows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 14, -80 - (i - 1) * ROW_H)
    row.name:SetText(x.name or "?")
    row.mark:SetShown(x.fighting)
    if x.kill then
      row.name:SetTextColor(unpack(C.text))
      row.time:SetText(UI.Time(x.kill.killedAt or 0)); row.time:SetTextColor(unpack(C.text))
      if x.best then
        local d = (x.kill.killedAt or 0) - x.best
        row.delta:SetText((d <= 0 and GREEN or RED) .. signed(d) .. "|r")
        if not last or (x.kill.killedAt or 0) >= (last.kill.killedAt or 0) then last, lastDelta = x, d end
      else row.delta:SetText("") end
    elseif x.fighting then
      row.name:SetTextColor(UI.Accent())
      row.delta:SetText("")
      row.time:SetText("now"); row.time:SetTextColor(UI.Accent())
    else
      row.name:SetTextColor(unpack(C.dim))
      row.delta:SetText("")
      row.time:SetText(x.best and UI.Time(x.best) or "-"); row.time:SetTextColor(unpack(C.faint))
    end
    row:Show()
  end
  for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
  f.total:SetText(lastDelta and ((lastDelta <= 0 and GREEN or RED) .. signed(lastDelta) .. "|r") or (info.dead .. "/" .. #rows .. " bosses"))
  local y = -80 - #rows * ROW_H - 6
  if info.total then
    f.foot:SetText("Best " .. UI.Time(info.total) .. (info.by and ("  ·  " .. info.by) or ""))
  else
    f.foot:SetText("No best run yet: this one sets it")
  end
  f.foot:ClearAllPoints(); f.foot:SetPoint("TOPLEFT", 14, y)
  f:SetHeight(-y + 24)
  f:Show()
end

-- ---- progress strip ------------------------------------------------------------------------

local ICON, GAP = 36, 8
local function strip(r, rows, info)
  local f = panels.Strip
  if not f then
    f = panel("Strip", 300, 78, true)
    f.title = UI.Text(f, 12); f.title:SetPoint("TOPLEFT", 12, -9)
    f.clock = UI.Text(f, 12, C.text, "RIGHT"); f.clock:SetPoint("TOPRIGHT", -12, -9)
    f.icons = {}
  end
  f.title:SetText((ns.RunName and ns.RunName(r) or r.dungeon or "Dungeon") .. "  |cff999fb0" .. info.dead .. "/" .. #rows .. "|r")
  f.clock:SetText(clockText(r))
  local ar, ag, ab = UI.Accent()
  for i, x in ipairs(rows) do
    local p = f.icons[i]
    if not p then
      p = portrait(f, ICON)
      p.check = p:CreateTexture(nil, "OVERLAY"); p.check:SetSize(16, 16); p.check:SetPoint("BOTTOMRIGHT", 3, -3)
      p.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      f.icons[i] = p
    end
    paintPortrait(p, x.b)
    local dead = x.kill ~= nil
    p.tex:SetDesaturated(dead); p.tex:SetAlpha(dead and 0.5 or 1)
    p.check:SetShown(dead)
    if x.fighting then p.ring:SetVertexColor(1, 0.55, 0.2, 1)
    elseif dead then p.ring:SetVertexColor(ar, ag, ab, 1)
    else p.ring:SetVertexColor(1, 1, 1, 0.2) end
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", 14 + (i - 1) * (ICON + GAP), -32)
    p:Show()
  end
  for i = #rows + 1, #f.icons do f.icons[i]:Hide() end
  f:SetWidth(dockCorner() and DOCK.Strip[3] or math.max(220, 28 + #rows * (ICON + GAP) - GAP))
  f:Show()
end

-- ---- boss cards ----------------------------------------------------------------------------

local BOSS_W, BOSS_H = 440, 92
local function bossHolder()
  local f = panels.Boss
  if f then return f end
  f = panel("Boss", BOSS_W, BOSS_H, false)
  local c = CreateFrame("Frame", nil, f); c:SetAllPoints()
  UI.Fill(c, C.bg); UI.Border(c, { 1, 1, 1, 0.14 })
  c.bar = c:CreateTexture(nil, "ARTWORK"); c.bar:SetWidth(4); c.bar:SetPoint("TOPLEFT"); c.bar:SetPoint("BOTTOMLEFT")
  c.por = portrait(c, 60); c.por:SetPoint("LEFT", 20, 0)
  c.cap = UI.Text(c, 11, C.dim); c.cap:SetPoint("TOPLEFT", 96, -16)
  c.name = UI.Text(c, 22); c.name:SetPoint("TOPLEFT", 96, -32); c.name:SetWidth(BOSS_W - 110)
  c.sub = UI.Text(c, 12, C.dim); c.sub:SetPoint("TOPLEFT", 96, -62); c.sub:SetWidth(BOSS_W - 110)
  c:Hide()
  f.card = c
  return f
end

-- kind: "pull", "kill" or "wipe"
local function bossCard(kind, boss, caption, sub, hold)
  if not on("streamBoss") then return end
  local f = bossHolder()
  local c = f.card
  local r, g, b = UI.Accent()
  if kind == "kill" then r, g, b = 0.44, 0.83, 0.60 elseif kind == "wipe" then r, g, b = 0.94, 0.42, 0.42 end
  c.bar:SetColorTexture(r, g, b, 1)
  c.por.ring:SetVertexColor(r, g, b, 1)
  paintPortrait(c.por, boss)
  c.por.tex:SetDesaturated(kind == "kill")
  c.cap:SetText(caption); c.cap:SetTextColor(r, g, b)
  c.name:SetText(boss.name or "Boss")
  c.sub:SetText(sub or "")
  c.kind = kind
  flash(c, hold or 6)
end

local function findRow(rows, id, name)
  for i, x in ipairs(rows) do if isBoss(x.b, id, name) then return x, i end end
end

local function onPull(r, id, name)
  local rows, info = model(r)
  local x = findRow(rows, id, name)
  local boss = x and x.b or { name = name, encounterID = id }
  local bits = {}
  if x and x.level then bits[#bits + 1] = "Level " .. x.level end
  if x and x.best then bits[#bits + 1] = "guild best split " .. UI.Time(x.best) end
  local wishes = ns.WishesHere and ns.WishesHere(r.dungeon)[boss.name]
  if wishes and wishes[1] then bits[#bits + 1] = GOLD .. "drops " .. (wishes[1].n or "a wishlist item") .. "|r" end
  bossCard("pull", boss, string.format("BOSS %d OF %d", math.min(info.dead + 1, math.max(1, #rows)), math.max(1, #rows)), table.concat(bits, "  ·  "), 6)
end

local function onEnd(r, id, name, success, fought)
  local rows = model(r)
  local x = findRow(rows, id, name)
  local boss = x and x.b or { name = name, encounterID = id }
  local bits = {}
  if fought then bits[#bits + 1] = (success and "Killed in " or "Lasted ") .. UI.Time(math.floor(fought + 0.5)) end
  if success then
    local at = x and x.kill and x.kill.killedAt
    if at then
      local s = "split " .. UI.Time(at)
      if x.best then local d = at - x.best; s = s .. "  " .. (d <= 0 and GREEN or RED) .. signed(d) .. "|r" end
      bits[#bits + 1] = s
    end
    bossCard("kill", boss, "DEFEATED", table.concat(bits, "  ·  "), 9)
  else
    local w = r.wipes or 0
    if w > 0 then bits[#bits + 1] = w == 1 and "first wipe" or ("wipe " .. w) end
    bossCard("wipe", boss, "WIPE", table.concat(bits, "  ·  "), 6)
  end
end

-- once the damage meter has closed the fight: who did the most to the boss
local function addTopDamage(r)
  local c = panels.Boss and panels.Boss.card
  if not (c and c:IsShown() and c.kind == "kill") then return end
  local seg = r.segments and r.segments[#r.segments]
  if not (seg and seg.kind == "boss" and type(seg.stats) == "table") then return end
  local who, most = nil, 0
  for name, s in pairs(seg.stats) do
    if type(s.damage) == "number" and s.damage > most then who, most = name, s.damage end
  end
  if not who or c.topped == seg then return end
  c.topped = seg
  local cur = c.sub:GetText() or ""
  c.sub:SetText(cur .. (cur ~= "" and "  ·  " or "") .. "top damage " .. UI.ShortName(who) .. " " .. UI.Num(most))
end

-- ---- loot cards ----------------------------------------------------------------------------

local LOOT_W, LOOT_H, LOOT_MAX = 320, 48, 3
local lootPool, lootShown, lootQueue = {}, {}, {}

local function lootHolder()
  return panels.Loot or panel("Loot", LOOT_W, LOOT_MAX * (LOOT_H + 6) + 16, false)
end

local function lootLayout()
  for i, c in ipairs(lootShown) do
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", panels.Loot, "TOPLEFT", 0, -(i - 1) * (LOOT_H + 6))
  end
end

local showLoot
local function lootDone(c)
  for i, x in ipairs(lootShown) do if x == c then table.remove(lootShown, i) break end end
  lootPool[#lootPool + 1] = c
  lootLayout()
  local nextUp = table.remove(lootQueue, 1)
  if nextUp then showLoot(nextUp) end
end

function showLoot(item)
  if #lootShown >= LOOT_MAX then lootQueue[#lootQueue + 1] = item; return end
  local f = lootHolder()
  local c = table.remove(lootPool)
  if not c then
    c = CreateFrame("Frame", nil, f); c:SetSize(LOOT_W, LOOT_H)
    UI.Fill(c, C.bg); c.edges = UI.Border(c, { 1, 1, 1, 0.14 })
    c.bar = c:CreateTexture(nil, "ARTWORK"); c.bar:SetWidth(3); c.bar:SetPoint("TOPLEFT"); c.bar:SetPoint("BOTTOMLEFT")
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(34, 34); c.icon:SetPoint("LEFT", 12, 0); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.name = UI.Text(c, 13); c.name:SetPoint("TOPLEFT", 56, -8); c.name:SetWidth(LOOT_W - 66)
    c.sub = UI.Text(c, 11, C.dim); c.sub:SetPoint("TOPLEFT", 56, -27); c.sub:SetWidth(LOOT_W - 66)
  end
  local r, g, b = 1, 1, 1
  if UI.QualityColor then local qr, qg, qb = UI.QualityColor(item.q); if qr then r, g, b = qr, qg, qb end end
  c.bar:SetColorTexture(r, g, b, 1)
  c.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  c.name:SetText(item.name or "Item"); c.name:SetTextColor(r, g, b)
  local sub = (item.who or "Someone") .. " got it" .. (item.boss and ("  ·  " .. item.boss) or "")
  if item.wish then sub = GOLD .. "On your wishlist!|r  " .. sub end
  c.sub:SetText(sub)
  lootShown[#lootShown + 1] = c
  lootLayout()
  flash(c, item.wish and 12 or 7, lootDone)
end

-- Modules/Loot.lua calls this for every new item someone in the group got.
function ns.OnLootGot(r, g, link)
  if not (ns.settings.stream and on("streamLoot")) or not r or r._notDungeon then return end
  local wish = ns.WishKind and ns.WishKind(g.i) and true or false
  if not wish and (g.q or 1) < 2 then return end -- greens and better
  local name, _, _, icon
  if UI.ItemLook then name, _, _, icon = UI.ItemLook(g.i) end
  name = name or (type(link) == "string" and link:match("%[(.-)%]")) or "Item"
  showLoot({ name = name, icon = icon, q = g.q, who = g.w, boss = g.b, wish = wish })
end

-- ---- the map -------------------------------------------------------------------------------

local MAP_W, MAP_H = 360, 240
local function map(r, rows)
  local d = ns.Dungeons and ns.Dungeons[r.instanceID]
  local dname = d and d.name or r.dungeon
  local floors = ns.DungeonFloors and ns.DungeonFloors(dname) or {}
  if #floors == 0 then
    -- no picture of this dungeon anywhere: nothing to show
    if panels.Map then panels.Map:Hide() end
    return
  end
  local f = panels.Map
  if not f then
    f = panel("Map", MAP_W + 20, MAP_H + 64, true)
    f.title = UI.Text(f, 12); f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetWidth(MAP_W - 4)
    f.canvas = UI.MapCanvas(f)
    f.canvas:SetPoint("TOP", 0, -30)
    f.canvas:EnableMouse(false) -- drags go to the window
    f.where = UI.Text(f, 12); f.where:SetPoint("BOTTOMLEFT", 12, 11); f.where:SetWidth(MAP_W - 4)
    f.lines = {}
    -- "the group is here": a slow pulse behind the boss's pin
    local here = CreateFrame("Frame", nil, f.canvas); here:SetSize(54, 54)
    here.tex = here:CreateTexture(nil, "OVERLAY"); here.tex:SetAllPoints(); here.tex:SetColorTexture(1, 1, 1, 1); UI.Round(here, here.tex)
    if here.CreateAnimationGroup then
      local ag = here:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
      local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0.75); a:SetToAlpha(0.15); a:SetDuration(0.9)
      here.pulse = ag
    end
    here:Hide()
    f.here = here
  end

  -- where the group is: the boss being fought, else the last one killed
  local at, fighting
  for _, x in ipairs(rows) do
    if x.fighting then at, fighting = x, true end
  end
  if not at then
    for _, x in ipairs(rows) do
      if x.kill and (not at or (x.kill.killedAt or 0) >= (at.kill.killedAt or 0)) then at = x end
    end
  end

  local function spot(x) -- floor index, x, y of a boss's pin
    if not ns.BossPin then return nil end
    local pf, px, py = ns.BossPin(dname, x.name)
    if not pf then return nil end
    for i, fl in ipairs(floors) do if ns.PinOnFloor(pf, fl, i) then return i, px, py end end
  end

  local floorIdx = (at and spot(at)) or f.floorIdx or 1
  if floorIdx > #floors then floorIdx = 1 end
  f.floorIdx = floorIdx
  local floor = floors[floorIdx]

  local pins, killedHere = {}, {}
  local hx, hy
  local pinPx = 30
  for i, x in ipairs(rows) do
    local fi, px, py = spot(x)
    if fi == floorIdx then
      pins[#pins + 1] = { x = px, y = py, n = i, key = x.name, label = x.name, boss = true, on = x.kill ~= nil,
        look = ns.BossLook and ns.BossLook(dname, x.name), size = pinPx }
      if x.kill then killedHere[#killedHere + 1] = { at = x.kill.killedAt or 0, x = px, y = py } end
      if x == at then hx, hy = px, py end
    end
  end
  f.canvas:Draw(floor.map, MAP_W, MAP_H, pins, floor.tiles, floor)

  -- the route so far: a line from each boss killed to the next, in the order they died
  table.sort(killedHere, function(a, b) return a.at < b.at end)
  local route = killedHere
  if fighting and hx then route[#route + 1] = { x = hx, y = hy } end
  local ar, ag, ab = UI.Accent()
  local n = 0
  if f.canvas.CreateLine then
    for i = 2, #route do
      n = n + 1
      local l = f.lines[n]
      if not l then l = f.canvas:CreateLine(nil, "OVERLAY"); l:SetThickness(3); f.lines[n] = l end
      local a, b = route[i - 1], route[i]
      l:SetColorTexture(ar, ag, ab, 0.9)
      l:SetStartPoint("TOPLEFT", f.canvas, a.x / 1000 * MAP_W, -a.y / 1000 * MAP_H)
      l:SetEndPoint("TOPLEFT", f.canvas, b.x / 1000 * MAP_W, -b.y / 1000 * MAP_H)
      l:Show()
    end
  end
  for i = n + 1, #f.lines do f.lines[i]:Hide() end

  local here = f.here
  if hx then
    here:ClearAllPoints(); here:SetPoint("CENTER", f.canvas, "TOPLEFT", hx / 1000 * MAP_W, -hy / 1000 * MAP_H)
    here:SetFrameLevel(f.canvas:GetFrameLevel() + 1) -- under the pins
    if fighting then here.tex:SetVertexColor(1, 0.55, 0.2) else here.tex:SetVertexColor(ar, ag, ab) end
    here:Show()
    if here.pulse and not here.pulse:IsPlaying() then here.pulse:Play() end
  else
    here:Hide()
  end

  f.title:SetText(dname .. (floor.name and ("  |cff999fb0" .. floor.name .. "|r") or ""))
  local where
  if fighting then where = "|cffff8c33Fighting|r " .. at.name
  elseif at then
    local nextUp
    for _, x in ipairs(rows) do if not x.kill then nextUp = nextUp or x end end
    where = "Last boss down: " .. at.name .. (r.doneAt and ("  ·  " .. GREEN .. "cleared|r") or "")
    if not hx then where = where .. "  |cff999fb0(not on the map yet)|r" end
  else
    where = "|cff999fb0At the entrance|r"
  end
  f.where:SetText(where)
  f:Show()
end

-- ---- showing, hiding, refreshing ------------------------------------------------------------

local function hideAll()
  for _, f in pairs(panels) do f:Hide() end
end

local function draw()
  local r = run()
  if not r then hideAll(); return end
  local rows, info = model(r)
  if on("streamSplits") then splits(r, rows, info) elseif panels.Splits then panels.Splits:Hide() end
  if on("streamStrip") then strip(r, rows, info) elseif panels.Strip then panels.Strip:Hide() end
  if on("streamMap") then map(r, rows) elseif panels.Map then panels.Map:Hide() end
  if on("streamBoss") then holder(bossHolder(), true, "Boss cards show here") elseif panels.Boss then panels.Boss:Hide() end
  if on("streamLoot") then holder(lootHolder(), true, "Loot cards show here") elseif panels.Loot then panels.Loot:Hide() end
end

-- errors are kept where /fox errors shows them (WoW hides them otherwise)
local function refresh()
  if ns.Quests and ns.Quests.Try then ns.Quests.Try("stream overlays", draw) else pcall(draw) end
end
ns.RefreshStream = function()
  for _, f in pairs(panels) do place(f) end
  refresh()
  if ns.RefreshTracker then ns.RefreshTracker() end -- the dungeon tracker steps aside while these show
end

-- the clocks, once a second; everything else redraws when something happens
C_Timer.NewTicker(1, function()
  local r = run()
  if not r then
    for _, f in pairs(panels) do if f:IsShown() then f:Hide() end end
    return
  end
  local t = clockText(r)
  if panels.Splits and panels.Splits:IsShown() then panels.Splits.clock:SetText(t) end
  if panels.Strip and panels.Strip:IsShown() then panels.Strip.clock:SetText(t) end
  S.tick = (S.tick or 0) + 1
  if S.tick % 5 == 0 or not (panels.Splits or panels.Strip or panels.Map) then refresh() end
end)

-- ---- preview --------------------------------------------------------------------------------

-- A sample run of a dungeon Foxden has a map for, two bosses down and the third pulled.
local function sampleRun()
  local pick
  for _, id in ipairs({ 129, 33, 36, 43, 389 }) do
    local d = ns.Dungeons and ns.Dungeons[id]
    if d and not pick and ns.DungeonFloors and #ns.DungeonFloors(d.name) > 0 then pick = id end
  end
  pick = pick or 129
  local d = (ns.Dungeons and ns.Dungeons[pick]) or { name = "Razorfen Downs", bosses = {} }
  local r = { id = "stream-test", dungeon = d.name, instanceID = pick, startTime = GetServerTime() - 431, pulled = true, wipes = 0, bosses = {} }
  for i = 1, math.min(2, #d.bosses) do
    local b = d.bosses[i]
    r.bosses[i] = { id = b.ids and b.ids[1], name = b.name, killedAt = 60 + i * 110 }
  end
  local third = d.bosses[3]
  return r, third
end

function ns.StreamTest()
  if S.test then
    S.test, S.fight = nil, nil
    refresh()
    ns.say("Stream preview off.", true)
    return
  end
  local r, third = sampleRun()
  S.test = r
  S.fight = third and { id = third.ids and third.ids[1], name = third.name, at = GetTime() - 20 } or nil
  refresh()
  if third then onPull(r, S.fight.id, S.fight.name) end
  showLoot({ name = "Sample Blade of the Fox", icon = "Interface\\Icons\\INV_Sword_27", q = 3, who = UnitName("player"), boss = r.bosses[1] and r.bosses[1].name })
  showLoot({ name = "Sample Wishlist Ring", icon = "Interface\\Icons\\INV_Jewelry_Ring_15", q = 4, who = UnitName("player"), boss = r.bosses[2] and r.bosses[2].name, wish = true })
  ns.say("Stream preview: drag each window where you want it, then /fox stream test again to end it.", true)
end

function ns.ToggleStream()
  ns.settings.stream = not ns.settings.stream
  ns.say("Stream overlays " .. (ns.settings.stream and "on: they show while you're in a dungeon run. /fox stream test previews them." or "off."), true)
  ns.RefreshStream()
end

function ns.ResetStreamPositions()
  ns.settings.streamPos = nil
  ns.RefreshStream()
end

ns.RegisterModule({
  name = "Stream",
  OnRunStart = function() S.fight = nil; C_Timer.After(0.3, refresh) end,
  OnRunResume = function() C_Timer.After(0.3, refresh) end,
  OnRunFinish = function() S.fight = nil; C_Timer.After(0.1, refresh) end,
  OnCombatEnd = function(_, r) if ns.settings.stream and r then addTopDamage(r); refresh() end end,
  events = {
    ENCOUNTER_START = function(_, r, id, name)
      if not r or r._notDungeon or ns.IsSecret(id) or ns.IsSecret(name) then return end
      S.fight = { id = id, name = name, at = GetTime() }
      if not ns.settings.stream then return end
      refresh()
      onPull(r, id, name)
    end,
    ENCOUNTER_END = function(_, r, id, name, _, _, success)
      local fight = S.fight
      S.fight = nil
      if not r or r._notDungeon or not ns.settings.stream or ns.IsSecret(id) or ns.IsSecret(name) then return end
      refresh()
      onEnd(r, id, name, success == 1, fight and (GetTime() - fight.at) or nil)
    end,
  },
})
