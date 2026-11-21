-- Foxden: where guildmates are, for everyone online, even without Foxden. The game only tells
-- addons another player's zone (the guild roster), not their spot, so this is one badge per zone
-- on the world map: how many guildmates are there, names on hover. Guildmates who share their
-- exact position with Foxden are dots instead (UI/MapPins.lua) and aren't counted twice. Someone
-- inside a dungeon shows at its entrance. Setting: "Guildmates' zones on the world map".

local _, ns = ...
local UI = ns.UI
local badges = {}
local mapByName -- zone name (lowercase) -> uiMapID

local function zoneMap(name)
  if not name or name == "" then return nil end
  if not mapByName then
    mapByName = {}
    if C_Map and C_Map.GetMapInfo then
      for id = 1, 3000 do
        local ok, i = pcall(C_Map.GetMapInfo, id)
        -- zones and cities first (3), then micro and orphan maps; the first of each name wins
        if ok and type(i) == "table" and i.name and i.mapType and not ns.IsSecret(i.mapType) and i.mapType >= 3 then
          local k = i.name:lower()
          local have = mapByName[k]
          if not have or (have.type ~= 3 and i.mapType == 3) then mapByName[k] = { id = id, type = i.mapType } end
        end
      end
    end
  end
  local e = mapByName[name:lower()]
  return e and e.id
end

-- 0..1 spot of a zone (its middle) or a map point on the shown map, or nil when it's not on it
local function onShown(map, x, y, shown)
  if map == shown then return x, y end
  if not (C_Map.GetMapRectOnMap and shown) then return nil end
  local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, shown)
  if not ok or type(minX) ~= "number" or ns.IsSecret(minX) then return nil end
  local px, py = minX + (maxX - minX) * x, minY + (maxY - minY) * y
  if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
  return px, py
end

local function badge(i, parent)
  local b = badges[i]
  if not b then
    b = CreateFrame("Frame", nil, parent)
    b:SetSize(22, 22)
    b.ring = b:CreateTexture(nil, "ARTWORK"); b.ring:SetAllPoints()
    b.bg = b:CreateTexture(nil, "ARTWORK", nil, 1); b.bg:SetPoint("TOPLEFT", 2, -2); b.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    b.bg:SetColorTexture(0.06, 0.06, 0.08, 0.95)
    for _, t in ipairs({ b.ring, b.bg }) do pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.num = UI.Text(b, 11, nil, "CENTER"); b.num:SetPoint("CENTER", 0, 0)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:SetText(s.zone .. (s.dungeon and " (inside)" or ""))
      for _, m in ipairs(s.members) do
        local r, g, bl = UI.ClassColor(m.class)
        GameTooltip:AddDoubleLine((m.name:match("^[^-]+") or m.name), m.level and ("Level " .. m.level) or "", r, g, bl, 0.7, 0.72, 0.78)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Zone only: the game doesn't share where in the zone. Guildmates sharing their location with Foxden are dots instead.", 0.6, 0.63, 0.69, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    badges[i] = b
  end
  return b
end

function ns.DrawGuildZones(child, shown)
  local n = 0
  local on = ns.settings and ns.settings.guildZones ~= false and child and shown
  if on then
    if ns.RequestRoster then ns.RequestRoster() end -- fresh zones next time (the game throttles it)
    local exact = ns.GuildLocations and ns.GuildLocations() or {}
    local byZone = {}
    for _, m in ipairs(ns.db and ns.db.roster and ns.db.roster.members or {}) do
      if m.online and not m.mobile and m.zone and m.zone ~= "" and not ns.IsMe(m.name) and not exact[ns.SenderKey(m.name)] then
        byZone[m.zone] = byZone[m.zone] or {}
        table.insert(byZone[m.zone], m)
      end
    end
    local w, h = child:GetWidth(), child:GetHeight()
    local r, g, b = UI.Accent()
    for zone, members in pairs(byZone) do
      local x, y, dungeon
      local map = zoneMap(zone)
      local em, ex, ey = ns.DungeonEntrance and ns.DungeonEntrance(zone)
      if em then x, y = onShown(em, ex / 100, ey / 100, shown); dungeon = true
      elseif map then
        -- on the zone's own map: top middle, out of the way; zoomed out: the zone's middle
        if map == shown then x, y = 0.5, 0.06 else x, y = onShown(map, 0.5, 0.5, shown) end
      end
      if x then
        n = n + 1
        table.sort(members, function(a, c) return (a.level or 0) > (c.level or 0) end)
        local p = badge(n, child)
        p.zone, p.members, p.dungeon = zone, members, dungeon
        p.ring:SetColorTexture(r, g, b, 1)
        p.num:SetText(#members)
        p:ClearAllPoints(); p:SetPoint("CENTER", child, "TOPLEFT", x * w, -y * h)
        p:SetFrameLevel((child:GetFrameLevel() or 1) + 18)
        p:Show()
      end
    end
  end
  for i = n + 1, #badges do badges[i]:Hide() end
end
