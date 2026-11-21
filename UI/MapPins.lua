-- Foxden: guildmates who share their location, as class-colored dots on the
-- world map (with name, zone and how fresh it is on hover), and the map pins the
-- guild has shared from notes (small diamonds: hover for the note), and dungeon quest
-- givers (UI/QuestPins.lua). Works on the zone map and zoomed out to the continent.

local _, ns = ...
local UI = ns.UI
local pins = {}

local function canvas()
  if not WorldMapFrame then return nil end
  -- the map's own canvas (what Questie's map library uses); the scroll child is the same frame on most clients
  if WorldMapFrame.GetCanvas then local ok, c = pcall(WorldMapFrame.GetCanvas, WorldMapFrame); if ok and type(c) == "table" and c.GetWidth then return c end end
  return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function classOf(key)
  for _, m in ipairs(ns.db and ns.db.roster and ns.db.roster.members or {}) do if ns.SenderKey(m.name) == key then return m.class end end
end

local function pin(i, parent)
  local p = pins[i]
  if not p then
    p = CreateFrame("Frame", nil, parent)
    p:SetSize(12, 12)
    p.ring = p:CreateTexture(nil, "ARTWORK"); p.ring:SetAllPoints(); p.ring:SetColorTexture(0, 0, 0, 0.9)
    p.dot = p:CreateTexture(nil, "OVERLAY"); p.dot:SetPoint("TOPLEFT", 2, -2); p.dot:SetPoint("BOTTOMRIGHT", -2, 2)
    for _, t in ipairs({ p.ring, p.dot }) do pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    p.icon = p:CreateTexture(nil, "OVERLAY", nil, 1); p.icon:SetPoint("TOPLEFT", 2, -2); p.icon:SetPoint("BOTTOMRIGHT", -2, 2); p.icon:Hide()
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:SetText(s.name or "Guildmate")
      if s.note then GameTooltip:AddLine(s.note, 1, 1, 1, true) end
      if s.zone then GameTooltip:AddLine(s.zone, 1, 1, 1) end
      if s.age and not s.note then GameTooltip:AddLine(s.age < 60 and "Just now" or (math.floor(s.age / 60) .. " min ago"), 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    pins[i] = p
  end
  return p
end

local hookMap -- below
local function refreshGuildPins()
  local child = canvas()
  if not child or not WorldMapFrame:IsShown() then return end
  local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  local w, h = child:GetWidth(), child:GetHeight()
  local now, n = GetServerTime(), 0
  for key, l in pairs(ns.GuildLocations and ns.GuildLocations() or {}) do
    if not ns.IsMe(key) then
      local x, y, ok = l.x / 1000, l.y / 1000, l.map == shown
      if not ok and shown and C_Map.GetMapRectOnMap then
        local okR, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, l.map, shown)
        if okR and minX then
          x, y = minX + (maxX - minX) * x, minY + (maxY - minY) * y
          ok = x >= 0 and x <= 1 and y >= 0 and y <= 1
        end
      end
      if ok then
        n = n + 1
        local p = pin(n, child)
        p.name, p.note, p.zone, p.age = key:match("^[^-]+") or key, nil, l.zone, now - (l.at or now)
        p:SetSize(18, 18)
        local cls = classOf(key)
        local r, g, b = UI.ClassColor(cls)
        p.ring:SetColorTexture(r, g, b, 1) -- class-coloured ring around the class icon
        p.dot:SetColorTexture(r, g, b)
        p.icon:SetShown(UI.SetClassIcon(p.icon, cls, true))
        p:ClearAllPoints(); p:SetPoint("CENTER", child, "TOPLEFT", x * w, -y * h)
        p:SetFrameLevel((child:GetFrameLevel() or 1) + 20)
        p:Show()
      end
    end
  end
  -- pins from notes: yours, and guildmates' from the website snapshot
  local function place(map, px, py)
    local x, y, ok = px / 100, py / 100, map == shown
    if not ok and shown and C_Map.GetMapRectOnMap then
      local okR, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, shown)
      if okR and minX then
        x, y = minX + (maxX - minX) * x, minY + (maxY - minY) * y
        ok = x >= 0 and x <= 1 and y >= 0 and y <= 1
      end
    end
    return ok, x, y
  end
  local function notePin(by, text, map, px, py, zone)
    local ok, x, y = place(map, px, py)
    if not ok then return end
    n = n + 1
    local p = pin(n, child)
    p.name, p.note, p.zone, p.age = "Note from " .. by, text ~= "" and text or nil, zone ~= "" and zone or nil, nil
    p.dot:SetColorTexture(UI.Accent())
    p:SetSize(12, 12); p.icon:Hide(); p.ring:SetColorTexture(0, 0, 0, 0.9)
    p:ClearAllPoints(); p:SetPoint("CENTER", child, "TOPLEFT", x * w, -y * h)
    p:SetFrameLevel((child:GetFrameLevel() or 1) + 19)
    p:Show()
  end
  local me = ns.Member and ns.Member()
  for _, pn in ipairs(me and me.pins or {}) do notePin("you", pn.t or "", pn.map, pn.x, pn.y, pn.zone or "") end
  local site = ns.Site and ns.Site()
  for _, r in ipairs(site and type(site.pins) == "table" and site.pins or {}) do
    if not ns.IsMe(r[1]) then notePin(r[1], r[2] or "", r[3], r[4], r[5], r[6] or "") end
  end
  for i = n + 1, #pins do pins[i]:Hide() end
end

function ns.RefreshMapPins()
  hookMap()
  local child = canvas()
  if not child or not WorldMapFrame:IsShown() then return end
  if ns.Quests then ns.Quests.Try("guild pins", refreshGuildPins) else pcall(refreshGuildPins) end
  if ns.DrawQuestPins then ns.DrawQuestPins(child, WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()) end
  if ns.DrawGuildZones then
    if ns.Quests then ns.Quests.Try("guild zones", ns.DrawGuildZones, child, WorldMapFrame.GetMapID and WorldMapFrame:GetMapID())
    else pcall(ns.DrawGuildZones, child, WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()) end
  end
  if ns.DrawEntrancePins then
    if ns.Quests then ns.Quests.Try("dungeon entrances", ns.DrawEntrancePins, child, WorldMapFrame.GetMapID and WorldMapFrame:GetMapID())
    else pcall(ns.DrawEntrancePins, child, WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()) end
  end
end

-- Hook the world map. It may load after you log in (load-on-demand), so also wait for it.
local hooked = false
function ns.WorldMapHooked() return hooked end
function hookMap()
  if hooked or not WorldMapFrame then return end
  hooked = true
  WorldMapFrame:HookScript("OnShow", function() ns.RefreshMapPins() end)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() ns.RefreshMapPins() end) end
  C_Timer.NewTicker(5, function() if WorldMapFrame:IsShown() then ns.RefreshMapPins() end end)
  if ns.Quests then ns.Quests.OnChange(function() if WorldMapFrame:IsShown() then ns.RefreshMapPins() end end) end
  if WorldMapFrame:IsShown() then ns.RefreshMapPins() end
end

-- (the core only passes on its own ADDON_LOADED, so this one has its own listener)
local waiter = CreateFrame("Frame")
waiter:RegisterEvent("ADDON_LOADED")
waiter:SetScript("OnEvent", function(self, _, name)
  if name == "Blizzard_WorldMap" or WorldMapFrame then hookMap() end
  if hooked then self:UnregisterEvent("ADDON_LOADED") end
end)

ns.RegisterModule({
  name = "MapPins",
  events = { PLAYER_LOGIN = function() hookMap() end },
})

-- /fox marktest: a big red badge in the middle of the open world map and on the minimap for
-- 15 seconds, and what the game says about them. For finding out why marks don't show.
function ns.MarkTest()
  local say = function(t) if ns.say then ns.say(t, true) else print(t) end end
  local c = canvas()
  local function info(f) if not f then return "missing" end
    return (f:IsShown() and "shown" or "hidden") .. "/" .. (f:IsVisible() and "visible" or "not visible") .. string.format(" lvl %d %s", f:GetFrameLevel() or 0, f:GetFrameStrata() or "?") end
  say("Map window: " .. info(WorldMapFrame) .. ". Canvas: " .. info(c) .. (c and string.format(" %dx%d", c:GetWidth() or 0, c:GetHeight() or 0) or "")
    .. (WorldMapFrame and WorldMapFrame.ScrollContainer and c ~= WorldMapFrame.ScrollContainer.Child and " (not the scroll child)" or ""))
  local made = {}
  local function badge(parent, size, level)
    local b = ns.MakeQuestMark(parent)
    b:Set({ npc = "Foxden test", quests = { { title = "Test mark", kind = "new" } } }, size)
    b:ClearAllPoints(); b:SetPoint("CENTER", parent, "CENTER", 0, 0)
    b:SetFrameStrata(parent:GetFrameStrata())
    b:SetFrameLevel(parent == Minimap and math.min(9000, (parent:GetFrameLevel() or 1) + level) or (ns.MapMarkLevel and ns.MapMarkLevel(parent) or level))
    b:Show(); made[#made + 1] = b
    return b
  end
  if c and WorldMapFrame:IsShown() then
    local b = badge(c, 60, 600)
    say("Test mark on the map: " .. info(b) .. ". You should see a big gold ! in the middle of the map.")
  else
    say("Open the world map first, then /fox marktest again.")
  end
  if Minimap then
    local m = badge(Minimap, 30, 60)
    say("Test mark on the minimap: " .. info(m) .. ". You should see a gold ! in its middle.")
  end
  C_Timer.After(15, function() for _, b in ipairs(made) do b:Hide() end end)
end