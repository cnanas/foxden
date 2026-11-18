-- Foxden: quest marks on the world map and the minimap.
--   "!"  a quest you can pick up (every quest QuestieDB knows: Core/Quests.lua), and for
--        dungeon quests the next step of their chain you haven't done, ringed in the accent
--        colour, with where it leads (the website's quest rows, chains from QuestieDB and what
--        guild members learned in game).
--   "?"  a finished quest in your log: where to turn it in.
-- Hover for the quests at that spot; click a dungeon quest's mark to open it in Foxden.
-- World map: drawn by MapPins (ns.DrawQuestPins). Minimap: UI/MinimapPins.lua (ns.QuestMarks).

local _, ns = ...
local UI = ns.UI
local pins = {}
ns.questPinFrames = pins -- for /fox debugging and the test harness

local function hex(r, g, b) return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end

local function nameOfSlug()
  local out = {}
  for _, d in pairs(ns.Dungeons or {}) do out[ns.Slug(d.name)] = d.name end
  return out
end

-- Dungeon quests (the website's rows): each one's next chain step, by giver.
local function dungeonGivers()
  local site = ns.Site and ns.Site()
  local all = site and type(site.quests) == "table" and site.quests
  if not all then return {} end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  local fac = mine == "Alliance" and "A" or mine == "Horde" and "H" or nil
  local level = UnitLevel and UnitLevel("player") or 60
  local names = nameOfSlug()
  local function state(id) return ns.QuestState and ns.QuestState(id) end
  local function forMe(f) return f == nil or f == "" or f == "B" or not fac or f == fac end
  local givers, seen = {}, {}
  for slug, rows in pairs(all) do
    for _, q in ipairs(type(rows) == "table" and rows or {}) do
      if type(q) == "table" then q = ns.Quests.Enrich(q) end
      if type(q) == "table" and forMe(q[3]) and not state(q[1]) then
        -- the step to pick up next: the first one of its chain you haven't done
        local chain, stepId, title, npc, map, x, y, min, k, n = q[23], q[1], q[2], q[6], q[8], q[9], q[10], (q[5] or 0) > 0 and q[5] or q[4], nil, nil
        local qlevel = tonumber(q[4]) or 0
        local skip = false
        if type(chain) == "table" and #chain > 1 then
          for i, st in ipairs(chain) do
            local s = state(st[1])
            if s ~= "done" then
              if s == "have" or not forMe(st[8]) then skip = true -- you're on it, or it's the other faction's version
              elseif st[1] ~= q[1] then
                stepId, title, npc, map, x, y, min, k, n = st[1], st[2], st[3], st[4], st[5], st[6], st[7], i, #chain
                qlevel = tonumber(st[9]) or 0
              end
              break
            end
          end
        end
        min = tonumber(min) or 0
        if not skip and (tonumber(map) or 0) > 0 and (min == 0 or min <= level + ns.Quests.Ahead()) and (qlevel == 0 or (ns.settings and ns.settings.questShowGrey) or level - qlevel <= ns.Quests.GreyBelow()) then
          local key = ns.Quests.KeyOf(map, x, y)
          local g = givers[key]
          if not g then g = { npc = npc, map = map, x = x, y = y, quests = {} }; givers[key] = g end
          if (not g.npc or g.npc == "") and npc and npc ~= "" then g.npc = npc end
          local sk = key .. "/" .. stepId
          local entry = seen[sk]
          if not entry then
            entry = { id = stepId, title = title, min = min, level = qlevel, kind = "new", k = k, n = n, leadsTo = {}, dungeon = names[slug] or slug, slug = slug, dq = q[1], objective = (stepId == q[1]) and q[12] or nil }
            seen[sk] = entry
            g.quests[#g.quests + 1] = entry
          end
          if stepId ~= q[1] then entry.leadsTo[#entry.leadsTo + 1] = q[2] end
        end
      end
    end
  end
  return givers
end

-- Everything to mark, by spot: every available quest and turn-in, merged with the dungeon
-- quests' chain steps. Cached until your quest log, level or the settings change.
local marksCache
function ns.QuestMarksDirty() marksCache = nil end
function ns.QuestMarks()
  if marksCache then return marksCache end
  local out = {}
  local function giver(k, g)
    local t = out[k]
    if not t then t = { npc = g.npc, map = g.map, x = g.x, y = g.y, quests = {}, byId = {} }; out[k] = t end
    if (t.npc == nil or t.npc == "") and g.npc and g.npc ~= "" then t.npc = g.npc end
    return t
  end
  local settings = ns.settings or {}
  if settings.questPinsAll ~= false and ns.Quests then
    for k, g in pairs(ns.Quests.Givers()) do
      local t = giver(k, g)
      for _, e in ipairs(g.quests) do t.quests[#t.quests + 1] = e; t.byId[e.id] = e end
    end
  end
  if settings.questPins ~= false then
    for k, g in pairs(dungeonGivers()) do
      local t = giver(k, g)
      for _, e in ipairs(g.quests) do
        local have = t.byId[e.id]
        if have then
          have.k, have.n, have.leadsTo, have.dungeon, have.slug, have.dq = e.k, e.n, e.leadsTo, e.dungeon, e.slug, e.dq
          have.objective = have.objective or e.objective
        else t.quests[#t.quests + 1] = e; t.byId[e.id] = e end
      end
    end
  end
  for _, g in pairs(out) do
    g.turnin, g.dungeon, g.high = false, false, true
    local level = UnitLevel and UnitLevel("player") or 60
    for _, e in ipairs(g.quests) do
      if e.kind == "turnin" then g.turnin = true end
      if e.dungeon then g.dungeon = true end
      if e.kind == "turnin" or (e.min or 0) <= level then g.high = false end
    end
  end
  marksCache = out
  return out
end
if ns.Quests then ns.Quests.OnChange(function() marksCache = nil end) end

-- The hover card for one spot.
-- 2850 -> "2,850"
local function commas(n) local s = tostring(math.floor(n + 0.5)); while true do local k; s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2"); if k == 0 then return s end end end
local hovered -- the mark under the mouse, to redraw its card when Shift changes
local shiftWatch = CreateFrame("Frame")
shiftWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
shiftWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- item names arrive a moment after we ask
local redrawSoon = false
shiftWatch:SetScript("OnEvent", function(_, event, key)
  if not (hovered and hovered:IsVisible() and GameTooltip:IsOwned(hovered)) then return end
  if event == "MODIFIER_STATE_CHANGED" then
    if key == "LSHIFT" or key == "RSHIFT" then ns.QuestMarkTooltip(hovered, hovered.giver) end
  elseif IsShiftKeyDown and IsShiftKeyDown() and not redrawSoon then
    redrawSoon = true
    C_Timer.After(0.1, function() redrawSoon = false; if hovered and GameTooltip:IsOwned(hovered) then ns.QuestMarkTooltip(hovered, hovered.giver) end end)
  end
end)
-- ---- rewards (Shift) -------------------------------------------------------------------
local function itemText(id, name, count)
  local iname, _, quality, _, _, _, _, _, _, icon
  if C_Item and C_Item.GetItemInfo then iname, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id) end
  if not iname and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
  local r, g, b = 1, 1, 1
  if quality and C_Item and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
  return (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. hex(r or 1, g or 1, b or 1) .. (iname or name or ("Item " .. id)) .. "|r" .. ((count or 1) > 1 and (" x" .. count) or "")
end
local function factionName(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id); if ok and type(d) == "table" and d.name then return d.name end
  end
  if GetFactionInfoByID then local ok, n = pcall(GetFactionInfoByID, id); if ok and n then return n end end
  return "faction " .. id
end
local function siteRow(id)
  local site = ns.Site and ns.Site()
  for _, rows in pairs(site and type(site.quests) == "table" and site.quests or {}) do
    for _, d in ipairs(type(rows) == "table" and rows or {}) do if d[1] == id then return d end end
  end
end
-- Lines for one quest's rewards: gold, items you get, items you choose from, reputation.
local function rewardLines(id)
  local out, money, items, choice, rep = {}, nil, {}, {}, {}
  if ns.Quests.InLog(id) then
    -- in your log: the game knows exactly
    if GetQuestLogRewardMoney then local ok, m = pcall(GetQuestLogRewardMoney, id); if ok then money = m end end
    local okN, n = false, 0
    if GetNumQuestLogRewards then okN, n = pcall(GetNumQuestLogRewards, id) end
    for i = 1, okN and n or 0 do
      local ok, name, tex, count, quality, _, itemID = pcall(GetQuestLogRewardInfo, i, id)
      if ok and name then items[#items + 1] = itemID and itemText(itemID, name, count) or ("|T" .. tostring(tex) .. ":14|t " .. name) end
    end
    local okC, nc = false, 0
    if GetNumQuestLogChoices then okC, nc = pcall(GetNumQuestLogChoices, id, true) end
    for i = 1, okC and nc or 0 do
      local ok, name, tex, count, quality, _, itemID = pcall(GetQuestLogChoiceInfo, i, id)
      if ok and name then choice[#choice + 1] = itemID and itemText(itemID, name, count) or ("|T" .. tostring(tex) .. ":14|t " .. name) end
    end
  end
  local d = siteRow(id)
  if d then
    -- the website's copy of Blizzard's quest data (dungeon quests)
    if not money and (d[15] or 0) > 0 then money = d[15] end
    if #items == 0 then for _, iid in ipairs(type(d[17]) == "table" and d[17] or {}) do items[#items + 1] = itemText(iid) end end
    if #choice == 0 then for _, iid in ipairs(type(d[18]) == "table" and d[18] or {}) do choice[#choice + 1] = itemText(iid) end end
    if type(d[16]) == "string" and d[16] ~= "" then rep[#rep + 1] = d[16] end
  end
  -- every other quest: the website's copy of Blizzard's rewards (through the companion)
  local site = ns.Site and ns.Site()
  local rw = site and type(site.rewards) == "table" and (site.rewards[id] or site.rewards[tostring(id)])
  if type(rw) == "table" then
    if not money and (rw[1] or 0) > 0 then money = rw[1] end
    if #items == 0 then for _, iid in ipairs(type(rw[2]) == "table" and rw[2] or {}) do items[#items + 1] = itemText(iid) end end
    if #choice == 0 then for _, iid in ipairs(type(rw[3]) == "table" and rw[3] or {}) do choice[#choice + 1] = itemText(iid) end end
    if #rep == 0 and type(rw[4]) == "string" and rw[4] ~= "" then rep[#rep + 1] = rw[4] end
  end
  local r = ns.QuestDB and ns.QuestDB[id]
  if #rep == 0 and r and type(r[24]) == "table" then
    for _, x in ipairs(r[24]) do if type(x) == "table" and x[1] then rep[#rep + 1] = (x[2] or 0) .. " " .. factionName(x[1]) end end
  end
  if money and money > 0 then out[#out + 1] = ns.Money(money) end
  if #items > 0 then out[#out + 1] = "You get: " .. table.concat(items, ", ") end
  if #choice > 0 then out[#out + 1] = "Choose: " .. table.concat(choice, ", ") end
  if #rep > 0 then out[#out + 1] = "|cff8fb3ff" .. table.concat(rep, ", ") .. " reputation|r" end
  -- the website's list covers every quest Blizzard's API has: not in it = no gold or items
  if #out == 0 then out[#out + 1] = "|cff99a1b0" .. ((site and type(site.rewards) == "table") and "No gold or item reward" or "Rewards show once your guild's website sends them") .. "|r" end
  return out
end

ns.QuestRewardLines = rewardLines
ns.ItemText = itemText
-- A quest's reputation reward as text: the website's copy of Blizzard's data, else QuestieDB's.
function ns.QuestRep(id)
  local site = ns.Site and ns.Site()
  local rw = site and type(site.rewards) == "table" and (site.rewards[id] or site.rewards[tostring(id)])
  if type(rw) == "table" and type(rw[4]) == "string" and rw[4] ~= "" then return rw[4] end
  local d = siteRow(id)
  if d and type(d[16]) == "string" and d[16] ~= "" then return d[16] end
  local r = ns.QuestDB and ns.QuestDB[id]
  if r and type(r[24]) == "table" then
    local out = {}
    for _, x in ipairs(r[24]) do if type(x) == "table" and x[1] then out[#out + 1] = (x[2] or 0) .. " " .. factionName(x[1]) end end
    if #out > 0 then return table.concat(out, ", ") end
  end
end
ns.Commas = commas

-- The hover card: who's there and their quests, with XP; Shift adds gold and rewards.
function ns.QuestMarkTooltip(owner, g, anchor)
  if not g then return end
  hovered = owner
  local shift = IsShiftKeyDown and IsShiftKeyDown()
  local ar, ag, ab = UI.Accent()
  local level = UnitLevel and UnitLevel("player") or 60
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  local groups = g.members or { g }
  local shown = 0
  for gi, m in ipairs(groups) do
    local name = m.npc and m.npc ~= "" and m.npc or "Quest"
    if gi == 1 then GameTooltip:SetText(name, ar, ag, ab) else GameTooltip:AddLine(" "); GameTooltip:AddLine(name, ar, ag, ab) end
    for _, e in ipairs(m.quests) do
      shown = shown + 1
      if shown > 14 then break end
      local xp = ns.Quests.XP(e.id, e.level)
      local xpText = xp and (commas(xp) .. " XP") or ""
      if e.kind == "turnin" then
        GameTooltip:AddDoubleLine("Turn in: " .. (e.title or "?"), xpText ~= "" and xpText or "Ready", 0.43, 0.83, 0.6, 0.43, 0.83, 0.6)
      else
        local lv = (e.min or 0) > 0 and ("[" .. e.min .. "] ") or ""
        local r, gg, b = ns.Quests.Color(e.level)
        if (e.min or 0) > level then r, gg, b = 1, 0.35, 0.35 end
        GameTooltip:AddDoubleLine(lv .. (e.title or "?"), xpText, r, gg, b, 0.85, 0.87, 0.9)
        if e.k then GameTooltip:AddLine("   Step " .. e.k .. " of " .. e.n .. " toward " .. table.concat(e.leadsTo or {}, ", ") .. " (" .. (e.dungeon or "") .. ")", 0.85, 0.87, 0.9, true)
        elseif e.dungeon then GameTooltip:AddLine("   Dungeon: " .. e.dungeon, 0.85, 0.87, 0.9) end
        if not shift and e.objective and e.objective ~= "" then GameTooltip:AddLine("   " .. e.objective, 1, 1, 1, true) end
        if not e.k and e.leadsTo and #e.leadsTo > 0 then GameTooltip:AddLine("   Leads to " .. table.concat(e.leadsTo, ", "), 0.85, 0.87, 0.9, true) end
      end
      if shift then for _, l in ipairs(rewardLines(e.id)) do GameTooltip:AddLine("   " .. l, 1, 1, 1, true) end end
    end
  end
  local total = 0
  for _, m in ipairs(groups) do total = total + #m.quests end
  if total > 14 then GameTooltip:AddLine("   ...and " .. (total - 14) .. " more", 0.7, 0.72, 0.78) end
  GameTooltip:AddLine(" ")
  if not shift then GameTooltip:AddLine("Hold Shift for gold and rewards", 0.6, 0.63, 0.69) end
  GameTooltip:AddLine("Right-click: arrow to them", 0.6, 0.63, 0.69)
  if g.dungeon then GameTooltip:AddLine(hex(ar, ag, ab) .. "Click to open the dungeon quest in Foxden|r") end
  GameTooltip:Show()
end

-- Marks closer than this (in the mark's own units) become one, with a count.
function ns.ClusterMarks(list, dist)
  local out = {}
  for _, m in ipairs(list) do
    local into
    for _, c in ipairs(out) do
      local dx, dy = c.x - m.x, c.y - m.y
      if dx * dx + dy * dy < dist * dist then into = c; break end
    end
    if into then
      local n = #into.parts
      into.x, into.y = (into.x * n + m.x) / (n + 1), (into.y * n + m.y) / (n + 1)
      into.parts[n + 1] = m.g
    else
      out[#out + 1] = { x = m.x, y = m.y, parts = { m.g } }
    end
  end
  for _, c in ipairs(out) do
    if #c.parts == 1 then c.g = c.parts[1]
    else
      local g = { npc = c.parts[1].npc, quests = {}, members = c.parts, turnin = false, dungeon = false, high = true }
      for _, p in ipairs(c.parts) do
        for _, e in ipairs(p.quests) do g.quests[#g.quests + 1] = e end
        g.turnin = g.turnin or p.turnin; g.dungeon = g.dungeon or p.dungeon; g.high = g.high and p.high
      end
      c.g = g
    end
  end
  return out
end

-- One mark, drawn by Foxden (no game art, which this client may not have): a round badge
-- with "!" (a quest to pick up) or "?" (a turn-in) in gold, ringed in the accent colour for
-- dungeon quests, the "!" red when every quest there is above your level.
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function ns.MakeQuestMark(parent)
  local p = CreateFrame("Button", nil, parent)
  -- white once, masked round, then tinted: masked textures don't like being re-textured
  p.ring = p:CreateTexture(nil, "ARTWORK"); p.ring:SetPoint("CENTER")
  p.ring:SetColorTexture(1, 1, 1, 1); UI.Round(p, p.ring)
  p.bg = p:CreateTexture(nil, "ARTWORK", nil, 1); p.bg:SetPoint("CENTER")
  p.bg:SetColorTexture(1, 1, 1, 1); UI.Round(p, p.bg)
  p.bg:SetVertexColor(0.07, 0.07, 0.09, 0.92)
  p.txt = p:CreateFontString(nil, "OVERLAY"); p.txt:SetPoint("CENTER", 0.5, 0)
  -- how many quests when there's more than one
  p.num = p:CreateFontString(nil, "OVERLAY"); p.num:SetPoint("CENTER", p, "TOPRIGHT", -2, -2)
  p:SetScript("OnEnter", function(s) ns.QuestMarkTooltip(s, s.giver) end)
  p:SetScript("OnLeave", function(s) if hovered == s then hovered = nil end; GameTooltip:Hide() end)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnClick", function(s, button)
    local g = s.giver
    if button == "RightButton" and g then
      local m = g.members and g.members[1] or g
      if ns.SetArrow then ns.SetArrow(m.map, m.x, m.y, m.npc, m.quests[1] and m.quests[1].title) end
      return
    end
    for _, e in ipairs(s.giver and s.giver.quests or {}) do
      if e.slug and ns.OpenPage then ns.OpenPage("journal", { dungeon = e.slug, view = "quests", quest = e.dq }); return end
    end
  end)
  function p:Set(g, size)
    self.giver = g
    self:SetSize(size, size)
    self.ring:SetSize(size, size); self.bg:SetSize(size - 4, size - 4)
    if g.dungeon then local r, gg, b = UI.Accent(); self.ring:SetVertexColor(r, gg, b, 1)
    elseif g.turnin then self.ring:SetVertexColor(0.43, 0.83, 0.6, 1)
    else self.ring:SetVertexColor(1, 0.82, 0, 1) end
    if self.fontSize ~= size then
      self.fontSize = size
      self.txt:SetFont(UI.Font(), math.max(9, math.floor(size * 0.72)), "OUTLINE")
    end
    self.txt:SetText(g.turnin and "?" or "!")
    local count = #g.quests
    if count > 1 then
      if self.numSize ~= size then self.numSize = size; self.num:SetFont(UI.Font(), math.max(8, math.floor(size * 0.5)), "OUTLINE") end
      self.num:SetText(count); self.num:Show()
    else self.num:Hide() end
    if g.high and not g.turnin then self.txt:SetTextColor(1, 0.45, 0.45) else self.txt:SetTextColor(1, 0.82, 0) end
  end
  return p
end

-- child: the world map canvas; shown: the map on screen. Zone maps show everything; zoomed out
-- to a continent only dungeon quests and turn-ins (every quest would bury the map).
-- The layer to draw on: the map hands out layers to everything on it (its art, fog, Blizzard's
-- pins, other addons), often far above the canvas itself. Ask it for the top one.
function ns.MapMarkLevel(child)
  local mgr = WorldMapFrame and WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if mgr and mgr.GetValidFrameLevel then
    for _, name in ipairs({ "PIN_FRAME_LEVEL_TOPMOST", "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "PIN_FRAME_LEVEL_AREA_POI" }) do
      local ok, lvl = pcall(mgr.GetValidFrameLevel, mgr, name)
      if ok and type(lvl) == "number" and lvl > 0 then return math.min(9990, lvl + 2) end
    end
  end
  return math.min(9000, (child:GetFrameLevel() or 1) + 500)
end
local drawn, lastMap = 0, nil
function ns.QuestMapStatus()
  local hooked = ns.WorldMapHooked and ns.WorldMapHooked()
  local first = pins[1]
  local seen = ""
  if not (WorldMapFrame and WorldMapFrame:IsShown()) then seen = " (map closed now: open it, then /fox quests)"
  elseif first and first:IsShown() then
    local x, y = first:GetCenter()
    seen = string.format(" First mark: %s, %dx%d at %s, scale %.2f, alpha %.2f.", first:IsVisible() and "visible" or "not visible",
      math.floor(first:GetWidth() + 0.5), math.floor(first:GetHeight() + 0.5), (x and y) and (math.floor(x) .. "," .. math.floor(y)) or "nowhere",
      first:GetEffectiveScale() or 0, first:GetEffectiveAlpha() or 0)
  end
  return string.format("World map: %s; last drawn %d marks%s.%s Minimap: %d marks nearby.", hooked and "hooked" or "NOT hooked yet (open the map once)",
    drawn, lastMap and (" on map " .. lastMap) or "", seen, ns.MinimapNear and ns.MinimapNear() or 0)
    .. (ns.MinimapShown and (" " .. ns.MinimapShown() .. " on screen.") or "")
end
local function draw(child, shown)
  local n = 0
  local s = ns.settings or {}
  if s.questPins ~= false or s.questPinsAll ~= false then
    local w, h = child:GetWidth(), child:GetHeight()
    local zoomedOut = false
    if shown and C_Map and C_Map.GetMapInfo then
      local ok, info = pcall(C_Map.GetMapInfo, shown)
      zoomedOut = ok and type(info) == "table" and info.mapType ~= nil and info.mapType <= 2 -- world or continent
    end
    local rects = {}
    local function place(map, px, py)
      if map == shown then return true, px / 100, py / 100 end
      local rc = rects[map]
      if rc == nil then
        rc = false
        if shown and C_Map.GetMapRectOnMap then
          local okR, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, shown)
          -- an unrelated map comes back as an empty rect (all zeros): not on this map
          if okR and type(minX) == "number" and type(maxY) == "number" and maxX - minX > 0.0001 and maxY - minY > 0.0001 then
            rc = { minX, maxX, minY, maxY }
          end
        end
        rects[map] = rc
      end
      if not rc then return false end
      local x, y = rc[1] + (rc[2] - rc[1]) * px / 100, rc[3] + (rc[4] - rc[3]) * py / 100
      return x >= 0 and x <= 1 and y >= 0 and y <= 1, x, y
    end
    local level = ns.MapMarkLevel(child)
    local size = zoomedOut and 12 or (tonumber(s.questMarkSize) or 18)
    local list = {}
    for _, g in pairs(ns.QuestMarks()) do
      if #g.quests > 0 and (not zoomedOut or g.dungeon or g.turnin) then
        local ok, x, y = place(g.map, g.x, g.y)
        if ok then list[#list + 1] = { g = g, x = x * w, y = y * h } end
      end
    end
    -- turn-ins first, so a cluster with one shows "?"
    table.sort(list, function(a, b) if a.g.turnin ~= b.g.turnin then return a.g.turnin end; return a.x < b.x end)
    for _, c in ipairs(ns.ClusterMarks(list, size * 0.9)) do
      n = n + 1
      local p = pins[n] or ns.MakeQuestMark(child); pins[n] = p
      p:Set(c.g, size)
      p:ClearAllPoints(); p:SetPoint("CENTER", child, "TOPLEFT", c.x, -c.y)
      p:SetFrameLevel(level + (c.g.dungeon and 1 or 0))
      p:Show()
    end
  end
  for i = n + 1, #pins do pins[i]:Hide() end
  drawn, lastMap = n, shown
end
function ns.DrawQuestPins(child, shown)
  if not ns.Quests.Try("world map", draw, child, shown) then for _, p in ipairs(pins) do p:Hide() end end
end
