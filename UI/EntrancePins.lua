-- Foxden: dungeon and raid entrances on the world map (QuestieDB's dungeon list, see
-- Core/QuestSource.lua). A skull in a ring coloured by the dungeon's level for you;
-- hover for its name and levels, click to open it in Foxden, shift-click for the arrow.
-- Shows on the zone map and zoomed out to the continent. Drawn by UI/MapPins.lua.

local _, ns = ...
local UI = ns.UI
local pins = {}
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local bySlug
local function dungeonFor(slug)
  if not bySlug then
    bySlug = {}
    for id, d in pairs(ns.Dungeons or {}) do bySlug[ns.Slug(d.name)] = { id = id, d = d } end
  end
  return bySlug[slug]
end

local function pin(i, parent)
  local p = pins[i]
  if not p then
    p = CreateFrame("Button", nil, parent)
    p.ring = p:CreateTexture(nil, "ARTWORK"); p.ring:SetAllPoints()
    p.bg = p:CreateTexture(nil, "ARTWORK", nil, 1); p.bg:SetPoint("TOPLEFT", 2, -2); p.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    p.bg:SetColorTexture(0.06, 0.06, 0.08, 0.95)
    for _, t in ipairs({ p.ring, p.bg }) do pcall(t.SetMask, t, MASK) end
    p.icon = p:CreateTexture(nil, "OVERLAY"); p.icon:SetPoint("TOPLEFT", 4, -4); p.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    p.icon:SetTexture(SKULL)
    p:RegisterForClicks("LeftButtonUp")
    p:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      local d = s.dungeon
      GameTooltip:SetText((d and d.name or s.name) .. " entrance")
      if d then
        local lv = d.levels
        if lv then
          local r, g, b = 1, 0.82, 0
          if ns.Quests and ns.Quests.Color then r, g, b = ns.Quests.Color(math.floor((lv[1] + lv[2]) / 2)) end
          GameTooltip:AddLine((d.raid and "Raid, level " or "Dungeon, levels ") .. (lv[1] == lv[2] and lv[1] or (lv[1] .. "-" .. lv[2])), r, g, b)
        end
        if d.wings then
          local names = {}
          for _, w in ipairs(d.wings) do names[#names + 1] = w.name end
          GameTooltip:AddLine("Wings: " .. table.concat(names, ", "), 1, 1, 1, true)
        end
        if d.bosses and #d.bosses > 0 then GameTooltip:AddLine(#d.bosses .. " bosses", 0.7, 0.72, 0.78) end
        GameTooltip:AddLine("Click to open it in Foxden.", 0.7, 0.72, 0.78)
      end
      GameTooltip:AddLine("Shift-click for the arrow.", 0.7, 0.72, 0.78)
      GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    p:SetScript("OnClick", function(s)
      local name = s.dungeon and s.dungeon.name or s.name
      if IsShiftKeyDown() then
        if ns.SetArrow then ns.SetArrow(s.map, s.x, s.y, name .. " entrance") end
      elseif s.dungeon and ns.OpenPage then
        ns.OpenPage("journal", { dungeon = name })
      end
    end)
    pins[i] = p
  end
  return p
end

function ns.DrawEntrancePins(child, shown)
  local n = 0
  if child and shown and ns.settings.entrancePins ~= false then
    local w, h = child:GetWidth(), child:GetHeight()
    local level = ns.MapMarkLevel and ns.MapMarkLevel(child) or ((child:GetFrameLevel() or 1) + 20)
    local size = (ns.settings.questMarkSize or 18) + 2
    for _, e in ipairs(ns.DungeonEntrances and ns.DungeonEntrances() or {}) do
      local x, y, ok, zoomed = e.x / 100, e.y / 100, e.map == shown, false
      if not ok and C_Map.GetMapRectOnMap then
        local okR, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, e.map, shown)
        if okR and minX then
          x, y = minX + (maxX - minX) * x, minY + (maxY - minY) * y
          ok, zoomed = x >= 0 and x <= 1 and y >= 0 and y <= 1, true
        end
      end
      if ok then
        n = n + 1
        local p = pin(n, child)
        local found = dungeonFor(e.slug)
        p.dungeon, p.name, p.map, p.x, p.y = found and found.d, e.name, e.map, e.x, e.y
        local s = zoomed and math.floor(size * 0.8) or size
        if p.dungeon and p.dungeon.raid then s = s + 4 end
        p:SetSize(s, s)
        local r, g, b = 0.6, 0.6, 0.6
        local lv = p.dungeon and p.dungeon.levels
        if lv and ns.Quests and ns.Quests.Color then r, g, b = ns.Quests.Color(math.floor((lv[1] + lv[2]) / 2)) end
        p.ring:SetColorTexture(r, g, b, 1)
        p:ClearAllPoints(); p:SetPoint("CENTER", child, "TOPLEFT", x * w, -y * h)
        p:SetFrameStrata(child:GetFrameStrata())
        p:SetFrameLevel(math.max(1, level - 1)) -- under quest marks, which can share a spot
        p:Show()
      end
    end
  end
  for i = n + 1, #pins do pins[i]:Hide() end
end
