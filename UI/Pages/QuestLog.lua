-- Page: Your quests. Your quest log as a picture card per zone (the zone's own map as the
-- art): how many quests, how many are ready to turn in, dungeon quests. Hover a card for its
-- quests; click to open the world map on that zone. Single quests live in the quest tracker.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local PAD, GAP = 16, 14

local page = { key = "questlog", label = "Your quests", order = 59 }

-- A piece of the zone's map to use as its card art: one of the map's 256px tiles, from the
-- middle of the 4 x 3 grid (the map API's art, else the client's own map pictures).
-- Quest log headers can be a dungeon's name (its quests): those get the dungeon's own art.
local dungeonByName
local function zoneArt(name, map)
  if not dungeonByName then
    dungeonByName = {}
    for id, d in pairs(ns.Dungeons or {}) do dungeonByName[ns.Slug(d.name)] = id end
  end
  local id = dungeonByName[ns.Slug(name)]
  if id and ns.DungeonArt and ns.DungeonArt[id] then return ns.DungeonArt[id], true end
  if not (map and C_Map and C_Map.GetMapArtLayerTextures) then return nil end
  local ok, tex = pcall(C_Map.GetMapArtLayerTextures, map, 1)
  if ok and type(tex) == "table" and #tex >= 7 then return { tex[6], "square" } end
  if ok and type(tex) == "table" and tex[1] then return { tex[1], "square" } end
end

function page:Build(f)
  self.scroll = CreateFrame("ScrollFrame", nil, f)
  self.scroll:EnableMouseWheel(true)
  self.body = CreateFrame("Frame", nil, self.scroll)
  self.scroll:SetScrollChild(self.body)
  self.scroll:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, (self.body:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, (sf:GetVerticalScroll() or 0) - d * 40)))
  end)
  local b = self.body
  self.total = UI.Tile(b); self.total.onClick = function() if ToggleQuestLog then ToggleQuestLog() end end
  self.ready = UI.Tile(b)
  self.helper = UI.Tile(b); self.helper.onClick = function() ns.OpenPage("quests") end
  self.head = UI.Text(b, 15); self.head:SetText("By zone")
  self.empty = UI.Text(b, 12, C.dim); self.empty:SetWordWrap(true)
  self.cards = {}
end

function page:Layout(w, h)
  self.w, self.h = w, h
  self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", 0, 0); self.scroll:SetSize(w, h)
  self.body:SetWidth(w)
  local inner = w - PAD * 2
  local tw = math.floor((inner - GAP * 2) / 3)
  for i, t in ipairs({ self.total, self.ready, self.helper }) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + GAP), -PAD); t:SetSize(tw, 118)
  end
  local y = -PAD - 118 - GAP - 4
  self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", PAD, y - 4)
  self.cardTop = y - 24 - 10
  self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT", PAD, self.cardTop); self.empty:SetWidth(inner)
  self.cols = inner >= 760 and 3 or 2
  self.cardW = math.floor((inner - GAP * (self.cols - 1)) / self.cols)
  self.cardH = math.max(92, math.min(118, math.floor(self.cardW * 0.38)))
end

function page:Refresh()
  local groups = ns.Quests and ns.Quests.Log() or {}
  local total, ready, dungeon = 0, 0, 0
  local zones = {}
  for _, g in ipairs(groups) do
    local z = { name = g.header or "Other", quests = {}, ready = 0, dungeon = 0 }
    for _, q in ipairs(g.quests or {}) do
      z.quests[#z.quests + 1] = q
      total = total + 1
      if q.complete then z.ready = z.ready + 1; ready = ready + 1 end
      if ns.QuestInstance and ns.QuestInstance(q.id) then z.dungeon = z.dungeon + 1; dungeon = dungeon + 1 end
    end
    if #z.quests > 0 then zones[#zones + 1] = z end
  end
  local maxQ = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 20
  self.total:Set({ title = "Quest log", big = tostring(total), unit = "of " .. maxQ,
    body = dungeon > 0 and (dungeon .. (dungeon == 1 and " dungeon quest" or " dungeon quests")) or "Click to open the game's quest log.",
    icon = "Interface\\Icons\\INV_Misc_Book_08" })
  self.ready:Set({ title = "Ready to turn in", big = tostring(ready), unit = ready == 1 and "quest" or "quests",
    body = ready > 0 and "Their turn-ins show as ? on your map." or "Nothing ready yet.",
    bigColor = ready > 0 and { 0.43, 0.83, 0.6, 1 } or nil, icon = "Interface\\GossipFrame\\ActiveQuestIcon" })
  self.helper:Set({ title = "Quest helper", big = "Settings", body = "Map and minimap marks, which quests show, the quest tracker.",
    icon = "Interface\\Icons\\INV_Misc_Spyglass_03" })

  for i, z in ipairs(zones) do
    local c = self.cards[i]
    if not c then
      c = UI.ArtCard(self.body)
      c.onClick = function(card)
        if card.map then if OpenWorldMap then pcall(OpenWorldMap, card.map) end
        else ns.OpenPage("journal", { dungeon = card.zone.name, view = "quests" }) end
      end
      c.onEnter = function(card)
        GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
        GameTooltip:SetText(card.zone.name)
        for _, q in ipairs(card.zone.quests) do
          local r, g, b = 1, 0.82, 0
          if ns.Quests and ns.Quests.Color then r, g, b = ns.Quests.Color(q.level) end
          GameTooltip:AddDoubleLine("[" .. (q.level or "?") .. "] " .. (q.title or "?"), q.complete and "ready" or "", r, g, b, 0.43, 0.83, 0.6)
        end
        GameTooltip:AddLine(card.map and "Click: open the map on this zone" or "Click: open this dungeon in Foxden", 0.55, 0.85, 0.55)
        GameTooltip:Show()
      end
      self.cards[i] = c
    end
    c.zone = z
    c.map = ns.ZoneMapID and ns.ZoneMapID(z.name)
    local right = {}
    if z.ready > 0 then right[#right + 1] = "|cff6fd39a" .. z.ready .. " ready|r" end
    if z.dungeon > 0 then right[#right + 1] = "|cff8fb3ff" .. z.dungeon .. (z.dungeon == 1 and " dungeon|r" or " dungeons|r") end
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", PAD + ((i - 1) % self.cols) * (self.cardW + GAP), self.cardTop - math.floor((i - 1) / self.cols) * (self.cardH + GAP))
    c:SetSize(self.cardW, self.cardH)
    local art, isDungeon = zoneArt(z.name, c.map)
    if isDungeon then c.map = nil end -- a dungeon: no world map to open
    c:Set({ art = art, title = z.name, tag = #z.quests .. (#z.quests == 1 and " quest" or " quests"),
      tagDone = z.ready == #z.quests, bottomLeft = nil, bottomRight = table.concat(right, "   ") })
    c:Show()
  end
  for i = #zones + 1, #self.cards do self.cards[i]:Hide() end
  self.empty:SetShown(#zones == 0)
  self.empty:SetText("Your quest log is empty. Quest givers near you show as ! on your map.")
  local rows = math.max(1, math.ceil(#zones / self.cols))
  self.body:SetHeight(-self.cardTop + rows * (self.cardH + GAP) + PAD)
end

ns.RegisterPage(page)
