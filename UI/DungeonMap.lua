-- Foxden: the dungeon's own map on the game's world map. Inside a dungeon or raid, opening the
-- map (M) shows the dungeon's map picture over it, with its bosses: hover for the loot, click for
-- the loot list. Floor buttons for dungeons with more than one floor; "Game map" hides it until
-- the map is closed. Going to another map on the world map hides it too.
-- Boss spots are the Journal's Map tab ones (Modules/BossPins.lua). Setting: "Dungeon map on the world map".

local _, ns = ...
local UI = ns.UI
local C = UI.C

local overlay, canvas, floorButtons, gameBtn, note
local state -- { dungeon = name, bosses, floors, floor = index, mapID = world map's map when opened, off }

local function current()
  local inside, kind = IsInInstance()
  if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
  local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  local d = ns.Dungeons and ns.Dungeons[instanceID]
  local dname = d and d.name or name
  local floors = ns.DungeonFloors and ns.DungeonFloors(dname) or {}
  if #floors == 0 then return nil end
  return dname, d and d.bosses or {}, floors
end

-- The floor you're on, when the game says; else the first.
local function startFloor(floors)
  local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  for i, f in ipairs(floors) do if here and f.map == here then return i end end
  return 1
end

local function build()
  local host = WorldMapFrame and WorldMapFrame.ScrollContainer
  if overlay or not host then return overlay ~= nil end
  overlay = CreateFrame("Frame", nil, host)
  overlay:SetAllPoints(host)
  overlay:SetFrameLevel(host:GetFrameLevel() + 50)
  UI.Fill(overlay, { 0.05, 0.05, 0.07, 0.97 })
  overlay:EnableMouse(true) -- the game's map underneath doesn't take clicks while this shows

  canvas = UI.MapCanvas(overlay)
  canvas.onClick = function(_, _, button)
    if button == "RightButton" and state then state.off = true; overlay:Hide() end
  end
  canvas.onPin = function(name, button, pin)
    if button == "LeftButton" and ns.ShowBossLootPopup and state then
      ns.ShowBossLootPopup(pin, state.dungeon, name)
      -- above the world map, which can be full screen
      if FoxdenBossLoot then FoxdenBossLoot:SetFrameStrata("FULLSCREEN_DIALOG") end
    end
  end
  canvas.onPinEnter = function(pin, tip)
    tip:SetText(pin.label or "Boss")
    if pin.sub then tip:AddLine(pin.sub, 0.7, 0.72, 0.78) end
    tip:AddLine("Click: loot list", 0.55, 0.85, 0.55)
  end

  gameBtn = UI.Button(overlay, "Game map", 90, 22, function()
    if state then state.off = true end
    overlay:Hide()
  end)
  gameBtn:SetPoint("TOPRIGHT", -8, -8)
  note = UI.Text(overlay, 11, C.faint); note:SetPoint("BOTTOMLEFT", 10, 8)
  floorButtons = {}
  return true
end

local function draw()
  if not (state and overlay) then return end
  local w, h = overlay:GetWidth() or 0, overlay:GetHeight() or 0
  if w < 50 or h < 50 then return end
  local top = #state.floors > 1 and 36 or 8
  local mw = math.min(w - 16, (h - top - 26) * 1.5)
  local mh = mw / 1.5
  local floor = state.floors[state.floor]

  local pins, unplaced = {}, 0
  local pinPx = math.floor(40 * (ns.settings and ns.settings.bossPinScale or 0.8) + 0.5)
  for i, b in ipairs(state.bosses) do
    if not b.wing then
      local f, x, y -- (`a and f()` keeps only f's first result)
      if ns.BossPin then f, x, y = ns.BossPin(state.dungeon, b.name) end
      if f and ns.PinOnFloor(f, floor, state.floor) then
        pins[#pins + 1] = { x = x, y = y, n = i, key = b.name, label = b.name, sub = b.level and ("Level " .. b.level) or nil,
          boss = true, look = ns.BossLook and ns.BossLook(state.dungeon, b.name), size = pinPx }
      elseif not f then unplaced = unplaced + 1 end
    end
  end
  canvas:ClearAllPoints(); canvas:SetPoint("TOP", overlay, "TOP", 0, -top)
  canvas:Draw(floor.map, mw, mh, pins, floor.tiles, floor)

  for i, f in ipairs(state.floors) do
    local b = floorButtons[i]
    if not b then
      b = UI.Button(overlay, "", 80, 22, function(btn) state.floor = btn.i; draw() end)
      floorButtons[i] = b
    end
    b.i = i
    b.label:SetText(f.name or ("Floor " .. i))
    b:SetWidth(math.min(170, b.label:GetStringWidth() + 20))
    b:ClearAllPoints()
    if i == 1 then b:SetPoint("TOPLEFT", 8, -8) else b:SetPoint("LEFT", floorButtons[i - 1], "RIGHT", 6, 0) end
    if i == state.floor then b.label:SetTextColor(UI.Accent()) else b.label:SetTextColor(unpack(C.text)) end
    b:SetShown(#state.floors > 1)
  end
  for i = #state.floors + 1, #floorButtons do floorButtons[i]:Hide() end
  note:SetText(state.dungeon
    .. (unplaced > 0 and ("  ·  " .. unplaced .. " not placed yet (Foxden > Dungeons > Map)") or "")
    .. "  ·  right-click or Game map for the game's map")
end

local function refresh()
  if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
  if ns.settings and ns.settings.dungeonWorldMap == false then if overlay then overlay:Hide() end; return end
  local dname, bosses, floors = current()
  if not dname then if overlay then overlay:Hide() end; state = nil; return end
  if not build() then return end
  local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  if not state or state.dungeon ~= dname then
    state = { dungeon = dname, bosses = bosses, floors = floors, floor = startFloor(floors), mapID = mapID }
  end
  state.mapID = state.mapID or mapID
  -- went to another map on the world map: leave the game's map showing
  if state.off or (state.mapID and mapID and mapID ~= state.mapID) then overlay:Hide(); return end
  overlay:Show()
  draw()
end

ns.RegisterModule({
  name = "DungeonMap",
  events = {
    PLAYER_LOGIN = function()
      if not WorldMapFrame then return end
      WorldMapFrame:HookScript("OnShow", function()
        -- a fresh look each time the map opens
        -- (the map it settles on is recorded by refresh: the game can change it while opening)
        if state then state.off = nil; state.mapID = nil end
        C_Timer.After(0, refresh)
      end)
      WorldMapFrame:HookScript("OnHide", function() if state then state.off = nil end end)
      if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() C_Timer.After(0, refresh) end) end
      if WorldMapFrame.ScrollContainer then WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", function() if overlay and overlay:IsShown() then draw() end end) end
    end,
    PLAYER_ENTERING_WORLD = function() state = nil; if overlay then overlay:Hide() end end,
  },
})
