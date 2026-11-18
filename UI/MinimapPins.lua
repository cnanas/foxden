-- Foxden: quest marks on the minimap, the same ones as the world map (ns.QuestMarks): "!" for
-- quests you can pick up, "?" for turn-ins, ringed for dungeon quests.
--
-- How a mark finds its place: every spot is turned into world coordinates once (yards), and
-- every couple of seconds the ones within reach of you are picked out. Then, a few times a
-- second, each is placed by its distance from you at the minimap's current scale (its zoom
-- level, indoors or out), turned with the minimap when it rotates, and hidden past the edge.

local _, ns = ...
local UI = ns.UI
-- The minimap's width in yards at each zoom level (0-5).
local OUTDOOR = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 3, [4] = 200, [5] = 133 + 1 / 3 }
local INDOOR = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 }
local REACH = 700 -- yards: look this far for marks (wider than the minimap at its widest)

local pins, near = {}, {}
ns.minimapPinFrames = pins
local world = {} -- [mapID .. ":" .. x .. ":" .. y] = { continent, wx, wy } or false
local driver, lastPick = nil, 0

local function worldOf(map, x, y)
  local k = map .. ":" .. x .. ":" .. y
  local w = world[k]
  if w == nil then
    w = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
      local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
      if ok and cont and v and v.GetXY then local wx, wy = v:GetXY(); w = { cont, wx, wy } end
    end
    world[k] = w
  end
  return w
end

local function playerWorld()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not okM or type(map) ~= "number" or ns.IsSecret(map) then return nil end
  local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not okP or not pos then return nil end
  local px, py = pos:GetXY()
  if type(px) ~= "number" or ns.IsSecret(px) or (px == 0 and py == 0) then return nil end
  local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
  if not ok or not cont or not v then return nil end
  local wx, wy = v:GetXY()
  return cont, wx, wy
end

local function enabled() return ns.settings and ns.settings.questMinimap ~= false and Minimap ~= nil end

-- The marks within reach of you (every couple of seconds, or when quests change).
local function pick()
  wipe(near)
  if not enabled() or not ns.QuestMarks then return end
  local cont, px, py = playerWorld()
  if not cont then return end
  for _, g in pairs(ns.QuestMarks()) do
    if #g.quests > 0 then
      local w = worldOf(g.map, g.x, g.y)
      if w and w[1] == cont and math.abs(w[2] - px) < REACH and math.abs(w[3] - py) < REACH then near[#near + 1] = { g = g, w = w } end
    end
  end
end

local function place()
  local n = 0
  if enabled() and #near > 0 then
    local cont, px, py = playerWorld()
    if cont then
      local zoom = Minimap:GetZoom() or 0
      local indoors = IsIndoors and IsIndoors()
      local yards = (indoors and INDOOR or OUTDOOR)[zoom] or OUTDOOR[0]
      local radius = (Minimap:GetWidth() or 140) / 2
      local scale = radius / (yards / 2)
      local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
      local c, s = 1, 0
      if rotate and GetPlayerFacing then
        local a = GetPlayerFacing() or 0
        c, s = math.cos(a), math.sin(a)
      end
      local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
      local list = {}
      for _, m in ipairs(near) do
        -- world X runs north, world Y runs west
        local east, north = -(m.w[3] - py), m.w[2] - px
        if rotate then east, north = east * c + north * s, -east * s + north * c end
        local x, y = east * scale, north * scale
        local inside = square and (math.abs(x) <= radius - 6 and math.abs(y) <= radius - 6) or (x * x + y * y <= (radius - 6) ^ 2)
        if inside then list[#list + 1] = { g = m.g, x = x, y = y } end
      end
      for _, cl in ipairs(ns.ClusterMarks(list, 12)) do
        n = n + 1
        local p = pins[n] or ns.MakeQuestMark(Minimap); pins[n] = p
        p:Set(cl.g, 14)
        p:ClearAllPoints(); p:SetPoint("CENTER", Minimap, "CENTER", cl.x, cl.y)
        -- above minimap skins' borders and masks
        p:SetFrameStrata(Minimap:GetFrameStrata()); p:SetFrameLevel(math.min(9000, (Minimap:GetFrameLevel() or 1) + 60))
        p:Show()
      end
    end
  end
  for i = n + 1, #pins do pins[i]:Hide() end
end

function ns.RefreshMinimapPins() lastPick = 0 end
function ns.MinimapPinsTick() pick(); place() end -- for /fox debugging and the test harness
function ns.MinimapNear() return #near end
function ns.MinimapShown() local n = 0; for _, p in ipairs(pins) do if p:IsVisible() then n = n + 1 end end; return n end

ns.RegisterModule({
  name = "MinimapPins",
  events = {
    PLAYER_LOGIN = function()
      if not Minimap then return end
      driver = CreateFrame("Frame")
      local acc = 0
      driver:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.08 then return end
        acc = 0
        local now = GetTime()
        if now - lastPick > 2 then
          lastPick = now
          if not ns.Quests.Try("minimap", pick) then wipe(near) end
        end
        if not ns.Quests.Try("minimap", place) then wipe(near); for _, p in ipairs(pins) do p:Hide() end end
      end)
      if ns.Quests then ns.Quests.OnChange(function() lastPick = 0 end) end
    end,
    ZONE_CHANGED_NEW_AREA = function() lastPick = 0 end,
  },
})
